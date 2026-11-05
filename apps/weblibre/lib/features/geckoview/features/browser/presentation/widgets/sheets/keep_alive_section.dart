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
import 'package:fast_equatable/fast_equatable.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:weblibre/core/logger.dart';
import 'package:weblibre/features/keep_alive/domain/repositories/keep_alive_settings.dart';
import 'package:weblibre/features/user/data/providers.dart';
import 'package:weblibre/l10n/generated/app_localizations.dart';
import 'package:weblibre/utils/host_rules.dart';
import 'package:weblibre/utils/ui_helper.dart';

/// Section widget toggling whether this site keeps the browser running in
/// the background, so an open chat keeps streaming its answers while the
/// user is in another app. Mirrors the per-site gesture exclusion toggle.
class KeepAliveSection extends HookConsumerWidget {
  final Uri url;

  const KeepAliveSection({required this.url, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hosts = ref
        .watch(
          keepAliveHostsProvider.select(
            (s) => EquatableValue(s.value ?? const <String>[]),
          ),
        )
        .value;

    final host = normalizeRuleHost(url.toString());
    final isEnabledHere = host != null && hostMatchesRule(url, hosts);
    // A broader entry (e.g. `example.com` while on `m.example.com`) governs
    // this page; a per-site toggle for the exact host can't override it.
    final parentRule = coveringParentRule(url, hosts);

    final String subtitle;
    if (host == null) {
      subtitle = l10n.browser_keepAliveUnavailableOnThisPage;
    } else if (parentRule != null) {
      subtitle = l10n.browser_keepAliveEnabledByRuleFor(parentRule);
    } else if (isEnabledHere) {
      subtitle = l10n.browser_keepAliveSubtitleOn;
    } else {
      subtitle = l10n.browser_keepAliveSubtitleOff;
    }

    return SwitchListTile.adaptive(
      value: isEnabledHere,
      // Only actionable when we have a valid host to add to / remove from
      // the list, and no broader rule governs the page (which this
      // exact-host toggle could not override).
      onChanged: (host != null && parentRule == null)
          ? (enabled) => _toggleKeepAlive(context, ref, host, enabled)
          : null,
      title: Text(l10n.browser_keepAliveTitle),
      subtitle: Text(subtitle),
      secondary: Icon(
        isEnabledHere ? Icons.flash_on : Icons.flash_off,
        color: isEnabledHere
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Future<void> _toggleKeepAlive(
    BuildContext context,
    WidgetRef ref,
    String host,
    bool enabled,
  ) async {
    try {
      await setKeepAliveForHost(
        ref.read(userDatabaseProvider),
        host,
        enabled,
      );
    } catch (e, s) {
      logger.e('Failed to toggle keep-alive', error: e, stackTrace: s);
      if (context.mounted) {
        showErrorMessage(
          context,
          AppLocalizations.of(
            context,
          ).browser_failedToToggleKeepAlive(e.toString()),
        );
      }
    }
  }
}
