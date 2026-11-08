import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/category.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/unit.dart';

class ProductRepository {
  ProductRepository(this._db, this._outbox, this._hlc, this._tokenStore);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;
  final TokenStore _tokenStore;

  /// Tenant (biznis) ki konekte a. Lè l non-nil, rekèt pwodwi yo limite
  /// sou li — konsa pwodwi yon lòt magazen ki ta rete nan baz lokal la
  /// (soti nan yon sesyon anvan) pa parèt nan katalòg magazen aktyèl la.
  /// Nou kite liy ki gen `tenant_id` nil pase: se pwodwi nou kreye offline
  /// ki poko senkronize, epi aparèy la konekte sou yon sèl tenant alafwa.
  Future<String?> _activeTenantId() => _tokenStore.activeTenantId();

  /// Lis tout pwodwi pou yon magazen, ak stock JOIN.
  Future<List<Product>> listAll(String storeId, {String? search, String? categoryId}) async {
    final tenantId = await _activeTenantId();
    final clauses = <String>['p.is_active = 1'];
    final args = <Object?>[];
    // Pwodwi magazen aktyèl la (oswa pwodwi pataje ak store_id NULL).
    clauses.add('(p.store_id = ? OR p.store_id IS NULL)');
    args.add(storeId);
    if (tenantId != null) {
      clauses.add('(p.tenant_id = ? OR p.tenant_id IS NULL)');
      args.add(tenantId);
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      clauses.add('(p.name LIKE ? OR p.sku LIKE ? OR p.barcode LIKE ?)');
      args..add(s)..add(s)..add(s);
    }
    if (categoryId != null) {
      clauses.add('p.category_id = ?');
      args.add(categoryId);
    }
    final where = clauses.join(' AND ');

    final rows = await _db.rawQuery('''
      SELECT p.*,
             COALESCE(ps.stock, 0) AS stock,
             COALESCE(ps.low_stock_alert, 5) AS low_stock_alert
        FROM products p
        LEFT JOIN product_stocks ps
               ON ps.product_id = p.id AND ps.store_id = ?
       WHERE $where
       ORDER BY p.name ASC
    ''', [storeId, ...args]);
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> findByBarcode(String storeId, String barcode) async {
    final tenantId = await _activeTenantId();
    final tenantClause = tenantId != null ? 'AND (p.tenant_id = ? OR p.tenant_id IS NULL)' : '';
    final rows = await _db.rawQuery('''
      SELECT p.*,
             COALESCE(ps.stock, 0) AS stock,
             COALESCE(ps.low_stock_alert, 5) AS low_stock_alert
        FROM products p
        LEFT JOIN product_stocks ps
               ON ps.product_id = p.id AND ps.store_id = ?
       WHERE p.barcode = ? AND p.is_active = 1
         AND (p.store_id = ? OR p.store_id IS NULL) $tenantClause
       LIMIT 1
    ''', [storeId, barcode, storeId, ?tenantId]);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<Product?> findById(String storeId, String id) async {
    final tenantId = await _activeTenantId();
    final tenantClause = tenantId != null ? 'AND (p.tenant_id = ? OR p.tenant_id IS NULL)' : '';
    final rows = await _db.rawQuery('''
      SELECT p.*,
             COALESCE(ps.stock, 0) AS stock,
             COALESCE(ps.low_stock_alert, 5) AS low_stock_alert
        FROM products p
        LEFT JOIN product_stocks ps
               ON ps.product_id = p.id AND ps.store_id = ?
       WHERE p.id = ? AND (p.store_id = ? OR p.store_id IS NULL) $tenantClause
       LIMIT 1
    ''', [storeId, id, storeId, ?tenantId]);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<List<Product>> listLowStock(String storeId) async {
    final tenantId = await _activeTenantId();
    final tenantClause = tenantId != null ? 'AND (p.tenant_id = ? OR p.tenant_id IS NULL)' : '';
    final rows = await _db.rawQuery('''
      SELECT p.*, ps.stock, ps.low_stock_alert
        FROM products p
        JOIN product_stocks ps ON ps.product_id = p.id AND ps.store_id = ?
       WHERE p.is_active = 1 AND p.track_stock = 1
         AND (p.store_id = ? OR p.store_id IS NULL)
         AND ps.stock <= ps.low_stock_alert $tenantClause
       ORDER BY (ps.stock - ps.low_stock_alert) ASC
    ''', [storeId, storeId, ?tenantId]);
    return rows.map(Product.fromMap).toList();
  }

  /// Kreye yon pwodwi nèf ak stock inisyal nan magazen aktyèl la.
  Future<Product> create({
    required String storeId,
    required String name,
    required String unitId,
    String? categoryId,
    String? sku,
    String? barcode,
    String? description,
    required double price,
    double cost = 0,
    double taxRate = 0,
    bool trackStock = true,
    String? imagePath,
    double initialStock = 0,
    double lowStockAlert = 5,
  }) async {
    final id = Ulid().toCanonical();
    final now = DateTime.now().toUtc();
    final version = _hlc.next();

    final product = Product(
      id: id,
      categoryId: categoryId,
      unitId: unitId,
      name: name,
      sku: sku,
      barcode: barcode,
      description: description,
      price: price,
      cost: cost,
      taxRate: taxRate,
      trackStock: trackStock,
      imagePath: imagePath,
      version: version,
      createdAt: now,
      updatedAt: now,
      stock: initialStock,
      lowStockAlert: lowStockAlert,
    );

    // Tague pwodwi a ak tenant aktyèl la depi kreyasyon an, konsa li
    // rete vizib sèlman pou magazen sa a menm anvan premye senkronizasyon.
    final tenantId = await _activeTenantId();
    final productMap = product.toMap();
    if (tenantId != null) {
      productMap['tenant_id'] = tenantId;
    }
    // Mare pwodwi a ak magazen kote l kreye a — konsa li pa parèt nan lòt
    // magazen yo (chak magazen gen pwòp pwodwi li).
    productMap['store_id'] = storeId;

    await _db.transaction((txn) async {
      await txn.insert('products', productMap);

      // Stock pa magazen
      final stockId = Ulid().toCanonical();
      final stockVersion = _hlc.next();
      await txn.insert('product_stocks', {
        'id': stockId,
        'product_id': id,
        'store_id': storeId,
        'stock': initialStock,
        'low_stock_alert': lowStockAlert,
        'version': stockVersion,
        'updated_at': now.toIso8601String(),
      });

      // Outbox: pwodwi + stock
      await _outbox.enqueue(
        txn: txn,
        tableName: 'products',
        rowId: id,
        op: 'create',
        payload: productMap,
        overrideVersion: version,
      );
      await _outbox.enqueue(
        txn: txn,
        tableName: 'product_stocks',
        rowId: stockId,
        op: 'create',
        payload: {
          'id': stockId,
          'product_id': id,
          'store_id': storeId,
          'stock': initialStock,
          'low_stock_alert': lowStockAlert,
          'version': stockVersion,
          'updated_at': now.toIso8601String(),
        },
        overrideVersion: stockVersion,
      );
    });

    return product;
  }

  Future<Product> update(Product p) async {
    final updated = p.copyWith(version: _hlc.next(), updatedAt: DateTime.now().toUtc());
    await _db.transaction((txn) async {
      await txn.update('products', updated.toMap(), where: 'id = ?', whereArgs: [updated.id]);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'products',
        rowId: updated.id,
        op: 'update',
        payload: updated.toMap(),
        overrideVersion: updated.version,
      );
    });
    return updated;
  }

  Future<void> updateStock({
    required String storeId,
    required String productId,
    required double newStock,
    double? lowStockAlert,
  }) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final existing = await txn.query(
        'product_stocks',
        where: 'product_id = ? AND store_id = ?',
        whereArgs: [productId, storeId],
        limit: 1,
      );
      String stockId;
      Map<String, Object?> payload;
      if (existing.isEmpty) {
        stockId = Ulid().toCanonical();
        payload = {
          'id': stockId,
          'product_id': productId,
          'store_id': storeId,
          'stock': newStock,
          'low_stock_alert': lowStockAlert ?? 5,
          'version': version,
          'updated_at': now.toIso8601String(),
        };
        await txn.insert('product_stocks', payload);
      } else {
        stockId = existing.first['id'] as String;
        payload = {
          'id': stockId,
          'product_id': productId,
          'store_id': storeId,
          'stock': newStock,
          'low_stock_alert': lowStockAlert ?? (existing.first['low_stock_alert'] as num?)?.toDouble() ?? 5,
          'version': version,
          'updated_at': now.toIso8601String(),
        };
        await txn.update('product_stocks', payload, where: 'id = ?', whereArgs: [stockId]);
      }
      await _outbox.enqueue(
        txn: txn,
        tableName: 'product_stocks',
        rowId: stockId,
        op: 'upsert',
        payload: payload,
        overrideVersion: version,
      );
    });
  }

  Future<void> delete(String productId) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      await txn.update(
        'products',
        {'is_active': 0, 'deleted_at': now.toIso8601String(), 'updated_at': now.toIso8601String(), 'version': version},
        where: 'id = ?',
        whereArgs: [productId],
      );
      await _outbox.enqueue(
        txn: txn,
        tableName: 'products',
        rowId: productId,
        op: 'delete',
        payload: {'id': productId},
        overrideVersion: version,
      );
    });
  }

  Future<List<Category>> listCategories(String storeId) async {
    final rows = await _db.rawQuery(
      'SELECT * FROM categories WHERE (store_id = ? OR store_id IS NULL) AND deleted_at IS NULL ORDER BY sort_order, name',
      [storeId],
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<List<Unit>> listUnits() async {
    final rows = await _db.query('units', orderBy: 'name');
    return rows.map(Unit.fromMap).toList();
  }
}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  final tokenStore = ref.watch(tokenStoreProvider);
  return ProductRepository(db, outbox, hlc, tokenStore);
});
