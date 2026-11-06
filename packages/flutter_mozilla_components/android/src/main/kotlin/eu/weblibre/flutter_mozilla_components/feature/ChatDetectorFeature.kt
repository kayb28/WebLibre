/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components.feature

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.map
import mozilla.components.browser.state.store.BrowserStore
import mozilla.components.concept.engine.Engine
import mozilla.components.concept.engine.webextension.MessageHandler
import mozilla.components.concept.engine.webextension.Port
import mozilla.components.lib.state.ext.flowScoped
import mozilla.components.support.base.log.logger.Logger
import mozilla.components.support.ktx.kotlinx.coroutines.flow.filterChanged
import mozilla.components.support.webextensions.BuiltInWebExtensionController
import org.json.JSONObject

/**
 * Installs the chat_detector built-in web extension and relays its per-tab
 * generation events to Dart through [ChatDetectorEvents].
 *
 * The extension's background script watches response streams (server-sent
 * events and recognized completion endpoints) and attributes each one to a
 * tab through that tab's content script, which owns a native port registered
 * here per engine session — the same attribution trick ReadabilityExtract
 * uses. This feature has no view and runs for the lifetime of the component
 * set (see [WebExtensionActionsHost]); a fragment bound lifecycle would stop
 * detection exactly while the browser is in the background, which is when
 * detection matters.
 */
class ChatDetectorFeature(
    private var engine: Engine,
    private var store: BrowserStore,
    private var events: ChatDetectorEvents?,
) {
    companion object {
        private val logger = Logger("ChatDetector")

        internal const val CHAT_DETECTOR_EXTENSION_ID = "chat-detector@weblibre.eu"
        internal const val CHAT_DETECTOR_CONTENT_PORT = "weblibreChatDetector"
        internal const val CHAT_DETECTOR_EXTENSION_URL =
            "resource://android/assets/extensions/chat_detector/"
    }

    private class ContentMessageHandler(
        private var events: ChatDetectorEvents,
        private var tabId: String,
    ) : MessageHandler {
        override fun onPortConnected(port: Port) {
            logger.debug("Port connected: ${port.name()}")
        }

        override fun onPortMessage(message: Any, port: Port) {
            if (message is JSONObject) {
                val url = message.optString("url")
                val type = message.optString("type")
                if (url.isNotEmpty() && type.isNotEmpty()) {
                    events.onStreamUpdate(tabId, url, type)
                }
            }
        }
    }

    private var sessionScope: CoroutineScope? = null

    private var extensionController = BuiltInWebExtensionController(
        CHAT_DETECTOR_EXTENSION_ID,
        CHAT_DETECTOR_EXTENSION_URL,
        CHAT_DETECTOR_CONTENT_PORT,
    )

    fun start() {
        val events = events ?: return

        extensionController.install(
            engine,
            onSuccess = { extension ->
                sessionScope = store.flowScoped(dispatcher = Dispatchers.Main) { flow ->
                    flow.map { it.tabs }
                        .filterChanged { it.engineState.engineSession }
                        .collect { state ->
                            val engineSession = state.engineState.engineSession ?: return@collect

                            if (extension.hasContentMessageHandler(
                                    engineSession,
                                    CHAT_DETECTOR_CONTENT_PORT,
                                )
                            ) {
                                return@collect
                            }

                            val handler = ContentMessageHandler(events, state.id)
                            extension.registerContentMessageHandler(
                                engineSession,
                                CHAT_DETECTOR_CONTENT_PORT,
                                handler,
                            )
                        }
                }
            },
            onError = { throwable ->
                logger.error("Failed to install chat detector extension: ", throwable)
            },
        )
    }

    fun stop() {
        sessionScope?.cancel()
    }
}
