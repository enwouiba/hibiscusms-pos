import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/purchase.dart';

/// Item nan fom acha (volatile).
class PurchaseLineDraft {
  final Product product;
  final double quantity;
  final double cost;

  const PurchaseLineDraft({
    required this.product,
    required this.quantity,
    required this.cost,
  });

  double get subtotal => quantity * cost;

  PurchaseLineDraft copyWith({double? quantity, double? cost}) => PurchaseLineDraft(
        product: product,
        quantity: quantity ?? this.quantity,
        cost: cost ?? this.cost,
      );
}

class PurchaseRepository {
  PurchaseRepository(this._db, this._outbox, this._hlc);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  Future<Purchase> createPurchase({
    required String storeId,
    required String userId,
    String? supplierId,
    String? supplierName,
    String? invoiceNumber,
    String? notes,
    required List<PurchaseLineDraft> lines,
    double amountPaid = 0,
  }) async {
    if (lines.isEmpty) throw StateError('Acha pa gen liy.');
    final now = DateTime.now().toUtc();
    return _db.transaction((txn) async {
      // pwochen # acha
      final r = await txn.rawQuery(
        'SELECT COALESCE(MAX(purchase_number), 0) m FROM purchases WHERE store_id = ?',
        [storeId],
      );
      final purchaseNumber = ((r.first['m'] as num?) ?? 0).toInt() + 1;

      double subtotal = 0;
      for (final l in lines) {
        subtotal += l.subtotal;
      }
      final total = subtotal;

      final id = Ulid().toCanonical();
      final version = _hlc.next();
      final purchaseMap = {
        'id': id,
        'store_id': storeId,
        'supplier_id': supplierId,
        'user_id': userId,
        'invoice_number': invoiceNumber,
        'purchase_number': purchaseNumber,
        'subtotal': subtotal,
        'tax': 0.0,
        'total': total,
        'amount_paid': amountPaid,
        'status': 'received',
        'notes': notes,
        'version': version,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      await txn.insert('purchases', purchaseMap);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'purchases',
        rowId: id,
        op: 'create',
        payload: purchaseMap,
        overrideVersion: version,
      );

      final items = <PurchaseItem>[];
      for (final l in lines) {
        final itemId = Ulid().toCanonical();
        final itemMap = {
          'id': itemId,
          'purchase_id': id,
          'product_id': l.product.id,
          'name_snapshot': l.product.name,
          'quantity': l.quantity,
          'cost': l.cost,
          'subtotal': l.subtotal,
        };
        await txn.insert('purchase_items', itemMap);
        await _outbox.enqueue(
          txn: txn,
          tableName: 'purchase_items',
          rowId: itemId,
          op: 'create',
          payload: itemMap,
        );
        items.add(PurchaseItem.fromMap(itemMap));

        // Ajiste stock + stock_movement
        await _addStock(
          txn: txn,
          storeId: storeId,
          productId: l.product.id,
          userId: userId,
          quantity: l.quantity,
          costAtTime: l.cost,
          referenceId: id,
          now: now,
        );
      }

      return Purchase.fromMap(purchaseMap, items: items, supplierName: supplierName);
    });
  }

  Future<void> _addStock({
    required Transaction txn,
    required String storeId,
    required String productId,
    required String userId,
    required double quantity,
    required double costAtTime,
    required String referenceId,
    required DateTime now,
  }) async {
    final stockRow = await txn.query(
      'product_stocks',
      where: 'product_id = ? AND store_id = ?',
      whereArgs: [productId, storeId],
      limit: 1,
    );
    double balance;
    String stockId;
    if (stockRow.isEmpty) {
      stockId = Ulid().toCanonical();
      balance = quantity;
      final psVersion = _hlc.next();
      final psMap = {
        'id': stockId,
        'product_id': productId,
        'store_id': storeId,
        'stock': balance,
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
      balance = ((stockRow.first['stock'] as num?)?.toDouble() ?? 0) + quantity;
      final psVersion = _hlc.next();
      final psMap = {
        'id': stockId,
        'product_id': productId,
        'store_id': storeId,
        'stock': balance,
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
      'type': 'purchase',
      'quantity': quantity,
      'balance_after': balance,
      'cost_at_time': costAtTime,
      'reference_type': 'purchase',
      'reference_id': referenceId,
      'notes': null,
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
  }

  Future<List<Purchase>> listRecent(String storeId, {int limit = 50}) async {
    final rows = await _db.rawQuery('''
      SELECT p.*, s.name AS supplier_name
        FROM purchases p
        LEFT JOIN suppliers s ON s.id = p.supplier_id
       WHERE p.store_id = ?
       ORDER BY p.created_at DESC
       LIMIT ?
    ''', [storeId, limit]);
    return rows.map((r) => Purchase.fromMap(r, supplierName: r['supplier_name'] as String?)).toList();
  }

  Future<Purchase?> findById(String id) async {
    final rows = await _db.rawQuery('''
      SELECT p.*, s.name AS supplier_name
        FROM purchases p
        LEFT JOIN suppliers s ON s.id = p.supplier_id
       WHERE p.id = ?
       LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    final items = await _db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [id]);
    return Purchase.fromMap(
      rows.first,
      items: items.map(PurchaseItem.fromMap).toList(),
      supplierName: rows.first['supplier_name'] as String?,
    );
  }
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return PurchaseRepository(db, outbox, hlc);
});
