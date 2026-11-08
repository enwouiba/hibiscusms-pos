import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/category.dart';
import '../../../shared/models/unit.dart';

class CategoryRepository {
  CategoryRepository(this._db, this._outbox, this._hlc);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  Future<List<Category>> list(String storeId) async {
    final rows = await _db.rawQuery(
      'SELECT * FROM categories WHERE (store_id = ? OR store_id IS NULL) AND deleted_at IS NULL ORDER BY sort_order, name',
      [storeId],
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<Category> create({
    required String? storeId,
    required String name,
    int color = 0xFF607D8B,
    int sortOrder = 0,
  }) async {
    final id = Ulid().toCanonical();
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    final cat = Category(
      id: id,
      storeId: storeId,
      name: name,
      color: color,
      sortOrder: sortOrder,
      version: version,
      createdAt: now,
      updatedAt: now,
    );
    await _db.transaction((txn) async {
      await txn.insert('categories', cat.toMap());
      await _outbox.enqueue(
        txn: txn,
        tableName: 'categories',
        rowId: id,
        op: 'create',
        payload: cat.toMap(),
        overrideVersion: version,
      );
    });
    return cat;
  }

  Future<Category> update(Category c) async {
    final updated = c.copyWith(version: _hlc.next(), updatedAt: DateTime.now().toUtc());
    await _db.transaction((txn) async {
      await txn.update('categories', updated.toMap(), where: 'id = ?', whereArgs: [updated.id]);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'categories',
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
        'categories',
        {'deleted_at': now.toIso8601String(), 'updated_at': now.toIso8601String(), 'version': version},
        where: 'id = ?', whereArgs: [id],
      );
      await _outbox.enqueue(
        txn: txn,
        tableName: 'categories',
        rowId: id,
        op: 'delete',
        payload: {'id': id},
        overrideVersion: version,
      );
    });
  }

  // ---------- UNITS ----------
  Future<List<Unit>> listUnits() async {
    final rows = await _db.query('units', orderBy: 'name');
    return rows.map(Unit.fromMap).toList();
  }

  Future<Unit> createUnit({
    required String code,
    required String name,
    int decimals = 0,
  }) async {
    final id = Ulid().toCanonical();
    final now = DateTime.now().toUtc();
    final m = {
      'id': id,
      'code': code,
      'name': name,
      'decimals': decimals,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    await _db.transaction((txn) async {
      await txn.insert('units', m);
      // Note: units pa gen "version" — pa sync ak HLC, men outbox push otomatik
      await _outbox.enqueue(
        txn: txn,
        tableName: 'units',
        rowId: id,
        op: 'create',
        payload: m,
      );
    });
    return Unit.fromMap(m);
  }
}

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return CategoryRepository(db, outbox, hlc);
});
