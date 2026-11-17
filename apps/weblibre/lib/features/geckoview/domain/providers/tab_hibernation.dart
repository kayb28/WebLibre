/*
 * Copyright (c) 2024-2026 Fabian Freund.
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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
import 'dart:async';

import 'package:flutter_mozilla_components/flutter_mozilla_components.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:weblibre/core/logger.dart';
import 'package:weblibre/core/providers/persisted_bool.dart';
import 'package:weblibre/features/geckoview/domain/providers.dart';
import 'package:weblibre/features/geckoview/domain/providers/selected_tab.dart';
import 'package:weblibre/features/geckoview/domain/providers/tab_list.dart';

/// How long a background tab must go without the user looking at it before
/// its engine session is suspended: at that point native closes the session
/// (with it the tab's sandboxed content process) and keeps the serialized
/// state. In the spirit of the 30-minute defaults of desktop "memory
/// savers": long enough that background loads, redirects and slow reading
/// are over for nearly every page, short enough that a stack of tabs holds
/// RAM for minutes, not days.
const _hibernationAfter = Duration(minutes: 30);

/// How often idle background tabs are considered for suspension. The sweep
/// is cheap (a map walk and one native call when candidates exist), so a
/// short interval only makes hibernation kick in closer to the deadline.
const _sweepInterval = Duration(minutes: 1);

/// Tab ids whose engine sessions the hibernation policy has suspended.
///
/// The policy is native; this provider only drives it and mirrors its
/// result. [TabHibernation._sweep] sends the idle background tab ids over
/// [GeckoTabHibernationService.suspendTabs]; the store suspends the ones
/// that may be suspended (never the selected tab, tabs without a live
/// engine session, crashed or initializing tabs, or tabs playing media)
/// and returns the ids it actually suspended - exactly what lands in the
/// state here. Selecting one of them wakes it natively, in the same
/// container and with its back/forward history; the badge is dropped from
/// the state the moment the selection changes.
///
/// Written in manual Riverpod syntax on purpose: everything around here is
/// generated, and adding an annotated provider would need codegen for a
/// provider whose only public surface is a Set.
///
/// The provider is created once, early - `TabStates.build` reads it, so the
/// sweep timer runs from startup; nothing renders the state until the tab
/// views do.
final tabHibernationProvider =
    NotifierProvider<TabHibernation, Set<String>>(TabHibernation.new);

class TabHibernation extends Notifier<Set<String>> {
  final GeckoTabHibernationService _service = GeckoTabHibernationService();

  /// The idle clock of each background tab: when it last moved to the
  /// background, or last reported content activity from there (a load, a
  /// redirect, a scripted navigation). Tabs with no entry yet start their
  /// clock at the first sweep that sees them, so a tab the engine
  /// restored from disk is never suspended the moment it loads.
  final _lastActive = <String, DateTime>{};

  StreamSubscription<TabContentState>? _contentSub;
  Timer? _sweepTimer;
  bool _sweeping = false;

  @override
  Set<String> build() {
    // Toggling the setting rebuilds the notifier: the timer re-arms and the
    // badges clear (native still knows which sessions it suspended, and
    // still wakes them on selection), while the clocks survive.
    ref.watch(persistedBoolProvider(PersistedBoolKey.tabHibernation));

    // A build re-execution stops the previous timer and subscription first.
    _sweepTimer?.cancel();
    unawaited(_contentSub?.cancel());

    final eventService = ref.watch(eventServiceProvider);
    _contentSub = eventService.tabContentEvents.listen(
      (event) => _lastActive[event.id] = DateTime.now(),
      onError: (Object error, StackTrace stackTrace) {
        logger.e(
          'Error in tab content events',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );

    // A selection change does two things: the tab left in the background
    // starts its idle clock now, and the tab brought forward (woken
    // natively, engine session recreated) loses its badge. No
    // fireImmediately: the state cannot be touched during the first build,
    // and a tab that is already selected needs no clock entry - it stops
    // being a suspension candidate the moment it is selected again.
    ref.listen(selectedTabProvider, (previous, next) {
      if (previous == next) return;

      if (previous != null) {
        _lastActive[previous] = DateTime.now();
      }

      if (next != null && state.contains(next)) {
        state = state.difference({next});
      }
    });

    // Closed tabs take their clocks and badges with them.
    ref.listen(tabListProvider, (_, next) {
      final open = next.value.toSet();
      _lastActive.removeWhere((id, _) => !open.contains(id));

      if (state.isNotEmpty) {
        final pruned = state.intersection(open);
        if (pruned.length != state.length) {
          state = pruned;
        }
      }
    });

    _sweepTimer = Timer.periodic(_sweepInterval, (_) {
      unawaited(_sweep());
    });

    ref.onDispose(() {
      _sweepTimer?.cancel();
      _sweepTimer = null;
      unawaited(_contentSub?.cancel());
      _contentSub = null;
    });

    return const {};
  }

  /// Suspends the engine sessions of the background tabs idle past
  /// [_hibernationAfter] and adds the ones native actually suspended to the
  /// state.
  Future<void> _sweep() async {
    // The method channel call is awaited; overlapping sweeps would only
    // re-send ids the guards would drop anyway.
    if (_sweeping) return;
    _sweeping = true;

    try {
      if (!ref.read(persistedBoolProvider(PersistedBoolKey.tabHibernation))) {
        return;
      }

      final tabIds = ref.read(tabListProvider).value;
      final selected = ref.read(selectedTabProvider);

      final now = DateTime.now();
      final candidates = <String>{};

      for (final tabId in tabIds) {
        if (tabId == selected) continue;
        if (state.contains(tabId)) continue;

        final lastActive = _lastActive[tabId];
        if (lastActive == null) {
          _lastActive[tabId] = now;
        } else if (now.difference(lastActive) >= _hibernationAfter) {
          candidates.add(tabId);
        }
      }

      if (candidates.isEmpty) return;

      final suspended = await _service.suspendTabs(tabIds: candidates);
      if (!ref.mounted) return;

      if (suspended.isNotEmpty) {
        state = state.union(suspended.toSet());
      }
    } catch (error, stackTrace) {
      logger.e(
        'Tab hibernation sweep failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _sweeping = false;
    }
  }
}
