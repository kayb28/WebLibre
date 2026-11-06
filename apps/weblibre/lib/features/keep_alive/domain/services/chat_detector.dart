/*
 * Copyright (c) 2026 kayb28 and contributors.
 *
 * This file is part of WebLibre
 * (see https://weblibre.eu).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weblibre/core/logger.dart';
import 'package:weblibre/features/keep_alive/domain/services/chat_session.dart';

/// One generation stream event reported by the chat_detector web extension:
/// the engine observed a chat-like response stream open (`started`) or
/// close (`ended`) on a tab.
class ChatStreamEvent {
  final String tabId;
  final Uri url;
  final bool started;
  final DateTime at;

  const ChatStreamEvent({
    required this.tabId,
    required this.url,
    required this.started,
    required this.at,
  });

  /// Parses the raw channel payload (a standard-codec map, see
  /// `ChatDetectorEvents.kt`); malformed events are dropped with a log line
  /// instead of poisoning the stream.
  static ChatStreamEvent? fromChannel(Object? raw) {
    try {
      final map = raw as Map;
      return ChatStreamEvent(
        tabId: map['tabId']! as String,
        url: Uri.parse(map['url']! as String),
        started: map['type'] == 'started',
        at: DateTime.fromMillisecondsSinceEpoch(
          (map['timestamp']! as num).toInt(),
        ),
      );
    } catch (e, s) {
      logger.w('Malformed chat detector event', error: e, stackTrace: s);
      return null;
    }
  }
}

/// Raw event stream of the chat detector. The Kotlin side replays the
/// current per-tab snapshot when this stream is listened to, so a late
/// listener still learns about generations already in progress.
final chatDetectorEventsProvider = StreamProvider<ChatStreamEvent>((ref) {
  const channelName = 'eu.weblibre.gecko/chat_detector';

  return EventChannel(channelName)
      .receiveBroadcastStream()
      .map(ChatStreamEvent.fromChannel)
      .where((event) => event != null)
      .cast<ChatStreamEvent>();
});

/// Feeds the detector's events into the per-tab session manager. Activated
/// once from the app root (see `_activateService` in main.dart), the same
/// way the keep-alive service activator is.
final chatDetectorActivatorProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<ChatStreamEvent>>(
    chatDetectorEventsProvider,
    (previous, next) {
      final event = next.value;
      if (event == null) {
        return;
      }

      final manager = ref.read(chatSessionsProvider.notifier);
      if (event.started) {
        manager.streamStarted(event.tabId, event.url);
      } else {
        manager.streamEnded(event.tabId);
      }
    },
  );
});
