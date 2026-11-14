import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<String> getDatabasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, AppConstants.dbName);
  }

  Future<Database> _open() async {
    final path = await getDatabasePath();
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // FK dezaktive — sèvè a se sous laverite. FK ka chwa konfli pandan sync
    // lè timing tab yo pa egzakteman òdre (eg. product_stocks anvan stores).
    await db.execute('PRAGMA foreign_keys = OFF');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE stores (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        name TEXT NOT NULL,
        code TEXT NOT NULL UNIQUE,
        address TEXT,
        phone TEXT,
        currency TEXT NOT NULL DEFAULT 'HTG',
        timezone TEXT NOT NULL DEFAULT 'America/Port-au-Prince',
        is_active INTEGER NOT NULL DEFAULT 1,
        settings TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE roles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL,
        level INTEGER NOT NULL,
        permissions TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        phone TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        avatar_path TEXT,
        locale TEXT NOT NULL DEFAULT 'ht',
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE role_user (
        user_id TEXT NOT NULL,
        role_id TEXT NOT NULL,
        store_id TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT,
        parent_id TEXT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL DEFAULT 4286611584,
        icon TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
        FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE SET NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_categories_store ON categories(store_id)');

    batch.execute('''
      CREATE TABLE units (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        decimals INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE suppliers (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT,
        name TEXT NOT NULL,
        contact_name TEXT,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        balance REAL NOT NULL DEFAULT 0,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
      )
    ''');
    batch.execute('CREATE INDEX idx_suppliers_name ON suppliers(name)');

    batch.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        balance REAL NOT NULL DEFAULT 0,
        loyalty_points INTEGER NOT NULL DEFAULT 0,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
      )
    ''');
    batch.execute('CREATE INDEX idx_customers_phone ON customers(phone)');
    batch.execute('CREATE INDEX idx_customers_name ON customers(name)');

    batch.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT,
        category_id TEXT,
        unit_id TEXT NOT NULL,
        name TEXT NOT NULL,
        sku TEXT,
        barcode TEXT,
        description TEXT,
        price REAL NOT NULL,
        cost REAL NOT NULL DEFAULT 0,
        tax_rate REAL NOT NULL DEFAULT 0,
        track_stock INTEGER NOT NULL DEFAULT 1,
        image_path TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
        FOREIGN KEY (unit_id) REFERENCES units(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    batch.execute('CREATE INDEX idx_products_sku ON products(sku)');
    batch.execute('CREATE INDEX idx_products_category ON products(category_id)');
    batch.execute('CREATE INDEX idx_products_active ON products(is_active)');
    batch.execute('CREATE INDEX idx_products_store ON products(store_id)');

    batch.execute('''
      CREATE TABLE product_stocks (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        product_id TEXT NOT NULL,
        store_id TEXT NOT NULL,
        stock REAL NOT NULL DEFAULT 0,
        low_stock_alert REAL NOT NULL DEFAULT 5,
        location TEXT,
        version TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
      )
    ''');
    batch.execute('CREATE UNIQUE INDEX uq_product_store ON product_stocks(product_id, store_id)');
    batch.execute('CREATE INDEX idx_ps_low ON product_stocks(store_id, stock, low_stock_alert)');

    batch.execute('''
      CREATE TABLE stock_movements (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        user_id TEXT,
        type TEXT NOT NULL CHECK (type IN ('sale','purchase','adjust','transfer_in','transfer_out','return','damage')),
        quantity REAL NOT NULL,
        balance_after REAL NOT NULL,
        cost_at_time REAL,
        reference_type TEXT,
        reference_id TEXT,
        notes TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_sm_product ON stock_movements(product_id, created_at)');
    batch.execute('CREATE INDEX idx_sm_store ON stock_movements(store_id, created_at)');
    batch.execute('CREATE INDEX idx_sm_ref ON stock_movements(reference_type, reference_id)');

    batch.execute('''
      CREATE TABLE cash_sessions (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        opening_balance REAL NOT NULL DEFAULT 0,
        closing_balance REAL,
        expected_balance REAL,
        difference REAL,
        total_sales REAL NOT NULL DEFAULT 0,
        total_cash REAL NOT NULL DEFAULT 0,
        notes TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE purchases (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT NOT NULL,
        supplier_id TEXT,
        user_id TEXT NOT NULL,
        invoice_number TEXT,
        purchase_number INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        tax REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL,
        amount_paid REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'received',
        notes TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');
    batch.execute('CREATE UNIQUE INDEX uq_purchase_num ON purchases(store_id, purchase_number)');

    batch.execute('''
      CREATE TABLE purchase_items (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        purchase_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        name_snapshot TEXT NOT NULL,
        quantity REAL NOT NULL,
        cost REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        cashier_name TEXT,
        customer_id TEXT,
        cash_session_id TEXT,
        sale_number INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL,
        amount_received REAL,
        change_due REAL,
        amount_due REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'completed',
        notes TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL,
        FOREIGN KEY (cash_session_id) REFERENCES cash_sessions(id) ON DELETE SET NULL
      )
    ''');
    batch.execute('CREATE UNIQUE INDEX uq_sale_num ON sales(store_id, sale_number)');
    batch.execute('CREATE INDEX idx_sales_created ON sales(store_id, created_at)');

    batch.execute('''
      CREATE TABLE sale_items (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        sale_id TEXT NOT NULL,
        product_id TEXT,
        name_snapshot TEXT NOT NULL,
        sku_snapshot TEXT,
        price_snapshot REAL NOT NULL,
        cost_snapshot REAL NOT NULL DEFAULT 0,
        tax_rate_snapshot REAL NOT NULL DEFAULT 0,
        quantity REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_sale_items_sale ON sale_items(sale_id)');

    batch.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        sale_id TEXT,
        purchase_id TEXT,
        user_id TEXT NOT NULL,
        method TEXT NOT NULL CHECK (method IN ('cash','mon_cash','natcash','card','bank_transfer','credit','check')),
        amount REAL NOT NULL,
        reference TEXT,
        notes TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        cash_session_id TEXT,
        category TEXT,
        description TEXT NOT NULL,
        amount REAL NOT NULL,
        receipt_path TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
        FOREIGN KEY (cash_session_id) REFERENCES cash_sessions(id) ON DELETE SET NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE backup_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        backup_at TEXT NOT NULL,
        drive_file_id TEXT,
        file_name TEXT,
        size_bytes INTEGER,
        status TEXT NOT NULL,
        error_message TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        op_id TEXT NOT NULL UNIQUE,
        table_name TEXT NOT NULL,
        row_id TEXT NOT NULL,
        op TEXT NOT NULL CHECK (op IN ('create','update','delete','upsert')),
        payload TEXT NOT NULL,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        last_attempt_at TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_outbox_pending ON sync_outbox(attempts, created_at)');

    batch.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE customer_payments (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT,
        customer_id TEXT NOT NULL,
        user_id TEXT,
        sale_id TEXT,
        amount REAL NOT NULL,
        method TEXT NOT NULL DEFAULT 'cash',
        type TEXT NOT NULL DEFAULT 'payment',
        notes TEXT,
        reason TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
      )
    ''');
    batch.execute('CREATE INDEX idx_customer_payments_customer ON customer_payments(customer_id)');

    // manual_adjustments — pou +/- sou VANT NÈT ak KREDIT (v6)
    batch.execute('''
      CREATE TABLE manual_adjustments (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT,
        user_id TEXT,
        target TEXT NOT NULL,
        operation TEXT NOT NULL,
        amount REAL NOT NULL,
        reason TEXT NOT NULL,
        notes TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_ma_store ON manual_adjustments(store_id)');
    batch.execute('CREATE INDEX idx_ma_target ON manual_adjustments(target)');

    // Dry cleaning — lòd ak rad yo (v8)
    batch.execute(_sqlDrycleanOrders);
    batch.execute('CREATE INDEX idx_dco_store_status ON dryclean_orders(store_id, status)');
    batch.execute(_sqlDrycleanItems);
    batch.execute('CREATE INDEX idx_dcoi_order ON dryclean_order_items(order_id)');

    // Otèl — chanm ak sejou (v10)
    batch.execute(_sqlHotelRooms);
    batch.execute('CREATE INDEX idx_hr_store_status ON hotel_rooms(store_id, status)');
    batch.execute(_sqlHotelStays);
    batch.execute('CREATE INDEX idx_hs_store_status ON hotel_stays(store_id, status)');
    batch.execute('CREATE INDEX idx_hs_room ON hotel_stays(room_id, status)');

    await batch.commit(noResult: true);
  }

  static const String _sqlDrycleanOrders = '''
      CREATE TABLE dryclean_orders (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT,
        user_id TEXT,
        cashier_name TEXT,
        customer_id TEXT,
        customer_name TEXT,
        customer_phone TEXT,
        order_number INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'received',
        rack_location TEXT,
        ready_date TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        notes TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT,
        deleted_at TEXT
      )
  ''';

  static const String _sqlDrycleanItems = '''
      CREATE TABLE dryclean_order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        store_id TEXT,
        product_id TEXT,
        name_snapshot TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        tag_number TEXT,
        condition_notes TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
  ''';

  static const String _sqlHotelRooms = '''
      CREATE TABLE hotel_rooms (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT,
        name TEXT NOT NULL,
        room_type TEXT,
        price_per_night REAL NOT NULL DEFAULT 0,
        price_per_hour REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'available',
        notes TEXT,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
  ''';

  static const String _sqlHotelStays = '''
      CREATE TABLE hotel_stays (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        store_id TEXT,
        user_id TEXT,
        cashier_name TEXT,
        room_id TEXT NOT NULL,
        room_name_snapshot TEXT,
        guest_name TEXT,
        guest_phone TEXT,
        guest_id_doc TEXT,
        mode TEXT NOT NULL DEFAULT 'nightly',
        duration INTEGER NOT NULL DEFAULT 1,
        rate REAL NOT NULL DEFAULT 0,
        stay_number INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        check_in_at TEXT NOT NULL,
        check_out_at TEXT,
        extra REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        notes TEXT,
        proforma_validated INTEGER NOT NULL DEFAULT 0,
        version TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
  ''';

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Ajoute kolòn cashier_name pou tras kèsye ki fè chak vant
      try {
        await db.execute('ALTER TABLE sales ADD COLUMN cashier_name TEXT');
      } catch (_) {} // si deja egziste
    }
    if (oldVersion < 3) {
      // Multi-tenant: ajoute tenant_id sou tout tab biznis-scope
      const tables = [
        'stores', 'users', 'categories', 'units', 'suppliers', 'customers',
        'products', 'product_stocks', 'stock_movements', 'cash_sessions',
        'purchases', 'purchase_items', 'sales', 'sale_items', 'payments', 'expenses',
      ];
      for (final t in tables) {
        try {
          await db.execute('ALTER TABLE $t ADD COLUMN tenant_id TEXT');
        } catch (_) {} // si deja egziste
      }
      // Re-pull tout done yo paske ansyen yo gen dwa pa gen tenant_id mache
      try {
        await db.delete('sync_state');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      // Customer debt tracking — `amount_due` on sales tracks unpaid portion.
      try { await db.execute('ALTER TABLE sales ADD COLUMN amount_due REAL NOT NULL DEFAULT 0'); } catch (_) {}
      // customer_payments — every cash-in from a customer reducing their balance.
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS customer_payments (
            id TEXT PRIMARY KEY,
            tenant_id TEXT,
            store_id TEXT,
            customer_id TEXT NOT NULL,
            user_id TEXT,
            sale_id TEXT,
            amount REAL NOT NULL,
            method TEXT NOT NULL DEFAULT 'cash',
            notes TEXT,
            version TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_customer_payments_customer ON customer_payments(customer_id)');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      // v5: ajoute type + reason kolòn nan customer_payments
      try {
        await db.execute("ALTER TABLE customer_payments ADD COLUMN type TEXT NOT NULL DEFAULT 'payment'");
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE customer_payments ADD COLUMN reason TEXT');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      // v6: manual_adjustments — pou +/- sou VANT NÈT ak KREDIT
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS manual_adjustments (
            id TEXT PRIMARY KEY,
            tenant_id TEXT,
            store_id TEXT,
            user_id TEXT,
            target TEXT NOT NULL,
            operation TEXT NOT NULL,
            amount REAL NOT NULL,
            reason TEXT NOT NULL,
            notes TEXT,
            version TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT,
            deleted_at TEXT
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ma_store ON manual_adjustments(store_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ma_target ON manual_adjustments(target)');
      } catch (_) {}
    }

    if (oldVersion < 7) {
      // v7: pwodwi pa magazen — chak magazen gen pwòp pwodwi li.
      // store_id NULL = pwodwi pataje (ansyen konpòtman, bak-end jere l).
      try {
        await db.execute('ALTER TABLE products ADD COLUMN store_id TEXT');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_store ON products(store_id)');
      } catch (_) {}
    }

    if (oldVersion < 8) {
      // v8: dry cleaning — tab lòd + rad yo
      try {
        await db.execute(_sqlDrycleanOrders.replaceFirst('CREATE TABLE', 'CREATE TABLE IF NOT EXISTS'));
        await db.execute('CREATE INDEX IF NOT EXISTS idx_dco_store_status ON dryclean_orders(store_id, status)');
        await db.execute(_sqlDrycleanItems.replaceFirst('CREATE TABLE', 'CREATE TABLE IF NOT EXISTS'));
        await db.execute('CREATE INDEX IF NOT EXISTS idx_dcoi_order ON dryclean_order_items(order_id)');
      } catch (_) {}
    }

    if (oldVersion < 9) {
      // v9: rack/kote pou dry cleaning
      try {
        await db.execute('ALTER TABLE dryclean_orders ADD COLUMN rack_location TEXT');
      } catch (_) {}
    }

    if (oldVersion < 10) {
      // v10: jesyon otèl — chanm ak sejou
      try {
        await db.execute(_sqlHotelRooms);
        await db.execute('CREATE INDEX IF NOT EXISTS idx_hr_store_status ON hotel_rooms(store_id, status)');
        await db.execute(_sqlHotelStays);
        await db.execute('CREATE INDEX IF NOT EXISTS idx_hs_store_status ON hotel_stays(store_id, status)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_hs_room ON hotel_stays(room_id, status)');
      } catch (_) {}
    }

    if (oldVersion < 11) {
      // v11: NIF/CIN kliyan sou sejou otèl
      try {
        await db.execute('ALTER TABLE hotel_stays ADD COLUMN guest_id_doc TEXT');
      } catch (_) {}
    }

    if (oldVersion < 12) {
      // v12: pofoma valide (devi -> fakti) pou sejou otèl
      try {
        await db.execute('ALTER TABLE hotel_stays ADD COLUMN proforma_validated INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
