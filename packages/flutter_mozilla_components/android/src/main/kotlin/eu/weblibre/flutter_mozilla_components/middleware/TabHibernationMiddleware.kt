/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components.middleware

import mozilla.components.browser.state.action.BrowserAction
import mozilla.components.browser.state.action.EngineAction
import mozilla.components.browser.state.action.TabListAction
import mozilla.components.browser.state.selector.findTab
import mozilla.components.browser.state.state.BrowserState
import mozilla.components.browser.state.store.BrowserStore
import mozilla.components.lib.state.Middleware
import mozilla.components.lib.state.Store
import mozilla.components.support.base.log.logger.Logger

/**
 * Tab hibernation: frees the RAM of background tabs the user has not looked
 * at for a while, without closing them.
 *
 * Android Components has exactly this mechanism — [EngineAction.SuspendEngineSessionAction]
 * unlinks a tab's engine session and closes it (taking the sandboxed content
 * process with it) while keeping the serialized `EngineSessionState`, so a new
 * session restores the full back/forward history. The stock policy driving
 * it, `TrimMemoryMiddleware`, only fires under system memory pressure;
 * WebLibre disables even that (`EngineMiddleware.create(trimMemoryAutomatically = false)`).
 *
 * This middleware is the *wake* side of an opt-in, time-based policy: Dart
 * decides which background tabs have been idle past the threshold and asks for
 * them over the hibernation method channel (`TabHibernationApiImpl`); those
 * dispatches run through [suspendTabs] and mark the tabs here. The next
 * selection of a marked tab dispatches [EngineAction.CreateEngineSessionAction],
 * which rebuilds and links a fresh session — in the same
 * `SessionState.contextId`, so container isolation survives the cycle.
 *
 * Only tabs suspended by this policy wake here. Tabs restored from disk are
 * deliberately left alone: whatever lazy behaviour the rest of the app applies
 * to them is unchanged.
 *
 * All entry points run on the main thread (store middleware and the method
 * channel handler), so the mark set needs no synchronization.
 */
object TabHibernationMiddleware : Middleware<BrowserState, BrowserAction> {
    private val logger = Logger("TabHibernationMiddleware")

    /** Tabs this policy suspended and not yet woken. Main thread only. */
    private val hibernatedTabIds = mutableSetOf<String>()

    override fun invoke(
        store: Store<BrowserState, BrowserAction>,
        next: (BrowserAction) -> Unit,
        action: BrowserAction,
    ) {
        next(action)

        // Runs after the reducer, so the store already reflects the removals
        // when the marks are pruned below.
        when (action) {
            is TabListAction.SelectTabAction -> onTabSelected(store, action.tabId)

            is TabListAction.RemoveTabAction,
            is TabListAction.RemoveTabsAction,
            is TabListAction.RemoveAllTabsAction,
            is TabListAction.RemoveAllNormalTabsAction,
            is TabListAction.RemoveAllPrivateTabsAction -> prune(store),
            else -> Unit
        }
    }

    /**
     * Suspends the engine sessions of the [requested] tabs that may be
     * suspended, and returns the ids that actually were.
     *
     * Skipped, in the order checked: the selected tab (never — its session is
     * what the user is looking at), tabs without a live engine session (a
     * restored-from-disk tab; there is no process to free), tabs whose session
     * is initializing or crashed (the crash path belongs to
     * [CrashRecoveryMiddleware]), and tabs playing media (the
     * `LastMediaAccessMiddleware` tracks that; suspending them would stop the
     * audio). Only ids suspended here are marked for waking on selection.
     */
    fun suspendTabs(
        store: BrowserStore,
        requested: Collection<String>,
    ): List<String> {
        if (requested.isEmpty()) return emptyList()

        val state = store.state
        val suspended = mutableListOf<String>()

        for (tabId in requested) {
            if (tabId == state.selectedTabId) continue

            val tab = state.findTab(tabId) ?: continue
            if (tab.engineState.engineSession == null) continue
            if (tab.engineState.initializing || tab.engineState.crashed) continue
            if (tab.lastMediaAccessState.mediaSessionActive) continue

            store.dispatch(EngineAction.SuspendEngineSessionAction(tabId))
            hibernatedTabIds.add(tabId)
            suspended.add(tabId)
        }

        if (suspended.isNotEmpty()) {
            logger.info("Suspended ${suspended.size} background tab(s): $suspended")
        }

        return suspended
    }

    /**
     * Wakes a tab this policy suspended: the engine middleware rebuilds the
     * session and restores the kept `EngineSessionState`, so the tab comes
     * back with its back/forward history.
     *
     * Dispatched after [next], so the selection has already applied and the
     * engine view presenter will pick up the linked session on its next
     * render.
     */
    private fun onTabSelected(
        store: Store<BrowserState, BrowserAction>,
        tabId: String,
    ) {
        if (tabId !in hibernatedTabIds) return

        hibernatedTabIds.remove(tabId)
        logger.info("Waking hibernated tab $tabId")
        store.dispatch(EngineAction.CreateEngineSessionAction(tabId))
    }

    /** Drops the marks of tabs that are no longer open. */
    private fun prune(store: Store<BrowserState, BrowserAction>) {
        if (hibernatedTabIds.isEmpty()) return

        val open = store.state.tabs.mapTo(mutableSetOf()) { it.id }
        hibernatedTabIds.retainAll(open)
    }
}
