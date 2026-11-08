import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/cash_session.dart';

class CashSessionRepository {
  CashSessionRepository(this._db, this._outbox, this._hlc);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  Future<CashSession?> current(String storeId, String userId) async {
    final rows = await _db.query(
      'cash_sessions',
      where: 'store_id = ? AND user_id = ? AND closed_at IS NULL',
      whereArgs: [storeId, userId],
      orderBy: 'opened_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CashSession.fromMap(rows.first);
  }

  Future<List<CashSession>> recent(String storeId, {int limit = 30}) async {
    final rows = await _db.query(
      'cash_sessions',
      where: 'store_id = ?',
      whereArgs: [storeId],
      orderBy: 'opened_at DESC',
      limit: limit,
    );
    return rows.map(CashSession.fromMap).toList();
  }

  Future<CashSession> open({
    required String storeId,
    required String userId,
    required double openingBalance,
    String? notes,
  }) async {
    final existing = await current(storeId, userId);
    if (existing != null) return existing;

    final id = Ulid().toCanonical();
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    final m = {
      'id': id,
      'store_id': storeId,
      'user_id': userId,
      'opened_at': now.toIso8601String(),
      'closed_at': null,
      'opening_balance': openingBalance,
      'closing_balance': null,
      'expected_balance': null,
      'difference': null,
      'total_sales': 0.0,
      'total_cash': 0.0,
      'notes': notes,
      'version': version,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    await _db.transaction((txn) async {
      await txn.insert('cash_sessions', m);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'cash_sessions',
        rowId: id,
        op: 'create',
        payload: m,
        overrideVersion: version,
      );
    });
    return CashSession.fromMap(m);
  }

  Future<CashSession> close({
    required String id,
    required double closingBalance,
    String? notes,
  }) async {
    final sessionRow = await _db.query('cash_sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (sessionRow.isEmpty) throw StateError('Sesyon pa egziste.');
    final session = CashSession.fromMap(sessionRow.first);

    // Total cash + sales pou sesyon sa
    final cashTotalRow = await _db.rawQuery('''
      SELECT COALESCE(SUM(p.amount), 0) AS cash_total
        FROM payments p
        JOIN sales s ON s.id = p.sale_id
       WHERE s.cash_session_id = ? AND p.method = 'cash'
    ''', [id]);
    final totalCash = ((cashTotalRow.first['cash_total'] as num?) ?? 0).toDouble();

    final salesTotalRow = await _db.rawQuery('''
      SELECT COALESCE(SUM(total), 0) AS sales_total, COUNT(*) AS cnt
        FROM sales
       WHERE cash_session_id = ? AND status = 'completed'
    ''', [id]);
    final totalSales = ((salesTotalRow.first['sales_total'] as num?) ?? 0).toDouble();

    final expected = session.openingBalance + totalCash;
    final diff = closingBalance - expected;
    final now = DateTime.now().toUtc();
    final version = _hlc.next();

    final m = {
      'id': id,
      'store_id': session.storeId,
      'user_id': session.userId,
      'opened_at': session.openedAt.toIso8601String(),
      'closed_at': now.toIso8601String(),
      'opening_balance': session.openingBalance,
      'closing_balance': closingBalance,
      'expected_balance': expected,
      'difference': diff,
      'total_sales': totalSales,
      'total_cash': totalCash,
      'notes': notes ?? session.notes,
      'version': version,
      'created_at': session.createdAt.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    await _db.transaction((txn) async {
      await txn.update('cash_sessions', m, where: 'id = ?', whereArgs: [id]);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'cash_sessions',
        rowId: id,
        op: 'update',
        payload: m,
        overrideVersion: version,
      );
    });
    return CashSession.fromMap(m);
  }
}

final cashSessionRepositoryProvider = Provider<CashSessionRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return CashSessionRepository(db, outbox, hlc);
});
