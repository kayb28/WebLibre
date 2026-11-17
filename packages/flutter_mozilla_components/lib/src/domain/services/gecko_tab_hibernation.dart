/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/services.dart';

/// Suspends the engine sessions of background tabs so their sandboxed
/// content processes can be reclaimed, without closing the tabs.
///
/// This is the Dart half of tab hibernation. A suspend request makes native
/// dispatch `EngineAction.SuspendEngineSessionAction` per tab: the session is
/// unlinked and closed — freeing its content process — while the serialized
/// engine session state is kept, so the back/forward history survives.
/// Selecting a hibernated tab brings it back automatically (the native
/// `TabHibernationMiddleware` recreates the session in the same container
/// context); no Dart call is needed for that.
///
/// Not a Pigeon API on purpose: one method channel keeps this feature out of
/// the generated API surface, so the codegen for [GeckoTabsApi] is untouched.
class GeckoTabHibernationService {
  static const MethodChannel _channel = MethodChannel(
    'eu.weblibre.flutter_mozilla_components/hibernation',
  );

  /// Asks native to suspend the engine sessions of [tabIds].
  ///
  /// Returns the ids actually suspended: the selected tab, tabs without a
  /// live engine session, initializing or crashed tabs and tabs playing
  /// media are skipped there. Callers should treat the returned ids (and
  /// only those) as hibernated.
  ///
  /// Before the engine is initialized this returns an empty list.
  Future<List<String>> suspendTabs({required Set<String> tabIds}) async {
    if (tabIds.isEmpty) {
      return const [];
    }

    final suspended = await _channel.invokeListMethod<String>(
      'suspendTabs',
      tabIds.toList(),
    );

    return suspended ?? const [];
  }
}
