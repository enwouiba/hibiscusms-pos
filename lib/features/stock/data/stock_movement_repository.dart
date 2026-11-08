import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/stock_movement.dart';

class StockMovementRepository {
  StockMovementRepository(this._db, this._outbox, this._hlc);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  Future<List<StockMovement>> list(String storeId, {String? productId, int limit = 200}) async {
    final clauses = <String>['sm.store_id = ?'];
    final args = <Object?>[storeId];
    if (productId != null) {
      clauses.add('sm.product_id = ?');
      args.add(productId);
    }
    args.add(limit);
    final rows = await _db.rawQuery('''
      SELECT sm.*, p.name AS product_name, u.name AS user_name
        FROM stock_movements sm
        LEFT JOIN products p ON p.id = sm.product_id
        LEFT JOIN users u ON u.id = sm.user_id
       WHERE ${clauses.join(' AND ')}
       ORDER BY sm.created_at DESC
       LIMIT ?
    ''', args);
    return rows.map((r) => StockMovement.fromMap(
          r,
          productName: r['product_name'] as String?,
          userName: r['user_name'] as String?,
        )).toList();
  }

  /// Ajiste stock manyèlman (admin sèlman).
  Future<void> manualAdjust({
    required String storeId,
    required String productId,
    required String userId,
    required double newStock,
    String? notes,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.transaction((txn) async {
      final stockRow = await txn.query(
        'product_stocks',
        where: 'product_id = ? AND store_id = ?',
        whereArgs: [productId, storeId],
        limit: 1,
      );
      final currentStock = stockRow.isEmpty
          ? 0.0
          : ((stockRow.first['stock'] as num?)?.toDouble() ?? 0);
      final delta = newStock - currentStock;
      String stockId;

      if (stockRow.isEmpty) {
        stockId = Ulid().toCanonical();
        final psVersion = _hlc.next();
        final psMap = {
          'id': stockId,
          'product_id': productId,
          'store_id': storeId,
          'stock': newStock,
          'low_stock_alert': 5,
          'version': psVersion,
          'updated_at': now.toIso8601String(),
        };
        await txn.insert('product_stocks', psMap);
        await _outbox.enqueue(
          txn: txn,
          tableName: 'product_stocks',
          rowId: stockId,
          op: 'create',
          payload: psMap,
          overrideVersion: psVersion,
        );
      } else {
        stockId = stockRow.first['id'] as String;
        final psVersion = _hlc.next();
        final psMap = {
          'id': stockId,
          'product_id': productId,
          'store_id': storeId,
          'stock': newStock,
          'low_stock_alert': stockRow.first['low_stock_alert'],
          'version': psVersion,
          'updated_at': now.toIso8601String(),
        };
        await txn.update('product_stocks', psMap, where: 'id = ?', whereArgs: [stockId]);
        await _outbox.enqueue(
          txn: txn,
          tableName: 'product_stocks',
          rowId: stockId,
          op: 'update',
          payload: psMap,
          overrideVersion: psVersion,
        );
      }

      final movId = Ulid().toCanonical();
      final movVersion = _hlc.next();
      final movMap = {
        'id': movId,
        'store_id': storeId,
        'product_id': productId,
        'user_id': userId,
        'type': 'adjust',
        'quantity': delta,
        'balance_after': newStock,
        'cost_at_time': null,
        'reference_type': 'adjustment',
        'reference_id': null,
        'notes': notes,
        'version': movVersion,
        'created_at': now.toIso8601String(),
      };
      await txn.insert('stock_movements', movMap);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'stock_movements',
        rowId: movId,
        op: 'create',
        payload: movMap,
        overrideVersion: movVersion,
      );
    });
  }
}

final stockMovementRepositoryProvider = Provider<StockMovementRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return StockMovementRepository(db, outbox, hlc);
});
