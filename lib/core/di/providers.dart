import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../auth/token_store.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../sync/hlc.dart';
import '../sync/outbox_service.dart';
import '../sync/sync_service.dart';

/// Pwòp baz done lokal SQLite.
final databaseProvider = FutureProvider<Database>((ref) async {
  return await AppDatabase.instance.database;
});

final databaseInstanceProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// HLC pou jenere `version` pa aparèy.
final hlcProvider = FutureProvider<Hlc>((ref) async {
  final deviceId = await ref.watch(tokenStoreProvider).deviceId();
  return Hlc(deviceId: deviceId ?? 'unset');
});

/// Override sa nan main.dart apre `await ref.read(hlcProvider.future)`.
final outboxServiceOverrideProvider = Provider<OutboxService>((ref) {
  final db = ref.watch(databaseInstanceProvider);
  final hlcAsync = ref.watch(hlcProvider);
  return OutboxService(db, hlcAsync.maybeWhen(
    data: (h) => h,
    orElse: () => Hlc(deviceId: 'unset'),
  ));
});

final syncServiceOverrideProvider = Provider<SyncService>((ref) {
  return SyncService(
    api: ref.watch(apiClientProvider),
    outbox: ref.watch(outboxServiceOverrideProvider),
    database: ref.watch(databaseInstanceProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});
