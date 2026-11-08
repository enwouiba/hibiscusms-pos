import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/supplier.dart';

class SupplierRepository {
  SupplierRepository(this._db, this._outbox, this._hlc);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  Future<List<Supplier>> list(String storeId, {String? search}) async {
    final clauses = <String>['(store_id = ? OR store_id IS NULL)', 'deleted_at IS NULL'];
    final args = <Object?>[storeId];
    if (search != null && search.trim().isNotEmpty) {
      clauses.add('name LIKE ?');
      args.add('%${search.trim()}%');
    }
    final rows = await _db.query(
      'suppliers',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'name',
    );
    return rows.map(Supplier.fromMap).toList();
  }

  Future<Supplier?> findById(String id) async {
    final rows = await _db.query('suppliers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Supplier.fromMap(rows.first);
  }

  Future<Supplier> create({
    required String storeId,
    required String name,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async {
    final id = Ulid().toCanonical();
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    final s = Supplier(
      id: id,
      storeId: storeId,
      name: name,
      contactName: contactName,
      phone: phone,
      email: email,
      address: address,
      notes: notes,
      version: version,
      createdAt: now,
      updatedAt: now,
    );
    await _db.transaction((txn) async {
      await txn.insert('suppliers', s.toMap());
      await _outbox.enqueue(
        txn: txn,
        tableName: 'suppliers',
        rowId: id,
        op: 'create',
        payload: s.toMap(),
        overrideVersion: version,
      );
    });
    return s;
  }

  Future<Supplier> update(Supplier s) async {
    final updated = s.copyWith(version: _hlc.next(), updatedAt: DateTime.now().toUtc());
    await _db.transaction((txn) async {
      await txn.update('suppliers', updated.toMap(), where: 'id = ?', whereArgs: [updated.id]);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'suppliers',
        rowId: updated.id,
        op: 'update',
        payload: updated.toMap(),
        overrideVersion: updated.version,
      );
    });
    return updated;
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      await txn.update(
        'suppliers',
        {'deleted_at': now.toIso8601String(), 'updated_at': now.toIso8601String(), 'version': version},
        where: 'id = ?', whereArgs: [id],
      );
      await _outbox.enqueue(
        txn: txn,
        tableName: 'suppliers',
        rowId: id,
        op: 'delete',
        payload: {'id': id},
        overrideVersion: version,
      );
    });
  }
}

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return SupplierRepository(db, outbox, hlc);
});
