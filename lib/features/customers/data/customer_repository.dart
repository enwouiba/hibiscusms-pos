import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/customer.dart';

class CustomerRepository {
  CustomerRepository(this._db, this._outbox, this._hlc);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  Future<List<Customer>> list(String storeId, {String? search}) async {
    final clauses = <String>['(store_id = ? OR store_id IS NULL)', 'deleted_at IS NULL'];
    final args = <Object?>[storeId];
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      clauses.add('(name LIKE ? OR phone LIKE ?)');
      args..add(s)..add(s);
    }
    final rows = await _db.query(
      'customers',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'name',
    );
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> findById(String id) async {
    final rows = await _db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<Customer> create({
    required String storeId,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async {
    final id = Ulid().toCanonical();
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    final customer = Customer(
      id: id,
      storeId: storeId,
      name: name,
      phone: phone,
      email: email,
      address: address,
      notes: notes,
      version: version,
      createdAt: now,
      updatedAt: now,
    );
    await _db.transaction((txn) async {
      await txn.insert('customers', customer.toMap());
      await _outbox.enqueue(
        txn: txn,
        tableName: 'customers',
        rowId: id,
        op: 'create',
        payload: customer.toMap(),
        overrideVersion: version,
      );
    });
    return customer;
  }

  Future<Customer> update(Customer c) async {
    final updated = c.copyWith(version: _hlc.next(), updatedAt: DateTime.now().toUtc());
    await _db.transaction((txn) async {
      await txn.update('customers', updated.toMap(), where: 'id = ?', whereArgs: [updated.id]);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'customers',
        rowId: updated.id,
        op: 'update',
        payload: updated.toMap(),
        overrideVersion: updated.version,
      );
    });
    return updated;
  }

  /// Adjust customer balance by +/- amount (positive = customer owes more).
  /// Used when a sale is partially paid (debt added) or when a payment is
  /// received (debt reduced — call with a negative delta).
  Future<Customer?> adjustBalance(String id, double delta, {Transaction? txn}) async {
    Future<Customer?> run(Transaction t) async {
      final rows = await t.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return null;
      final c = Customer.fromMap(rows.first);
      final updated = c.copyWith(
        balance: c.balance + delta,
        version: _hlc.next(),
        updatedAt: DateTime.now().toUtc(),
      );
      await t.update('customers', updated.toMap(), where: 'id = ?', whereArgs: [id]);
      await _outbox.enqueue(
        txn: t,
        tableName: 'customers',
        rowId: id,
        op: 'update',
        payload: updated.toMap(),
        overrideVersion: updated.version,
      );
      return updated;
    }
    if (txn != null) return run(txn);
    return _db.transaction(run);
  }

  /// Record a payment from a customer (cash-in) and reduce their balance.
  Future<void> recordPayment({
    required String customerId,
    required double amount,
    String? storeId,
    String? userId,
    String? saleId,
    String method = 'cash',
    String? notes,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');
    final now = DateTime.now().toUtc();
    final paymentId = Ulid().toCanonical();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final payMap = {
        'id': paymentId,
        'store_id': storeId,
        'customer_id': customerId,
        'user_id': userId,
        'sale_id': saleId,
        'amount': amount,
        'method': method,
        'type': 'payment',
        'notes': notes,
        'version': version,
        'created_at': now.toIso8601String(),
      };
      await txn.insert('customer_payments', payMap);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'customer_payments',
        rowId: paymentId,
        op: 'create',
        payload: payMap,
        overrideVersion: version,
      );
      await adjustBalance(customerId, -amount, txn: txn);
    });
  }

  /// Ajoute dèt manyèl bay yon kliyan (san bezwen fè yon fakti).
  /// Egzanp: kliyan te achte yon bagay ki pat pase nan POS, oswa te prete.
  Future<void> recordDebtAddition({
    required String customerId,
    required double amount,
    required String reason,
    String? storeId,
    String? userId,
    String? notes,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');
    if (reason.trim().isEmpty) throw ArgumentError('reason obligatwa');
    final now = DateTime.now().toUtc();
    final paymentId = Ulid().toCanonical();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final payMap = {
        'id': paymentId,
        'store_id': storeId,
        'customer_id': customerId,
        'user_id': userId,
        'sale_id': null,
        'amount': amount,
        'method': 'cash',
        'type': 'debt_addition',
        'notes': notes,
        'reason': reason,
        'version': version,
        'created_at': now.toIso8601String(),
      };
      await txn.insert('customer_payments', payMap);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'customer_payments',
        rowId: paymentId,
        op: 'create',
        payload: payMap,
        overrideVersion: version,
      );
      // Ojmante dèt (kontrè peman)
      await adjustBalance(customerId, amount, txn: txn);
    });
  }

  /// Lis tout tranzaksyon dèt (peman + ajoute) pou yon kliyan
  Future<List<Map<String, Object?>>> listDebtTransactions(String customerId, {int limit = 50}) async {
    return await _db.query(
      'customer_payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<List<Customer>> listWithDebt(String storeId) async {
    final rows = await _db.query(
      'customers',
      where: '(store_id = ? OR store_id IS NULL) AND deleted_at IS NULL AND balance > 0',
      whereArgs: [storeId],
      orderBy: 'balance DESC',
    );
    return rows.map(Customer.fromMap).toList();
  }

  Future<double> totalOutstandingDebt(String storeId) async {
    final r = await _db.rawQuery(
      'SELECT COALESCE(SUM(balance), 0) AS d FROM customers WHERE (store_id = ? OR store_id IS NULL) AND deleted_at IS NULL',
      [storeId],
    );
    return (r.first['d'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> recentPayments(String customerId, {int limit = 20}) async {
    return _db.query(
      'customer_payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      await txn.update(
        'customers',
        {'deleted_at': now.toIso8601String(), 'updated_at': now.toIso8601String(), 'version': version},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _outbox.enqueue(
        txn: txn,
        tableName: 'customers',
        rowId: id,
        op: 'delete',
        payload: {'id': id},
        overrideVersion: version,
      );
    });
  }
}

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return CustomerRepository(db, outbox, hlc);
});
