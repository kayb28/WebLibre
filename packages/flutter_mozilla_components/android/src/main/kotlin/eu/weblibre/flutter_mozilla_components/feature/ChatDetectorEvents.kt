/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package eu.weblibre.flutter_mozilla_components.feature

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * Pushes chat generation stream events (started/ended per tab) to Dart.
 *
 * Unlike the Pigeon-generated event classes this one is hand written, so no
 * code generation step is needed: a plain [EventChannel] with the standard
 * codec carries small `HashMap`s, which is all the payload there is.
 *
 * The last known state per tab is kept, so a listener that arrives late —
 * Dart starts once, but a hot restart re-subscribes — still learns which
 * tabs are mid generation.
 */
class ChatDetectorEvents(messenger: BinaryMessenger) {
    companion object {
        internal const val CHANNEL = "eu.weblibre.gecko/chat_detector"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: EventChannel.Event? = null

    private val snapshot = ConcurrentHashMap<String, HashMap<String, Any>>()

    init {
        EventChannel(messenger, CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.Event?) {
                    sink = events
                    // Replay the snapshot: events are idempotent on the Dart
                    // side (a repeated "started" just refreshes the session).
                    snapshot.values.forEach { events?.success(it) }
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            }
        )
    }

    /**
     * Reports a generation stream that just started (type "started") or
     * finished (type "ended") on the tab with the given app tab id.
     */
    fun onStreamUpdate(tabId: String, url: String, type: String) {
        val event = hashMapOf(
            "tabId" to tabId,
            "url" to url,
            "type" to type,
            "timestamp" to System.currentTimeMillis(),
        )

        if (type == "started") {
            snapshot[tabId] = event
        } else {
            snapshot.remove(tabId)
        }

        mainHandler.post { sink?.success(event) }
    }
}
