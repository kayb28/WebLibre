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
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weblibre/features/user/data/database/database.dart';
import 'package:weblibre/features/user/data/providers.dart';

const _partitionKey = 'tabHibernation';
const _thresholdKey = 'hibernationThresholdMinutes';

/// How long a background tab stays idle before the hibernation sweep
/// suspends its engine session (see `tab_hibernation.dart`). The default
/// matches the 30-minute spirit of desktop "memory savers": long enough
/// that background loads, redirects and slow reading are over for nearly
/// every page, short enough that a stack of tabs holds RAM for minutes,
 * not days.
const defaultHibernationThresholdMinutes = 30;

/// The thresholds the settings segmented button offers. A short one frees
/// a tab's content process sooner - more tabs fit in the pool at once; a
/// long one keeps background pages instant to return to.
const hibernationThresholdChoices = [10, 30, 60];

/// The persisted idle threshold, in minutes.
///
/// Stored in the user settings database the same way the keep-alive host
/// list is (see `keep_alive_settings.dart`), so nothing here needs code
/// generation. Emits `defaultHibernationThresholdMinutes` until the first
/// row arrives and for any stored value outside the offered choices.
final tabHibernationThresholdProvider = StreamProvider<int>((ref) {
  final db = ref.watch(userDatabaseProvider);

  return db.settingDao
      .getAllSettingsOfPartitionKey(_partitionKey)
      .watch()
      .map((entries) => _readThreshold(entries, db));
});

int _readThreshold(
  List<MapEntry<String, DriftAny?>> entries,
  UserDatabase db,
) {
  final settings = Map.fromEntries(entries);
  final raw = settings[_thresholdKey]?.readAs<int>(
    DriftSqlType.int,
    db.typeMapping,
  );

  if (raw != null && hibernationThresholdChoices.contains(raw)) {
    return raw;
  }

  return defaultHibernationThresholdMinutes;
}

/// Persists the idle threshold. Takes the database so both the widget layer
/// and providers can call it with their own `ref`.
Future<void> setHibernationThreshold(UserDatabase db, int minutes) async {
  if (!hibernationThresholdChoices.contains(minutes)) {
    throw ArgumentError.value(minutes, 'minutes', 'Not an offered threshold');
  }

  await db.settingDao.updateSetting(_thresholdKey, _partitionKey, minutes);
}
