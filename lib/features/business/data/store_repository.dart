import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/store.dart';

class StoreRepository {
  StoreRepository(this._db, this._outbox, this._hlc);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  Future<Store?> findById(String id) async {
    final rows = await _db.query('stores', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Store.fromMap(rows.first);
  }

  Future<Store> update(Store s) async {
    final updated = s.copyWith(
      version: _hlc.next(),
      updatedAt: DateTime.now().toUtc(),
    );
    await _db.transaction((txn) async {
      await txn.update('stores', updated.toMap(), where: 'id = ?', whereArgs: [updated.id]);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'stores',
        rowId: updated.id,
        op: 'update',
        payload: updated.toMap(),
        overrideVersion: updated.version,
      );
    });
    return updated;
  }
}

final storeRepositoryProvider = Provider<StoreRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return StoreRepository(db, outbox, hlc);
});
