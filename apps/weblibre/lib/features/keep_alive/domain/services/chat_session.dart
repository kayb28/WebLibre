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
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weblibre/features/geckoview/domain/providers/tab_state.dart';

/// Phase of a chat generation observed on one tab.
///
/// The separation between [stabilizing] and [completed] avoids the classic
/// mistake of declaring a response done the instant the network stream
/// closes: some sites close one stream and open the next while still
/// writing the answer, so completion is only announced after a short quiet
/// period.
enum ChatGenerationPhase { generating, stabilizing, completed }

/// A chat generation in progress (or just finished) on one tab.
class ChatSession {
  final Uri url;
  final ChatGenerationPhase phase;

  /// When the stream currently (or last) feeding this session opened.
  /// Informational only — a reconnecting stream refreshes it.
  final DateTime since;

  /// When this chain of streams began. Unlike [since] it is not refreshed
  /// by a stream that re-opens while the session is still alive, so a loop
  /// of auto-reconnecting streams cannot keep the keep-alive condition
  /// satisfied forever (see [isActiveGeneration]).
  final DateTime chainSince;

  const ChatSession({
    required this.url,
    required this.phase,
    required this.since,
    required this.chainSince,
  });

  ChatSession copyWith({ChatGenerationPhase? phase, DateTime? since}) =>
      ChatSession(
        url: url,
        phase: phase ?? this.phase,
        since: since ?? this.since,
        chainSince: chainSince,
      );
}

/// How long a generation chain may stay trusted as an active generation:
/// chat answers stream for seconds or minutes, but a stream that only
/// re-opens in a loop would otherwise pin the foreground service open for as
/// long as its tab lives. The keep-alive condition ignores anything older,
/// and a new chain only starts after a session was completed — never
/// mid-loop — so such streams cannot keep the service hostage.
const maxTrustedGeneration = Duration(minutes: 10);

/// Quiet period after the last stream closes before a generation counts as
/// [ChatGenerationPhase.completed].
const stabilizationDelay = Duration(seconds: 3);

/// How long a [ChatGenerationPhase.completed] session stays recorded before
/// it is dropped, so a tab can start a new generation cleanly.
const completedRetention = Duration(seconds: 30);

/// Per-tab chat generation sessions, fed by the detector's stream events
/// (see `chat_detector.dart`). Kept as a plain map keyed by tab id.
final chatSessionsProvider =
    NotifierProvider<ChatSessionManager, Map<String, ChatSession>>(
  ChatSessionManager.new,
);

class ChatSessionManager extends Notifier<Map<String, ChatSession>> {
  final Map<String, Timer> _stabilizeTimers = {};
  final Map<String, Timer> _sweepTimers = {};

  /// Open generation streams per tab. A site can hold more than one at a
  /// time (answer stream plus a live stream), and they do not always close
  /// in order, so the phase only leaves [ChatGenerationPhase.generating]
  /// when the last one closed.
  final Map<String, int> _openStreams = {};

  @override
  Map<String, ChatSession> build() {
    ref.onDispose(() {
      for (final timer in _stabilizeTimers.values) {
        timer.cancel();
      }
      for (final timer in _sweepTimers.values) {
        timer.cancel();
      }
      _stabilizeTimers.clear();
      _sweepTimers.clear();
    });

    // A tab that is gone cannot stream: drop its session immediately, undo
    // toast included (a lingering entry would only outlive by seconds).
    ref.listen(tabStatesProvider, (previous, next) {
      for (final tabId in state.keys.toList()) {
        if (!next.containsKey(tabId)) {
          remove(tabId);
        }
      }
    });

    return const {};
  }

  /// A generation stream just opened on this tab.
  void streamStarted(String tabId, Uri url) {
    _openStreams[tabId] = (_openStreams[tabId] ?? 0) + 1;
    _cancelTimers(tabId);

    // A stream that arrives while the session is still generating or
    // stabilizing is a continuation of the same generation chain — a
    // reconnect, not a new generation — so it inherits the chain's age
    // instead of resetting the trust window. Only a stream after a
    // completed (or absent) session starts a fresh chain.
    final existing = state[tabId];
    final chainSince =
        existing == null || existing.phase == ChatGenerationPhase.completed
        ? DateTime.now()
        : existing.chainSince;

    _set(
      tabId,
      ChatSession(
        url: url,
        phase: ChatGenerationPhase.generating,
        since: DateTime.now(),
        chainSince: chainSince,
      ),
    );
  }

  /// A generation stream on this tab just closed. Only when the last open
  /// stream closed does the session start stabilizing, and completion is
  /// announced after [stabilizationDelay] without a new stream.
  void streamEnded(String tabId) {
    final remaining = (_openStreams[tabId] ?? 0) - 1;
    if (remaining > 0) {
      // Another stream is still open on this tab: keep generating.
      _openStreams[tabId] = remaining;
      return;
    }
    _openStreams.remove(tabId);

    final session = state[tabId];
    if (session == null || session.phase != ChatGenerationPhase.generating) {
      return;
    }

    _stabilizeTimers[tabId]?.cancel();
    _stabilizeTimers[tabId] = Timer(stabilizationDelay, () {
      _stabilizeTimers.remove(tabId);
      final current = state[tabId];
      if (current == null || current.phase != ChatGenerationPhase.stabilizing) {
        return;
      }
      _set(tabId, current.copyWith(phase: ChatGenerationPhase.completed));
      _sweepTimers[tabId]?.cancel();
      _sweepTimers[tabId] = Timer(completedRetention, () {
        _sweepTimers.remove(tabId);
        remove(tabId);
      });
    });

    _set(
      tabId,
      session.copyWith(
        phase: ChatGenerationPhase.stabilizing,
        since: DateTime.now(),
      ),
    );
  }

  void remove(String tabId) {
    _cancelTimers(tabId);
    _openStreams.remove(tabId);
    if (!state.containsKey(tabId)) {
      return;
    }
    final next = Map<String, ChatSession>.of(state)..remove(tabId);
    state = next;
  }

  void _set(String tabId, ChatSession session) {
    state = {...state, tabId: session};
  }

  void _cancelTimers(String tabId) {
    _stabilizeTimers.remove(tabId)?.cancel();
    _sweepTimers.remove(tabId)?.cancel();
  }
}

/// Whether this session still counts as an active generation for the
/// keep-alive decision: generating or stabilizing, and trusted by chain age
/// (see [maxTrustedGeneration]) — the age of the whole chain, not just of
/// its latest stream, so a reconnecting stream cannot refresh the window.
bool isActiveGeneration(ChatSession session) {
  if (session.phase == ChatGenerationPhase.completed) {
    return false;
  }
  return DateTime.now().difference(session.chainSince) < maxTrustedGeneration;
}
