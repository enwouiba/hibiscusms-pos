import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/cart_item.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/sale.dart';

class SaleRepository {
  SaleRepository(this._db, this._outbox, this._hlc);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  /// Kreye yon vant atomik: sale + items + stock_movements + payments + outbox.
  ///
  /// If [allowDebt] is true and [amountReceived] < total, the unpaid portion
  /// is added to the customer's balance as debt (sale status becomes 'credit').
  /// If [customerId] is null but [customerName] is provided, a new Customer
  /// row is created on the fly (so the cashier doesn't have to pre-register).
  Future<Sale> createSale({
    required String storeId,
    required String userId,
    required String cashierName,
    required List<CartItem> cart,
    required PaymentMethod paymentMethod,
    required double amountReceived,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? cashSessionId,
    String? notes,
    double extraDiscount = 0,
    bool allowDebt = false,
  }) async {
    if (cart.isEmpty) throw StateError('Kart la vid.');

    final now = DateTime.now().toUtc();

    return _db.transaction((txn) async {
      // 0. Auto-create customer if a name was typed but no id was selected.
      if (customerId == null && (customerName ?? '').trim().isNotEmpty) {
        final newId = Ulid().toCanonical();
        final cVersion = _hlc.next();
        final customer = Customer(
          id: newId,
          storeId: storeId,
          name: customerName!.trim(),
          phone: (customerPhone ?? '').trim().isEmpty ? null : customerPhone!.trim(),
          version: cVersion,
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('customers', customer.toMap());
        await _outbox.enqueue(
          txn: txn,
          tableName: 'customers',
          rowId: newId,
          op: 'create',
          payload: customer.toMap(),
          overrideVersion: cVersion,
        );
        customerId = newId;
      }
      // 1. Kalkile total
      double subtotal = 0;
      double taxTotal = 0;
      for (final c in cart) {
        subtotal += c.subtotal;
        taxTotal += c.taxAmount;
      }
      final total = (subtotal - extraDiscount + taxTotal).clamp(0, double.infinity).toDouble();

      // 2. Pwochen sale_number pou magazen sa
      final maxRow = await txn.rawQuery(
        'SELECT COALESCE(MAX(sale_number), 0) AS m FROM sales WHERE store_id = ?',
        [storeId],
      );
      final saleNumber = ((maxRow.first['m'] as num?) ?? 0).toInt() + 1;

      // Determine debt: if partial paid + allowed + customer set, the difference
      // becomes outstanding debt added to the customer's balance.
      final paidNow = amountReceived.clamp(0, total).toDouble();
      final unpaid = (total - paidNow).clamp(0, double.infinity).toDouble();
      final isCredit = allowDebt && unpaid > 0 && customerId != null;
      if (unpaid > 0 && !isCredit) {
        throw StateError('Kantite resi pa ase, e pa gen kliyan pou pòte det la.');
      }

      // 3. Kreye sale
      final saleId = Ulid().toCanonical();
      final saleVersion = _hlc.next();
      final saleMap = {
        'id': saleId,
        'store_id': storeId,
        'user_id': userId,
        'cashier_name': cashierName,
        'customer_id': customerId,
        'cash_session_id': cashSessionId,
        'sale_number': saleNumber,
        'subtotal': subtotal,
        'discount': extraDiscount,
        'tax': taxTotal,
        'total': total,
        'amount_received': paidNow,
        'change_due': amountReceived - total > 0 ? amountReceived - total : 0,
        'amount_due': unpaid,
        'status': isCredit ? 'credit' : 'completed',
        'notes': notes,
        'version': saleVersion,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      await txn.insert('sales', saleMap);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'sales',
        rowId: saleId,
        op: 'create',
        payload: saleMap,
        overrideVersion: saleVersion,
      );

      // 4. Sale items + mouvman stock
      final items = <SaleItem>[];
      for (final c in cart) {
        final itemId = Ulid().toCanonical();
        final itemMap = {
          'id': itemId,
          'sale_id': saleId,
          'product_id': c.product.id,
          'name_snapshot': c.product.name,
          'sku_snapshot': c.product.sku,
          'price_snapshot': c.product.price,
          'cost_snapshot': c.product.cost,
          'tax_rate_snapshot': c.product.taxRate,
          'quantity': c.quantity,
          'discount': c.discount,
          'subtotal': c.subtotal,
        };
        await txn.insert('sale_items', itemMap);
        await _outbox.enqueue(
          txn: txn,
          tableName: 'sale_items',
          rowId: itemId,
          op: 'create',
          payload: itemMap,
        );
        items.add(SaleItem.fromMap(itemMap));

        // Stock movement (sale = quantity negatif)
        if (c.product.trackStock) {
          await _moveStock(
            txn: txn,
            storeId: storeId,
            productId: c.product.id,
            userId: userId,
            type: 'sale',
            quantity: -c.quantity,
            costAtTime: c.product.cost,
            referenceType: 'sale',
            referenceId: saleId,
            now: now,
          );
        }
      }

      // 5. Peman (only record what was actually paid right now)
      final payments = <Payment>[];
      if (paidNow > 0) {
        final paymentId = Ulid().toCanonical();
        final payVersion = _hlc.next();
        final payMap = {
          'id': paymentId,
          'sale_id': saleId,
          'purchase_id': null,
          'user_id': userId,
          'method': paymentMethod.code,
          'amount': paidNow,
          'reference': null,
          'notes': null,
          'version': payVersion,
          'created_at': now.toIso8601String(),
        };
        await txn.insert('payments', payMap);
        await _outbox.enqueue(
          txn: txn,
          tableName: 'payments',
          rowId: paymentId,
          op: 'create',
          payload: payMap,
          overrideVersion: payVersion,
        );
        payments.add(Payment.fromMap(payMap));
      }

      // 6. If credit sale, add the unpaid portion to the customer's balance.
      if (isCredit && customerId != null) {
        final cid = customerId!;
        final cRows = await txn.query('customers', where: 'id = ?', whereArgs: [cid], limit: 1);
        if (cRows.isNotEmpty) {
          final c = Customer.fromMap(cRows.first);
          final updated = c.copyWith(
            balance: c.balance + unpaid,
            version: _hlc.next(),
            updatedAt: now,
          );
          await txn.update('customers', updated.toMap(), where: 'id = ?', whereArgs: [cid]);
          await _outbox.enqueue(
            txn: txn,
            tableName: 'customers',
            rowId: cid,
            op: 'update',
            payload: updated.toMap(),
            overrideVersion: updated.version,
          );
        }
      }

      return Sale.fromMap(
        saleMap,
        items: items,
        payments: payments,
        customerName: customerName,
      );
    });
  }

  Future<void> _moveStock({
    required Transaction txn,
    required String storeId,
    required String productId,
    required String userId,
    required String type,
    required double quantity,
    required DateTime now,
    double? costAtTime,
    String? referenceType,
    String? referenceId,
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
      'type': type,
      'quantity': quantity,
      'balance_after': balance,
      'cost_at_time': costAtTime,
      'reference_type': referenceType,
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

  Future<List<Sale>> listRecent(String storeId, {int limit = 50}) async {
    // Ekskli vant ki efase yo (soft-deleted) — konsistan ak dashboard/reports
    final rows = await _db.rawQuery('''
      SELECT s.*, c.name AS customer_name
        FROM sales s
        LEFT JOIN customers c ON c.id = s.customer_id
       WHERE s.store_id = ? AND s.deleted_at IS NULL
       ORDER BY s.created_at DESC
       LIMIT ?
    ''', [storeId, limit]);
    return rows.map((r) => Sale.fromMap(r, customerName: r['customer_name'] as String?)).toList();
  }

  Future<Sale?> findById(String id) async {
    final rows = await _db.rawQuery('''
      SELECT s.*, c.name AS customer_name
        FROM sales s
        LEFT JOIN customers c ON c.id = s.customer_id
       WHERE s.id = ?
       LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    final items = await _db.query('sale_items', where: 'sale_id = ?', whereArgs: [id]);
    final payments = await _db.query('payments', where: 'sale_id = ?', whereArgs: [id]);
    return Sale.fromMap(
      rows.first,
      items: items.map(SaleItem.fromMap).toList(),
      payments: payments.map(Payment.fromMap).toList(),
      customerName: rows.first['customer_name'] as String?,
    );
  }

  /// Efase yon vant (soft delete) + restore stock.
  /// Sèlman admin+ ka rele sa.
  Future<void> deleteSale(String saleId) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();

    await _db.transaction((txn) async {
      // 1. Chèche vant la + items
      final saleRows = await txn.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (saleRows.isEmpty) return;
      final storeId = saleRows.first['store_id'] as String;
      final userId = saleRows.first['user_id'] as String;
      final items = await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);

      // 2. Pou chak item, retounen stock la
      for (final item in items) {
        final productId = item['product_id'] as String?;
        if (productId == null) continue;
        final qty = (item['quantity'] as num).toDouble();
        // Ajoute back to stock
        final stockRow = await txn.query(
          'product_stocks',
          where: 'product_id = ? AND store_id = ?',
          whereArgs: [productId, storeId],
          limit: 1,
        );
        if (stockRow.isNotEmpty) {
          final stockId = stockRow.first['id'] as String;
          final newStock = ((stockRow.first['stock'] as num?)?.toDouble() ?? 0) + qty;
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

          // Mouvman stock 'return'
          final movId = Ulid().toCanonical();
          final movMap = {
            'id': movId,
            'store_id': storeId,
            'product_id': productId,
            'user_id': userId,
            'type': 'return',
            'quantity': qty,
            'balance_after': newStock,
            'cost_at_time': item['cost_snapshot'],
            'reference_type': 'sale_delete',
            'reference_id': saleId,
            'notes': 'Vant efase',
            'version': _hlc.next(),
            'created_at': now.toIso8601String(),
          };
          await txn.insert('stock_movements', movMap);
        }
      }

      // 3. Soft delete sale
      final saleUpdate = {
        'deleted_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'version': version,
        'status': 'cancelled',
      };
      await txn.update('sales', saleUpdate, where: 'id = ?', whereArgs: [saleId]);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'sales',
        rowId: saleId,
        op: 'delete',
        payload: {'id': saleId},
        overrideVersion: version,
      );
    });
  }

  /// Statistik jou prensipal pou dashboard.
  /// Filtè menm jan ak _homeStatsProvider ak reports_screen.
  Future<Map<String, double>> dailyStats(String storeId) async {
    // Kalkile startOfDay lokal, konvèti nan UTC — pi kòrèk pase soustraksyon jou aktyèl
    final n = DateTime.now();
    final startOfDay = DateTime(n.year, n.month, n.day).toUtc().toIso8601String();
    final endOfDay = DateTime(n.year, n.month, n.day, 23, 59, 59).toUtc().toIso8601String();
    final r = await _db.rawQuery('''
      SELECT COALESCE(SUM(total), 0) AS revenue, COUNT(*) AS count
        FROM sales
       WHERE store_id = ?
         AND status = 'completed'
         AND deleted_at IS NULL
         AND created_at >= ? AND created_at <= ?
    ''', [storeId, startOfDay, endOfDay]);
    return {
      'revenue': (r.first['revenue'] as num?)?.toDouble() ?? 0,
      'count': (r.first['count'] as num?)?.toDouble() ?? 0,
    };
  }
}

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return SaleRepository(db, outbox, hlc);
});
