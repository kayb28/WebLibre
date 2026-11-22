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
import 'package:flutter/material.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:weblibre/core/providers/persisted_bool.dart';
import 'package:weblibre/features/keep_alive/domain/repositories/hibernation_settings.dart';
import 'package:weblibre/features/user/data/providers.dart';

/// Strings for the tab-hibernation setting, resolved from the ambient locale.
///
/// Kept beside the tile instead of the ARB pipeline on purpose: the merged
/// template (`lib/l10n/app_en.arb`) and the generated localizations are
/// build outputs this branch cannot regenerate remotely, so this stays
/// self-contained until the six keys can be folded into `settings_en.arb`
/// (and its five translations) with a local `melos run build-l10n` run.
TabHibernationStrings tabHibernationL10n(BuildContext context) {
  final language = Localizations.maybeLocaleOf(context)?.languageCode;

  return switch (language) {
    'de' => const TabHibernationStrings(
      title: 'Inaktive Hintergrund-Tabs anhalten',
      subtitle:
          'Schließt die Engine-Sitzung eines Hintergrund-Tabs nach der '
          'gewählten Leerlaufzeit und gibt ihren Speicher frei; beim '
          'Anwählen wacht der Tab mit intakter Chronik auf',
      thresholdTitle: 'Anhalten nach',
      thresholdSubtitle:
          'Leerlaufzeit im Hintergrund, bevor ein Tab angehalten wird',
      keywords: 'Ruhezustand,anhalten,Schlaf,Speicher,Hintergrund,Leerlauf',
      minuteUnit: 'Min.',
    ),
    'es' => const TabHibernationStrings(
      title: 'Suspender pestañas de segundo plano inactivas',
      subtitle:
          'Cierra la sesión del motor de una pestaña en segundo plano tras '
          'el tiempo de inactividad elegido, liberando su memoria; al '
          'seleccionarla despierta con su historial intacto',
      thresholdTitle: 'Suspender tras',
      thresholdSubtitle:
          'Tiempo de inactividad antes de suspender una pestaña',
      keywords: 'hibernar,suspender,dormir,memoria,segundo plano,inactiva',
      minuteUnit: 'min',
    ),
    'id' => const TabHibernationStrings(
      title: 'Tunda tab latar belakang yang menganggur',
      subtitle:
          'Menutup sesi mesin tab latar belakang setelah lama menganggur '
          'yang dipilih, membebaskan memorinya; memilih tab akan '
          'membangunkannya dengan riwayat utuh',
      thresholdTitle: 'Tunda setelah',
      thresholdSubtitle: 'Lama menganggur sebelum tab latar belakang ditunda',
      keywords: 'hibernasi,tunda,tidur,memori,latar belakang,menganggur',
      minuteUnit: 'mnt',
    ),
    'ru' => const TabHibernationStrings(
      title: 'Приостанавливать неактивные фоновые вкладки',
      subtitle:
          'Закрывает сессию движка фоновой вкладки после заданного времени '
          'простоя, освобождая память; при выборе вкладка просыпается с '
          'сохранённой историей',
      thresholdTitle: 'Приостанавливать через',
      thresholdSubtitle: 'Время простоя в фоне до приостановки вкладки',
      keywords: 'гибернация,приостановка,сон,память,фон,простой',
      minuteUnit: 'мин',
    ),
    'zh' => const TabHibernationStrings(
      title: '暂停闲置的后台标签页',
      subtitle: '后台标签页闲置超过设定时间后关闭其引擎会话并释放内存；选中时会保留历史记录并唤醒',
      thresholdTitle: '暂停时限',
      thresholdSubtitle: '标签页在后台闲置多久后暂停',
      keywords: '休眠,暂停,睡眠,内存,后台,闲置',
      minuteUnit: '分钟',
    ),
    _ => const TabHibernationStrings(
      title: 'Suspend idle background tabs',
      subtitle:
          "Closes a background tab's engine session once it sits idle long "
          'enough, freeing its memory; picking the tab wakes it with its '
          'history intact',
      thresholdTitle: 'Suspend after',
      thresholdSubtitle: 'Idle time before a background tab is suspended',
      keywords: 'hibernate,suspend,sleep,memory,background,idle',
      minuteUnit: 'min',
    ),
  };
}

/// The tab-hibernation strings for one locale; see [tabHibernationL10n].
class TabHibernationStrings {
  final String title;
  final String subtitle;
  final String thresholdTitle;
  final String thresholdSubtitle;
  final String keywords;
  final String minuteUnit;

  const TabHibernationStrings({
    required this.title,
    required this.subtitle,
    required this.thresholdTitle,
    required this.thresholdSubtitle,
    required this.keywords,
    required this.minuteUnit,
  });

  /// The label of one threshold segment, e.g. `30 min`.
  String minuteLabel(int minutes) => '$minutes $minuteUnit';
}

/// The tab-hibernation half of the settings entry: the switch that enables
/// the policy - the persisted `TabHibernation` bool, which until now
/// nothing in the UI ever wrote - and, below it, the idle-threshold
/// segmented button this branch adds (10/30/60 minutes).
///
/// The switch and the threshold write through to different stores: the
/// bool lives in the riverpod persistence of `persisted_bool.dart`, the
/// threshold in the user settings database (see `hibernation_settings.dart`)
/// so it survives like any other setting.
class TabHibernationSettingsTile extends ConsumerWidget {
  const TabHibernationSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = tabHibernationL10n(context);
    final enabled = ref.watch(
      persistedBoolProvider(PersistedBoolKey.tabHibernation),
    );
    final threshold =
        ref.watch(tabHibernationThresholdProvider).value ??
        defaultHibernationThresholdMinutes;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            title: Text(strings.title),
            subtitle: Text(strings.subtitle),
            secondary: const Icon(MdiIcons.weatherNight),
            contentPadding: EdgeInsets.zero,
            value: enabled,
            onChanged: (value) => ref
                .read(
                  persistedBoolProvider(PersistedBoolKey.tabHibernation)
                      .notifier,
                )
                .set(value),
          ),
          if (enabled) ...[
            ListTile(
              title: Text(strings.thresholdTitle),
              subtitle: Text(strings.thresholdSubtitle),
              contentPadding: EdgeInsets.zero,
            ),
            Center(
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final minutes in hibernationThresholdChoices)
                    ButtonSegment(
                      value: minutes,
                      label: Text(strings.minuteLabel(minutes)),
                    ),
                ],
                selected: {threshold},
                onSelectionChanged: (selection) async {
                  final db = ref.read(userDatabaseProvider);
                  await setHibernationThreshold(db, selection.first);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
