/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components.api

import eu.weblibre.flutter_mozilla_components.GlobalComponents
import eu.weblibre.flutter_mozilla_components.middleware.TabHibernationMiddleware
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart's side of tab hibernation: a plain method channel (not Pigeon, to keep
 * this out of the generated API surface) with a single method.
 *
 * - `suspendTabs(tabIds: List<String>)` asks the store to suspend the engine
 *   sessions of the given background tabs, and returns the ids actually
 *   suspended. See [TabHibernationMiddleware] for the policy's guards, and for
 *   how the tabs come back on selection.
 *
 * Before the engine is initialized this answers with an empty list: there is
 * nothing to suspend yet, and Dart treats that as "nothing to mark".
 *
 * Handlers run on the platform main thread, like the store dispatches they
 * cause, so no synchronization is needed with the middleware's mark set.
 */
class TabHibernationApiImpl {
    private var channel: MethodChannel? = null

    fun register(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL_NAME)
        channel.setMethodCallHandler(::onMethodCall)
        this.channel = channel
    }

    fun unregister() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            METHOD_SUSPEND_TABS -> {
                val components = GlobalComponents.components
                if (components == null) {
                    result.success(emptyList<String>())
                    return
                }

                val requested = (call.arguments as? List<*>)
                    ?.filterIsInstance<String>()
                    .orEmpty()

                val suspended =
                    TabHibernationMiddleware.suspendTabs(components.core.store, requested)
                result.success(suspended)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL_NAME = "eu.weblibre.flutter_mozilla_components/hibernation"
        private const val METHOD_SUSPEND_TABS = "suspendTabs"
    }
}
