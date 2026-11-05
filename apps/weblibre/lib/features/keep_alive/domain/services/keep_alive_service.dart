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
import 'package:weblibre/features/geckoview/domain/providers/tab_state.dart';
import 'package:weblibre/features/keep_alive/domain/repositories/keep_alive_settings.dart';
import 'package:weblibre/utils/host_rules.dart';

/// Client of the Android foreground service that keeps the app's process —
/// and with it every open tab's network session — alive while the user is in
/// another app. See KeepAliveService.kt in the Android module and the
/// `eu.weblibre.gecko/keep_alive` channel in MainActivity.kt.
class KeepAlivePlatformService {
  KeepAlivePlatformService._();

  static const _channel = MethodChannel('eu.weblibre.gecko/keep_alive');

  static final instance = KeepAlivePlatformService._();

  Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } catch (e, s) {
      logger.e('Failed to start keep-alive service', error: e, stackTrace: s);
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e, s) {
      logger.e('Failed to stop keep-alive service', error: e, stackTrace: s);
    }
  }

  Future<bool> isActive() async {
    try {
      return await _channel.invokeMethod<bool>('isActive') ?? false;
    } catch (e, s) {
      logger.e(
        'Failed to query keep-alive service',
        error: e,
        stackTrace: s,
      );
      return false;
    }
  }
}

/// Whether the foreground service should be running: true when at least one
/// open tab is on a host the user marked keep-alive.
///
/// A closed tab's state lingers a few seconds for the undo toast (see
/// `TabStates`), so the service can outlast its last tab by that much —
/// harmless, and it keeps a quick close-and-reopen from flapping.
final keepAliveShouldRunProvider = Provider<bool>((ref) {
  final hosts =
      ref.watch(keepAliveHostsProvider).value ?? const <String>[];
  if (hosts.isEmpty) return false;

  final tabStates = ref.watch(tabStatesProvider);
  return tabStates.values.any((tab) => hostMatchesRule(tab.url, hosts));
});

/// Keeps the platform service in step with [keepAliveShouldRunProvider].
/// Activated once from the app root (see `_activateService` in main.dart).
final keepAliveServiceActivatorProvider = Provider<void>((ref) {
  ref.listen<bool>(
    keepAliveShouldRunProvider,
    fireImmediately: true,
    (previous, next) {
      if (previous == next) return;

      if (next) {
        KeepAlivePlatformService.instance.start();
      } else if (previous != null) {
        // Never stopped on the first fire: a fresh provider build with no
        // history must not race a service the process never started.
        KeepAlivePlatformService.instance.stop();
      }
    },
  );
});
