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
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weblibre/features/user/data/database/database.dart';
import 'package:weblibre/features/user/data/providers.dart';

const _partitionKey = 'keepAlive';
const _hostsKey = 'hosts';

/// Hosts the user marked "keep active in background". A page is covered when
/// its host equals or is a subdomain of an entry (see `hostMatchesRule`).
///
/// Stored as one JSON list in the user settings database, the same way the
/// gesture exclusion list is, so nothing here needs code generation.
final keepAliveHostsProvider = StreamProvider<List<String>>((ref) {
  final db = ref.watch(userDatabaseProvider);

  return db.settingDao
      .getAllSettingsOfPartitionKey(_partitionKey)
      .watch()
      .map((entries) => _readHosts(entries, db));
});

List<String> _readHosts(
  List<MapEntry<String, DriftAny?>> entries,
  UserDatabase db,
) {
  final settings = Map.fromEntries(entries);
  final raw = settings[_hostsKey]?.readAs(
    DriftSqlType.string,
    db.typeMapping,
  );

  final decoded = raw != null ? jsonDecode(raw) : null;
  return decoded is List
      ? decoded.whereType<String>().toList()
      : const <String>[];
}

/// Adds or removes [host] (a bare lowercase host, as `normalizeRuleHost`
/// produces) from the keep-alive host list. Takes the database so both the
/// widget layer and providers can call it with their own `ref`.
Future<void> setKeepAliveForHost(
  UserDatabase db,
  String host,
  bool enabled,
) async {
  final entries = await db.settingDao
      .getAllSettingsOfPartitionKey(_partitionKey)
      .get();
  final hosts = _readHosts(entries, db).toSet();

  if (enabled) {
    hosts.add(host);
  } else {
    hosts.remove(host);
  }

  await db.settingDao.updateSetting(_hostsKey, _partitionKey, hosts.toList());
}
