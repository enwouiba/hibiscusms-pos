import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/dryclean_order.dart';

/// Yon liy sou yon lòd dry cleaning (rad + sèvis).
class DrycleanLineInput {
  final String? productId;
  final String name;
  final double quantity;
  final double unitPrice;
  final String? tagNumber;
  final String? conditionNotes;

  const DrycleanLineInput({
    this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.tagNumber,
    this.conditionNotes,
  });

  double get lineTotal => quantity * unitPrice;
}

class DrycleanRepository {
  DrycleanRepository(this._db, this._outbox, this._hlc);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  Future<int> _nextOrderNumber(String storeId) async {
    final r = await _db.rawQuery(
      'SELECT COALESCE(MAX(order_number), 0) AS m FROM dryclean_orders WHERE store_id = ?',
      [storeId],
    );
    return ((r.first['m'] as num?)?.toInt() ?? 0) + 1;
  }

  /// Kreye yon lòd: order + rad yo + outbox (atomik).
  Future<DrycleanOrder> create({
    required String storeId,
    String? userId,
    String? cashierName,
    String? customerName,
    String? customerPhone,
    DateTime? readyDate,
    required List<DrycleanLineInput> lines,
    double discount = 0,
    double deposit = 0,
    String? notes,
  }) async {
    final now = DateTime.now().toUtc();
    final orderId = Ulid().toCanonical();
    final orderNumber = await _nextOrderNumber(storeId);
    final subtotal = lines.fold<double>(0, (s, l) => s + l.lineTotal);
    final total = (subtotal - discount).clamp(0, double.infinity).toDouble();
    final version = _hlc.next();

    final orderMap = <String, dynamic>{
      'id': orderId,
      'store_id': storeId,
      'user_id': userId,
      'cashier_name': cashierName,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'order_number': orderNumber,
      'status': 'received',
      'ready_date': readyDate?.toIso8601String(),
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'amount_paid': deposit,
      'notes': notes,
      'version': version,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    final items = <DrycleanOrderItem>[];

    await _db.transaction((txn) async {
      await txn.insert('dryclean_orders', orderMap);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'dryclean_orders',
        rowId: orderId,
        op: 'create',
        payload: orderMap,
        overrideVersion: version,
      );

      for (final l in lines) {
        final itemId = Ulid().toCanonical();
        final itemMap = <String, dynamic>{
          'id': itemId,
          'order_id': orderId,
          'store_id': storeId,
          'product_id': l.productId,
          'name_snapshot': l.name,
          'quantity': l.quantity,
          'unit_price': l.unitPrice,
          'line_total': l.lineTotal,
          'tag_number': l.tagNumber,
          'condition_notes': l.conditionNotes,
          'version': _hlc.next(),
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };
        await txn.insert('dryclean_order_items', itemMap);
        await _outbox.enqueue(
          txn: txn,
          tableName: 'dryclean_order_items',
          rowId: itemId,
          op: 'create',
          payload: itemMap,
        );
        items.add(DrycleanOrderItem.fromMap(itemMap));
      }
    });

    return DrycleanOrder.fromMap(orderMap, items: items);
  }

  /// Lis lòd pou yon magazen (ak filtè estati opsyonèl).
  Future<List<DrycleanOrder>> list(String storeId, {DrycleanStatus? status}) async {
    final where = StringBuffer('store_id = ? AND (deleted_at IS NULL)');
    final args = <Object?>[storeId];
    if (status != null) {
      where.write(' AND status = ?');
      args.add(status.code);
    }
    final rows = await _db.query(
      'dryclean_orders',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map((m) => DrycleanOrder.fromMap(m)).toList();
  }

  /// Estatistik dry cleaning pou yon magazen (pou ekran Rapò a).
  Future<Map<String, num>> stats(String storeId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day).toUtc().toIso8601String();

    final r = await _db.rawQuery('''
      SELECT
        COUNT(*) AS total_orders,
        COALESCE(SUM(CASE WHEN status IN ('received','in_progress') THEN 1 ELSE 0 END), 0) AS pending,
        COALESCE(SUM(CASE WHEN status = 'ready' THEN 1 ELSE 0 END), 0) AS ready,
        COALESCE(SUM(CASE WHEN created_at >= ? THEN 1 ELSE 0 END), 0) AS today_count,
        COALESCE(SUM(CASE WHEN created_at >= ? THEN amount_paid ELSE 0 END), 0) AS today_revenue,
        COALESCE(SUM(CASE WHEN status != 'completed' THEN (total - amount_paid) ELSE 0 END), 0) AS uncollected
      FROM dryclean_orders
      WHERE store_id = ? AND (deleted_at IS NULL)
    ''', [startOfDay, startOfDay, storeId]);

    final row = r.first;
    return {
      'total_orders': (row['total_orders'] as num?) ?? 0,
      'pending': (row['pending'] as num?) ?? 0,
      'ready': (row['ready'] as num?) ?? 0,
      'today_count': (row['today_count'] as num?) ?? 0,
      'today_revenue': (row['today_revenue'] as num?) ?? 0,
      'uncollected': (row['uncollected'] as num?) ?? 0,
    };
  }

  Future<DrycleanOrder?> findById(String id) async {
    final rows = await _db.query('dryclean_orders', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final itemRows = await _db.query('dryclean_order_items', where: 'order_id = ?', whereArgs: [id]);
    final items = itemRows.map(DrycleanOrderItem.fromMap).toList();
    return DrycleanOrder.fromMap(rows.first, items: items);
  }

  /// Chanje estati yon lòd (Resevwa→Ap travay→Pare→Ranmase).
  Future<void> updateStatus(String orderId, DrycleanStatus status, {String? rackLocation}) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final rows = await txn.query('dryclean_orders', where: 'id = ?', whereArgs: [orderId], limit: 1);
      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first);
      map['status'] = status.code;
      map['version'] = version;
      map['updated_at'] = now.toIso8601String();
      if (rackLocation != null && rackLocation.isNotEmpty) {
        map['rack_location'] = rackLocation;
      }
      if (status == DrycleanStatus.completed) {
        map['completed_at'] = now.toIso8601String();
      }
      await txn.update('dryclean_orders', map, where: 'id = ?', whereArgs: [orderId]);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'dryclean_orders',
        rowId: orderId,
        op: 'update',
        payload: map,
        overrideVersion: version,
      );
    });
  }

  /// Ajoute yon peman sou yon lòd (depo oswa rès lè ranmase).
  Future<void> addPayment(String orderId, double amount) async {
    if (amount <= 0) return;
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final rows = await txn.query('dryclean_orders', where: 'id = ?', whereArgs: [orderId], limit: 1);
      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first);
      final paid = ((map['amount_paid'] as num?)?.toDouble() ?? 0) + amount;
      map['amount_paid'] = paid;
      map['version'] = version;
      map['updated_at'] = now.toIso8601String();
      await txn.update('dryclean_orders', map, where: 'id = ?', whereArgs: [orderId]);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'dryclean_orders',
        rowId: orderId,
        op: 'update',
        payload: map,
        overrideVersion: version,
      );
    });
  }
}

final drycleanRepositoryProvider = Provider<DrycleanRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return DrycleanRepository(db, outbox, hlc);
});
