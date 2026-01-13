// lib/data/local/app_db.dart
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDb {
  static const _dbName = 'vos_app.db';

  // Local DB is just a cache; sync_repository is the source of truth.
  // ✅ v35: Fix v_sales_report_itemized join (details join must not require order_id match)
  static const _dbVersion = 35;

  static Database? _instance;

  static Future<Database> get() async {
    if (_instance != null) return _instance!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    _instance = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _instance!;
  }

  /* -------------------------------------------------------------------------- */
  /*                               Schema creation                              */
  /* -------------------------------------------------------------------------- */

  static Future<void> _onCreate(Database db, int v) async {
    // Core tables
    await db.execute('''
      CREATE TABLE post_dispatch_plan (
        id INTEGER PRIMARY KEY,
        doc_no TEXT,
        driver_id INTEGER,
        encoder_id INTEGER,
        starting_point INTEGER,
        vehicle_id INTEGER,
        status TEXT,
        amount REAL,
        estimated_time_of_dispatch TEXT,
        estimated_time_of_arrival TEXT,
        time_of_dispatch TEXT,
        time_of_arrival TEXT,
        date_encoded TEXT,
        remarks TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE post_dispatch_invoices (
        id INTEGER PRIMARY KEY,
        invoice_id INTEGER,
        post_dispatch_plan_id INTEGER,
        sequence INTEGER,
        status TEXT,
        distance REAL,
        invoiceAt INTEGER,
        isCleared INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE sales_invoice (
        invoice_id INTEGER PRIMARY KEY,
        invoice_no TEXT,
        invoice_date TEXT,
        customer_code TEXT,
        branch_id INTEGER,
        gross_amount REAL,
        total_amount REAL,
        discount_amount REAL,
        net_amount REAL,
        order_id TEXT,
        dispatch_date TEXT,
        payment_status TEXT,
        transaction_status TEXT,
        due_date TEXT,
        payment_terms INTEGER,
        is_posted INTEGER DEFAULT 0,

        /* for v_sales_report */
        salesman_id INTEGER,
        sales_type INTEGER,
        invoice_type INTEGER,
        price_type TEXT,
        created_by INTEGER,
        created_date TEXT,
        modified_by INTEGER,
        modified_date TEXT,
        isReceipt INTEGER DEFAULT 0,
        isDispatched INTEGER DEFAULT 0,
        isRemitted INTEGER DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE TABLE sales_order (
        order_id INTEGER PRIMARY KEY,
        order_no TEXT,
        customer_code TEXT,
        supplier_id INTEGER,
        branch_id INTEGER,
        order_status TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE user (
        user_id INTEGER PRIMARY KEY,
        user_fname TEXT,
        user_mname TEXT,
        user_lname TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE branches (
        id INTEGER PRIMARY KEY,
        branch_name TEXT,
        city TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE vehicles (
        vehicle_id INTEGER PRIMARY KEY,
        vehicle_plate TEXT,
        status TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE customer (
        customer_code TEXT PRIMARY KEY,
        customer_name TEXT,
        brgy TEXT,
        city TEXT,
        province TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY,
        supplier_shortcut TEXT,
        supplier_name TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE post_dispatch_budgeting (
        id INTEGER PRIMARY KEY,
        post_dispatch_plan_id INTEGER,
        coa_id INTEGER,
        remarks TEXT,
        amount REAL
      );
    ''');

    await db.execute('''
      CREATE TABLE post_dispatch_plan_staff (
        id INTEGER PRIMARY KEY,
        post_dispatch_plan_id INTEGER,
        user_id INTEGER,
        role TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE sales_invoice_payments (
        id INTEGER PRIMARY KEY,
        invoice_id INTEGER,
        order_id TEXT,
        coa_id INTEGER,
        bank_id INTEGER,
        reference_no TEXT,
        paid_amount REAL,
        date_paid TEXT,
        date_encoded TEXT
      );
    ''');

    // AP / Disbursement base tables
    await _createAPTables(db);

    // Sales Return header
    await db.execute('''
      CREATE TABLE sales_return (
        return_id INTEGER PRIMARY KEY,
        return_number TEXT,
        customer_code TEXT,
        salesman_id INTEGER,
        branch_id INTEGER,
        return_date TEXT,
        total_amount REAL,
        discount_amount REAL,
        gross_amount REAL,
        remarks TEXT,
        created_by INTEGER,
        order_id TEXT,
        invoice_no TEXT,
        created_at TEXT,
        updated_at TEXT,
        received_at TEXT,
        isThirdParty INTEGER,
        price_type TEXT,
        status TEXT,
        isPosted INTEGER DEFAULT 0,
        isApplied INTEGER DEFAULT 0,
        isReceived INTEGER DEFAULT 0
      );
    ''');

    // salesman & reference tables
    await db.execute('''
      CREATE TABLE salesman (
        id INTEGER PRIMARY KEY,
        employee_id INTEGER,
        salesman_code TEXT,
        salesman_name TEXT,
        truck_plate TEXT,
        division_id INTEGER,
        branch_code INTEGER,
        bad_branch_code INTEGER,
        operation INTEGER,
        company_code INTEGER,
        supplier_code INTEGER,
        price_type TEXT,
        isActive INTEGER,
        isInventory INTEGER,
        canCollect INTEGER,
        inventory_day INTEGER,
        modified_date TEXT,
        encoder_id INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE payment_terms (
        id INTEGER PRIMARY KEY,
        payment_name TEXT,
        payment_days INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE operation (
        id INTEGER PRIMARY KEY,
        operation_code TEXT,
        operation_name TEXT,
        date_modified TEXT,
        encoder_id INTEGER,
        company_id INTEGER,
        type INTEGER,
        definition TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE sales_invoice_type (
        id INTEGER PRIMARY KEY,
        type TEXT,
        shortcut TEXT,
        max_length INTEGER
      );
    ''');

    // junction
    await db.execute('''
      CREATE TABLE sales_invoice_sales_return (
        id INTEGER PRIMARY KEY,
        return_no INTEGER,
        invoice_no INTEGER,
        linked_by INTEGER,
        created_at TEXT,
        updated_at TEXT
      );
    ''');

    // ---------------------- itemized dependencies ----------------------
    // FULL products schema (v23)
    await db.execute('''
      CREATE TABLE products (
        product_id INTEGER PRIMARY KEY,
        product_code TEXT,
        barcode TEXT,
        product_name TEXT,
        short_description TEXT,
        description TEXT,
        product_image TEXT,
        product_brand INTEGER,
        product_category INTEGER,
        parent_id INTEGER,
        isActive INTEGER,
        product_class INTEGER,
        product_segment INTEGER,
        product_section INTEGER,
        product_shelf_life TEXT,
        product_weight REAL,
        maintaining_quantity REAL,
        unit_of_measurement INTEGER,
        unit_of_measurement_count INTEGER,
        estimated_unit_cost REAL,
        estimated_extended_cost REAL,
        price_per_unit REAL,
        cost_per_unit REAL,
        priceA REAL,
        priceB REAL,
        priceC REAL,
        priceD REAL,
        priceE REAL,
        product_type TEXT,
        external_id TEXT,
        date_added TEXT,
        last_updated TEXT,
        created_at TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE categories (
        category_id INTEGER PRIMARY KEY,
        category_name TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE brand (
        brand_id INTEGER PRIMARY KEY,
        brand_name TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE units (
        unit_id INTEGER PRIMARY KEY,
        unit_name TEXT,
        unit_shortcut TEXT,
        "order" INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE product_per_supplier (
        id INTEGER PRIMARY KEY,
        supplier_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        discount_type INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE sales_invoice_details (
        detail_id INTEGER PRIMARY KEY,
        order_id TEXT,
        invoice_no INTEGER,
        product_id INTEGER,
        unit INTEGER,
        unit_price REAL,
        quantity REAL,
        total_amount REAL,
        discount_amount REAL,
        gross_amount REAL
      );
    ''');

    await db.execute('''
      CREATE TABLE sales_return_details (
        detail_id INTEGER PRIMARY KEY,
        return_no TEXT,
        product_id INTEGER,
        quantity REAL,
        unit_price REAL,
        total_amount REAL,
        discount_amount REAL,
        gross_amount REAL
      );
    ''');

    // 🆕 Product classification table (for ABC + forecast multiplier)
    await db.execute('''
      CREATE TABLE product_classification (
        product_id INTEGER PRIMARY KEY,
        abc_class TEXT,
        abc_class_forecast TEXT,
        abc_class_sold TEXT,
        forecast_multiplier REAL
      );
    ''');

    // ▶️ Divisions master table (with compat columns ready)
    await _createDivisionsTable(db);

    // ▶️ NEW: Assets & Equipment table + view
    await _createAssetsTables(db);
    await _createAssetsViews(db);

    await _createPpsUniqueIndex(db);

    // Views
    await _createViews(db);
    await _createSalesReportItemizedView(db);
    await _createCompatViews(db); // snake_case flags + division views

    // Helpful indices
    await _createIndices(db);
    await _createSalesReportIndices(db);
    await _createItemizedIndices(db);
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS post_dispatch_budgeting (
          id INTEGER PRIMARY KEY,
          post_dispatch_plan_id INTEGER,
          coa_id INTEGER,
          remarks TEXT,
          amount REAL
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS post_dispatch_plan_staff (
          id INTEGER PRIMARY KEY,
          post_dispatch_plan_id INTEGER,
          user_id INTEGER,
          role TEXT
        );
      ''');
      await db.execute('DROP VIEW IF EXISTS v_delivery_report;');
      await _createDeliveryReportView(db);
    }

    if (oldV < 3) {
      await db.execute('ALTER TABLE sales_invoice ADD COLUMN due_date TEXT;');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sales_invoice_payments (
          id INTEGER PRIMARY KEY,
          invoice_id INTEGER,
          order_id TEXT,
          coa_id INTEGER,
          bank_id INTEGER,
          reference_no TEXT,
          paid_amount REAL,
          date_paid TEXT,
          date_encoded TEXT
        );
      ''');
      await db.execute('DROP VIEW IF EXISTS v_delivery_report;');
      await db.execute('DROP VIEW IF EXISTS view_account_receivable;');
      await _createViews(db);
    }

    if (oldV < 4) {
      await db.execute('ALTER TABLE sales_invoice ADD COLUMN payment_terms INTEGER;');
      await db.execute('DROP VIEW IF EXISTS view_account_receivable;');
      await _createARView(db);
    }

    if (oldV < 5) {
      await db.execute('ALTER TABLE sales_invoice ADD COLUMN is_posted INTEGER DEFAULT 0;');
      await db.execute('DROP VIEW IF EXISTS view_account_receivable;');
      await _createARView(db);
    }

    if (oldV < 6) {
      await _createAPTables(db);
      await db.execute('DROP VIEW IF EXISTS v_ap_register;');
      await db.execute('DROP VIEW IF EXISTS v_disbursement_book;');
      await db.execute('DROP VIEW IF EXISTS v_payment_ledger;');
      await _createAPViews(db);
      await _createIndices(db);
    }

    if (oldV < 7) {
      await db.execute('DROP VIEW IF EXISTS v_ap_register;');
      await db.execute('DROP VIEW IF EXISTS v_disbursement_book;');
      await db.execute('DROP VIEW IF EXISTS v_payment_ledger;');
      await db.execute('DROP VIEW IF EXISTS v_ap_bills;');
      await db.execute('DROP VIEW IF EXISTS v_ap_vendor_summary;');
      await _createAPViews(db);
    }

    if (oldV < 8) {
      await db.execute('DROP VIEW IF EXISTS v_ap_bills;');
      await db.execute('DROP VIEW IF EXISTS v_ap_vendor_summary;');
      await _createAPViews(db);
    }

    if (oldV < 9) {
      await db.execute('DROP VIEW IF EXISTS v_ap_bills;');
      await db.execute('DROP VIEW IF EXISTS v_ap_vendor_summary;');
      await _createAPViews(db);
    }

    if (oldV < 10) {
      await _safeAddColumn(db, 'customer', 'brgy', 'TEXT');
      await _safeAddColumn(db, 'customer', 'province', 'TEXT');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS sales_return (
          return_id INTEGER PRIMARY KEY,
          return_number TEXT,
          customer_code TEXT,
          salesman_id INTEGER,
          branch_id INTEGER,
          return_date TEXT,
          total_amount REAL,
          discount_amount REAL,
          gross_amount REAL,
          remarks TEXT,
          created_by INTEGER,
          order_id TEXT,
          invoice_no TEXT,
          created_at TEXT,
          updated_at TEXT,
          received_at TEXT,
          isThirdParty INTEGER,
          price_type TEXT,
          status TEXT,
          isPosted INTEGER DEFAULT 0,
          isApplied INTEGER DEFAULT 0,
          isReceived INTEGER DEFAULT 0
        );
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS salesman (
          id INTEGER PRIMARY KEY,
          employee_id INTEGER,
          salesman_code TEXT,
          salesman_name TEXT,
          truck_plate TEXT,
          division_id INTEGER,
          branch_code INTEGER,
          bad_branch_code INTEGER,
          operation INTEGER,
          company_code INTEGER,
          supplier_code INTEGER,
          price_type TEXT,
          isActive INTEGER,
          isInventory INTEGER,
          canCollect INTEGER,
          inventory_day INTEGER,
          modified_date TEXT,
          encoder_id INTEGER
        );
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS payment_terms (
          id INTEGER PRIMARY KEY,
          payment_name TEXT,
          payment_days INTEGER
        );
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS operation (
          id INTEGER PRIMARY KEY,
          operation_code TEXT,
          operation_name TEXT,
          date_modified TEXT,
          encoder_id INTEGER,
          company_id INTEGER,
          type INTEGER,
          definition TEXT
        );
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS sales_invoice_type (
          id INTEGER PRIMARY KEY,
          type TEXT,
          shortcut TEXT,
          max_length INTEGER
        );
      ''');

      await _safeAddColumn(db, 'sales_invoice', 'salesman_id', 'INTEGER');
      await _safeAddColumn(db, 'sales_invoice', 'sales_type', 'INTEGER');
      await _safeAddColumn(db, 'sales_invoice', 'invoice_type', 'INTEGER');
      await _safeAddColumn(db, 'sales_invoice', 'price_type', 'TEXT');
      await _safeAddColumn(db, 'sales_invoice', 'created_by', 'INTEGER');
      await _safeAddColumn(db, 'sales_invoice', 'created_date', 'TEXT');
      await _safeAddColumn(db, 'sales_invoice', 'modified_by', 'INTEGER');
      await _safeAddColumn(db, 'sales_invoice', 'modified_date', 'TEXT');
      await _safeAddColumn(db, 'sales_invoice', 'isReceipt', 'INTEGER DEFAULT 0');
      await _safeAddColumn(db, 'sales_invoice', 'isDispatched', 'INTEGER DEFAULT 0');
      await _safeAddColumn(db, 'sales_invoice', 'isRemitted', 'INTEGER DEFAULT 0');

      await db.execute('DROP VIEW IF EXISTS v_sales_report;');

      await _createSalesReportIndices(db);
    }

    if (oldV < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sales_invoice_sales_return (
          id INTEGER PRIMARY KEY,
          return_no INTEGER,
          invoice_no INTEGER,
          linked_by INTEGER,
          created_at TEXT,
          updated_at TEXT
        );
      ''');

      await db.execute('DROP VIEW IF EXISTS v_sales_report;');

      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);

      await db.execute('CREATE INDEX IF NOT EXISTS idx_sisr_invoice_no ON sales_invoice_sales_return(invoice_no);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sisr_return_no ON sales_invoice_sales_return(return_no);');
    }

    if (oldV < 14) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS products (
          product_id INTEGER PRIMARY KEY,
          product_name TEXT,
          product_brand INTEGER,
          product_category INTEGER
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          category_id INTEGER PRIMARY KEY,
          category_name TEXT
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS brand (
          brand_id INTEGER PRIMARY KEY,
          brand_name TEXT
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS units (
          unit_id INTEGER PRIMARY KEY,
          unit_name TEXT
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_per_supplier (
          id INTEGER PRIMARY KEY,
          supplier_id INTEGER NOT NULL,
          product_id INTEGER NOT NULL,
          discount_type INTEGER
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sales_invoice_details (
          detail_id INTEGER PRIMARY KEY,
          order_id TEXT,
          invoice_no INTEGER,
          product_id INTEGER,
          unit INTEGER,
          unit_price REAL,
          quantity REAL,
          total_amount REAL,
          discount_amount REAL,
          gross_amount REAL
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sales_return_details (
          detail_id INTEGER PRIMARY KEY,
          return_no TEXT,
          product_id INTEGER,
          quantity REAL,
          unit_price REAL,
          total_amount REAL,
          discount_amount REAL,
          gross_amount REAL
        );
      ''');

      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);
      await _createItemizedIndices(db);
    }

    if (oldV < 15) {
      await db.execute('DROP VIEW IF EXISTS v_sales_report;');
      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);
    }

    if (oldV < 16) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS brand (
          brand_id INTEGER PRIMARY KEY,
          brand_name TEXT
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          category_id INTEGER PRIMARY KEY,
          category_name TEXT
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_per_supplier (
          id INTEGER PRIMARY KEY,
          supplier_id INTEGER NOT NULL,
          product_id INTEGER NOT NULL,
          discount_type INTEGER
        );
      ''');

      await _createPpsUniqueIndex(db);
    }

    if (oldV < 17) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS units (
          unit_id INTEGER PRIMARY KEY,
          unit_name TEXT
        );
      ''');
      await _safeAddColumn(db, 'units', 'unit_shortcut', 'TEXT');
      final info = await db.rawQuery('PRAGMA table_info(units);');
      final hasOrder = info.any((r) => (r['name'] as String?) == 'order');
      if (!hasOrder) {
        await db.execute('ALTER TABLE units ADD COLUMN "order" INTEGER;');
      }
    }

    if (oldV < 18) {
      await _safeAddColumn(db, 'products', 'parent_id', 'INTEGER');
      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);
    }

    if (oldV < 19) {
      await db.execute('DROP VIEW IF EXISTS v_sales_report;');
      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);
    }

    if (oldV < 20) {
      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_parent ON products(parent_id);');
    }

    if (oldV < 21) {
      await db.execute('DROP VIEW IF EXISTS v_sales_report;');
      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_parent ON products(parent_id);');
    }

    if (oldV < 22) {
      await db.execute('DROP VIEW IF EXISTS v_ap_register;');
      await db.execute('DROP VIEW IF EXISTS v_disbursement_book;');
      await db.execute('DROP VIEW IF EXISTS v_ap_bills;');
      await db.execute('DROP VIEW IF EXISTS v_ap_vendor_summary;');
      await db.execute('DROP VIEW IF EXISTS v_ap_vendor_coa_summary;');
      await _createAPViews(db);
    }

    if (oldV < 23) {
      await db.execute('CREATE TABLE IF NOT EXISTS _tmp_products AS SELECT * FROM products;');
      await db.execute('DROP TABLE IF EXISTS products;');

      await db.execute('''
        CREATE TABLE products (
          product_id INTEGER PRIMARY KEY,
          product_code TEXT,
          barcode TEXT,
          product_name TEXT,
          short_description TEXT,
          description TEXT,
          product_image TEXT,
          product_brand INTEGER,
          product_category INTEGER,
          parent_id INTEGER,
          isActive INTEGER,
          product_class INTEGER,
          product_segment INTEGER,
          product_section INTEGER,
          product_shelf_life TEXT,
          product_weight REAL,
          maintaining_quantity REAL,
          unit_of_measurement INTEGER,
          unit_of_measurement_count INTEGER,
          estimated_unit_cost REAL,
          estimated_extended_cost REAL,
          price_per_unit REAL,
          cost_per_unit REAL,
          priceA REAL,
          priceB REAL,
          priceC REAL,
          priceD REAL,
          priceE REAL,
          product_type TEXT,
          external_id TEXT,
          date_added TEXT,
          last_updated TEXT,
          created_at TEXT
        );
      ''');

      await db.execute('''
        INSERT OR IGNORE INTO products (product_id, product_name, product_brand, product_category, parent_id)
        SELECT product_id, product_name, product_brand, product_category, parent_id
        FROM _tmp_products;
      ''');

      await db.execute('DROP TABLE IF EXISTS _tmp_products;');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_parent ON products(parent_id);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_code ON products(product_code);');

      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);
    }

    if (oldV < 28) {
      await _createDivisionsTable(db);
      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);
      await _createCompatViews(db);
    }

    if (oldV < 29) {
      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);
      await _createCompatViews(db);
    }

    // 🔁 v30: add compat columns to `divisions`, backfill, and (re)create compat views
    if (oldV < 30) {
      await _safeAddColumn(db, 'divisions', 'id', 'INTEGER');
      await _safeAddColumn(db, 'divisions', 'name', 'TEXT');
      await db.execute('UPDATE divisions SET id = division_id WHERE id IS NULL;');
      await db.execute('UPDATE divisions SET name = division_name WHERE name IS NULL;');
      await _createCompatViews(db);
    }

    // 🔁 v31: ensure product_classification exists for consolidated historical SQL / In Cases
    if (oldV < 31) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_classification (
          product_id INTEGER PRIMARY KEY,
          abc_class TEXT,
          abc_class_forecast TEXT,
          abc_class_sold TEXT,
          forecast_multiplier REAL
        );
      ''');
    }

    // 🔁 v32: NEW Assets & Equipment schema
    if (oldV < 32) {
      await _createAssetsTables(db);
      await _createAssetsViews(db);
    }

    // 🔁 v34: refresh AR view to include sales returns info
    if (oldV < 34) {
      await db.execute('DROP VIEW IF EXISTS view_account_receivable;');
      await _createARView(db);
    }

    // ✅ v35: Fix v_sales_report_itemized join (remove order_id constraint in details join)
    if (oldV < 35) {
      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
      await _createSalesReportItemizedView(db);
      await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized_compat;');
      await _createCompatViews(db);
    }
  }

  /* -------------------------------------------------------------------------- */
  /*                               Views (common)                               */
  /* -------------------------------------------------------------------------- */

  static Future<void> _createViews(Database db) async {
    await _createDeliveryReportView(db);
    await _createARView(db);
    await _createAPViews(db);
  }

  static Future<void> _createDeliveryReportView(Database db) async {
    await db.execute('''
      CREATE VIEW v_delivery_report AS
      SELECT
        pdi.id AS id,
        (u.user_fname || ' ' || COALESCE(NULLIF(u.user_mname,''),'') || ' ' || u.user_lname) AS driver_name,
        pdi.sequence AS Seq,
        c.city AS city_town_name,
        s.supplier_shortcut AS supplier_code,
        pdp.doc_no AS doc_no,
        si.invoice_no AS invoice_no,
        si.invoice_date AS invoice_date,
        c.customer_name AS customer_name,
        b.branch_name AS starting_point,
        (COALESCE(si.total_amount,0) - COALESCE(si.discount_amount,0)) AS total,
        pdp.status AS post_delivery_plan_status,
        pdi.status AS post_dispatch_invoices_status,
        v.vehicle_plate AS vehicle,
        pdp.encoder_id AS encoder_id,
        pdp.estimated_time_of_dispatch AS estimated_time_of_dispatch,
        pdp.estimated_time_of_arrival AS estimated_time_of_arrival,
        pdp.time_of_dispatch AS time_of_dispatch,
        pdp.time_of_arrival AS time_of_arrival,
        pdp.date_encoded AS date_encoded,
        pdp.remarks AS remarks,
        (
          SELECT COALESCE(SUM(COALESCE(pbb.amount,0)),0)
          FROM post_dispatch_budgeting pbb
          WHERE pbb.post_dispatch_plan_id = pdp.id
        ) AS total_budget,
        (
          SELECT GROUP_CONCAT(
                   TRIM((uu.user_fname || ' ' ||
                        COALESCE(NULLIF(uu.user_mname,''),'') || ' ' ||
                        uu.user_lname)), ', '
                 )
          FROM post_dispatch_plan_staff ps
          JOIN user uu ON uu.user_id = ps.user_id
          WHERE ps.role = 'Helper'
            AND ps.post_dispatch_plan_id = pdp.id
        ) AS helper_name
      FROM post_dispatch_invoices pdi
      LEFT JOIN post_dispatch_plan pdp ON pdp.id = pdi.post_dispatch_plan_id
      LEFT JOIN sales_invoice si ON si.invoice_id = pdi.invoice_id
      LEFT JOIN user u ON u.user_id = pdp.driver_id
      LEFT JOIN branches b ON b.id = pdp.starting_point
      LEFT JOIN vehicles v ON v.vehicle_id = pdp.vehicle_id
      LEFT JOIN sales_order so ON (TRIM(so.order_no) = TRIM(si.order_id) OR so.order_id = CAST(si.order_id AS INTEGER))
      LEFT JOIN customer c ON c.customer_code = COALESCE(si.customer_code, so.customer_code)
      LEFT JOIN suppliers s ON s.id = so.supplier_id
      ORDER BY pdp.date_encoded DESC, pdi.sequence, si.invoice_id;
    ''');
  }

  static Future<void> _createARView(Database db) async {
    await db.execute('''
      CREATE VIEW view_account_receivable AS
      WITH sr_agg AS (
        SELECT
          TRIM(order_id) AS order_id,
          TRIM(invoice_no) AS invoice_no,
          SUM(COALESCE(total_amount,0)) AS return_total_amount,
          SUM(COALESCE(discount_amount,0)) AS return_discount_total
        FROM sales_return
        GROUP BY TRIM(order_id), TRIM(invoice_no)
      ),
      ar AS (
        SELECT
          si.invoice_id,
          si.invoice_no                           AS invoice_number,
          si.order_id,
          si.customer_code,
          c.customer_name,

          -- 🆕 Salesman info
          s.salesman_name                         AS salesman_name,
          s.salesman_code                         AS salesman_code,

          COALESCE(si.total_amount, 0)            AS total_amount,
          COALESCE(si.discount_amount, 0)         AS discount_amount,

          /* 🆕 Sales return aggregates at invoice level */
          COALESCE(sr.return_total_amount, 0)     AS return_total_amount,
          COALESCE(sr.return_discount_total, 0)   AS return_discount_total,
          (COALESCE(sr.return_total_amount,0) - COALESCE(sr.return_discount_total,0))
                                                 AS return_net_amount,

          /* Original net (for backward compat) */
          (COALESCE(si.total_amount, 0) - COALESCE(si.discount_amount, 0))
                                                 AS net_amount,

          COALESCE(p.paid_amount, 0)              AS paid_amount,

          /* Original balance (using original net_amount) */
          MAX(
            (COALESCE(si.total_amount, 0) - COALESCE(si.discount_amount, 0))
            - COALESCE(p.paid_amount, 0),
            0
          )                                      AS balance,

          /* 🆕 Net after returns & balance after returns */
          (
            (COALESCE(si.total_amount, 0) - COALESCE(si.discount_amount, 0))
            - (COALESCE(sr.return_total_amount,0) - COALESCE(sr.return_discount_total,0))
          )                                      AS net_after_returns,

          MAX(
            (
              (COALESCE(si.total_amount, 0) - COALESCE(si.discount_amount, 0))
              - (COALESCE(sr.return_total_amount,0) - COALESCE(sr.return_discount_total,0))
            )
            - COALESCE(p.paid_amount, 0),
            0
          )                                      AS balance_after_returns,

          COALESCE(
            NULLIF(si.due_date,''),
            CASE
              WHEN si.invoice_date IS NOT NULL AND si.payment_terms IS NOT NULL
              THEN date(substr(si.invoice_date,1,10), printf('+%d days', si.payment_terms))
            END
          )                                      AS due_date,
          si.is_posted                           AS is_posted
        FROM sales_invoice AS si
        LEFT JOIN (
          SELECT invoice_id, SUM(COALESCE(paid_amount,0)) AS paid_amount
          FROM sales_invoice_payments
          GROUP BY invoice_id
        ) AS p
          ON p.invoice_id = si.invoice_id
        LEFT JOIN customer AS c
          ON c.customer_code = si.customer_code
        LEFT JOIN sr_agg AS sr
          ON TRIM(sr.order_id) = TRIM(si.order_id)
         AND TRIM(sr.invoice_no) = TRIM(si.invoice_no)
        LEFT JOIN salesman AS s
          ON s.id = si.salesman_id   -- assumes sales_invoice.salesman_id = salesman.id
      )
      SELECT
        invoice_id,
        invoice_number,
        order_id,
        customer_code,
        customer_name,

        -- 🆕 salesman fields exposed in the view
        salesman_name,
        salesman_code,

        total_amount,
        discount_amount,
        /* original net */
        net_amount,
        /* 🆕 returns + net-after-returns */
        return_total_amount,
        return_discount_total,
        return_net_amount,
        net_after_returns,
        paid_amount,
        balance,
        balance_after_returns,
        due_date,
        date(due_date) AS due_date_date,
        is_posted
      FROM ar;
    ''');
  }

  /* -------------------------------------------------------------------------- */
  /*                         AP / Disbursement views                             */
  /* -------------------------------------------------------------------------- */

  static Future<void> _createAPViews(Database db) async {
    // v_ap_register
    await db.execute('''
      CREATE VIEW IF NOT EXISTS v_ap_register AS
      SELECT
        dp.id                            AS line_id,
        d.id                             AS disbursement_id,
        d.doc_no                         AS doc_no,
        date(d.transaction_date)         AS transaction_date,
        d.division_id                    AS division_id,
        d.encoder_id                     AS encoder_id,
        d.payee                          AS payee_id,
        s.supplier_name                  AS payee_name,
        dp.coa_id                        AS coa_id,
        coa.account_title                AS coa_title,
        coa.gl_code                      AS gl_code,
        dp.reference_no                  AS reference_no,
        dp.remarks                       AS line_remarks,
        dp.amount                        AS line_amount,
        dp.date                          AS line_date,
        d.total_amount                   AS header_total_amount,
        d.paid_amount                    AS header_paid_amount,
        COALESCE(d.isPosted,0)           AS is_posted
      FROM disbursement_payables dp
      JOIN disbursement d       ON d.id = dp.disbursement_id
      LEFT JOIN suppliers s     ON s.id = d.payee
      LEFT JOIN chart_of_accounts coa ON coa.coa_id = dp.coa_id
      ORDER BY d.transaction_date DESC, d.id, dp.id;
    ''');

    // v_disbursement_book
    await db.execute('''
      CREATE VIEW IF NOT EXISTS v_disbursement_book AS
      WITH pay AS (
        SELECT disbursement_id, SUM(COALESCE(amount,0)) AS paid_now
        FROM disbursement_payments
        GROUP BY disbursement_id
      )
      SELECT
        d.id                               AS disbursement_id,
        d.doc_no                           AS doc_no,
        date(d.transaction_date)           AS transaction_date,
        d.payee                            AS payee_id,
        s.supplier_name                    AS payee_name,
        d.total_amount                     AS total_amount,
        COALESCE(p.paid_now, 0)            AS paid_amount,
        MAX(d.total_amount - COALESCE(p.paid_now,0), 0) AS balance,
        COALESCE(d.isPosted,0)             AS is_posted,
        d.transaction_type                 AS transaction_type,
        d.division_id                      AS division_id,
        d.encoder_id                       AS encoder_id,
        d.remarks                          AS remarks,
        d.date_created                     AS date_created,
        d.date_updated                     AS date_updated,
        d.date_posted                      AS date_posted,
        d.date_approved                    AS date_approved,
        d.approver_id                      AS approver_id,
        d.posted_by                        AS posted_by
      FROM disbursement d
      LEFT JOIN pay p ON p.disbursement_id = d.id
      LEFT JOIN suppliers s ON s.id = d.payee
      ORDER BY d.transaction_date DESC, d.id DESC;
    ''');

    // v_ap_bills
    await db.execute('''
      CREATE VIEW IF NOT EXISTS v_ap_bills AS
      WITH lines AS (
        SELECT
          d.id                             AS disbursement_id,
          d.doc_no                         AS doc_no,
          d.payee                          AS payee_id,
          s.supplier_name                  AS payee_name,
          date(d.transaction_date)         AS transaction_date,
          date(COALESCE(NULLIF(MIN(NULLIF(dp.date, '')), ''), d.transaction_date)) AS due_date,
          SUM(COALESCE(dp.amount,0))       AS line_total,
          COALESCE(d.isPosted,0)           AS is_posted,
          MAX(COALESCE(d.date_updated, d.date_created)) AS last_update,
          (
            SELECT dp2.coa_id
            FROM disbursement_payables dp2
            WHERE dp2.disbursement_id = d.id
            ORDER BY COALESCE(dp2.amount,0) DESC, dp2.id ASC
            LIMIT 1
          )                                 AS primary_coa_id,
          (
            SELECT REPLACE(GROUP_CONCAT(coa_text), ',', ' | ')
            FROM (
              SELECT DISTINCT
                TRIM(COALESCE(coa.gl_code || ' - ', '') || COALESCE(coa.account_title,'')) AS coa_text
              FROM disbursement_payables dpx
              LEFT JOIN chart_of_accounts coa ON coa.coa_id = dpx.coa_id
              WHERE dpx.disbursement_id = d.id
            )
          )                                  AS coa_list,
          d.remarks                          AS header_remarks,
          GROUP_CONCAT(TRIM(NULLIF(dp.remarks,'')), ' | ') AS line_remarks
        FROM disbursement d
        LEFT JOIN disbursement_payables dp ON dp.disbursement_id = d.id
        LEFT JOIN suppliers s              ON s.id = d.payee
        GROUP BY d.id
      ),
      pay AS (
        SELECT disbursement_id, SUM(COALESCE(amount,0)) AS paid_now
        FROM disbursement_payments
        GROUP BY disbursement_id
      )
      SELECT
        l.disbursement_id,
        l.doc_no,
        l.payee_id,
        l.payee_name,
        l.transaction_date,
        l.due_date,
        l.line_total                          AS total_amount,
        COALESCE(p.paid_now,0)                AS paid_amount,
        MAX(l.line_total - COALESCE(p.paid_now,0), 0) AS balance,
        l.is_posted,
        l.last_update,
        l.header_remarks                      AS remarks,
        l.header_remarks,
        l.line_remarks,
        l.primary_coa_id,
        coa.gl_code                           AS primary_coa_gl,
        coa.account_title                     AS primary_coa_title,
        l.coa_list
      FROM lines l
      LEFT JOIN pay p ON p.disbursement_id = l.disbursement_id
      LEFT JOIN chart_of_accounts coa ON coa.coa_id = l.primary_coa_id
      WHERE l.line_total IS NOT NULL;
    ''');

    // v_ap_vendor_summary
    await db.execute('''
      CREATE VIEW IF NOT EXISTS v_ap_vendor_summary AS
      WITH bills AS ( SELECT * FROM v_ap_bills )
      SELECT
        g.payee_id,
        g.payee_name,
        SUM(g.balance)                               AS total_balance,
        MIN(g.due_date)                              AS next_due_date,
        CASE
          WHEN SUM(g.balance) <= 0 THEN 'Settled'
          WHEN MIN(g.due_date) IS NULL THEN 'Not Due'
          WHEN MIN(g.due_date) <  date('now') THEN 'Overdue'
          WHEN MIN(g.due_date) <= date('now','+7 day') THEN 'Due Soon'
          ELSE 'Not Due'
        END                                          AS status,
        (
          SELECT
            COALESCE(
              NULLIF(TRIM(b2.header_remarks), ''),
              NULLIF(TRIM(b2.line_remarks), '')
            )
          FROM v_ap_bills b2
          WHERE b2.payee_id = g.payee_id
          ORDER BY COALESCE(b2.due_date, b2.transaction_date) ASC
          LIMIT 1
        )                                            AS remarks
      FROM bills g
      GROUP BY g.payee_id, g.payee_name
      HAVING SUM(g.balance) IS NOT NULL;
    ''');

    // v_ap_vendor_coa_summary
    await db.execute('''
      CREATE VIEW IF NOT EXISTS v_ap_vendor_coa_summary AS
      WITH reg AS (
        SELECT
          d.payee            AS payee_id,
          s.supplier_name    AS payee_name,
          dp.coa_id          AS coa_id,
          coa.gl_code        AS gl_code,
          coa.account_title  AS account_title,
          SUM(COALESCE(dp.amount,0)) AS total_line_amount
        FROM disbursement_payables dp
        JOIN disbursement d        ON d.id = dp.disbursement_id
        LEFT JOIN suppliers s      ON s.id = d.payee
        LEFT JOIN chart_of_accounts coa ON coa.coa_id = dp.coa_id
        GROUP BY d.payee, s.supplier_name, dp.coa_id, coa.gl_code, coa.account_title
      )
      SELECT
        payee_id,
        payee_name,
        coa_id,
        gl_code,
        account_title,
        total_line_amount
      FROM reg
      ORDER BY payee_name, gl_code, account_title;
    ''');
  }

  /* -------------------------------------------------------------------------- */
  /*   v_sales_report_itemized (division name + camelCase & snake_case flags)   */
  /* -------------------------------------------------------------------------- */
  static Future<void> _createSalesReportItemizedView(Database db) async {
    await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized;');
    await db.execute('''
  CREATE VIEW v_sales_report_itemized AS
  WITH RECURSIVE root_map AS (
    SELECT p.product_id, p.parent_id, p.product_id AS root_id
    FROM products p
    WHERE p.parent_id IS NULL
    UNION ALL
    SELECT c.product_id, c.parent_id, r.root_id
    FROM products c
    JOIN root_map r ON c.parent_id = r.product_id
  ),

  /* Pick the BOX candidate per family (same principle as consolidatedSQL_FAMILY_AGG_RANGE_PIECES) */
  box_rank AS (
    SELECT
      rm.root_id,
      p.product_id,
      COALESCE(p.unit_of_measurement_count, 1) AS umc,
      u.`order`                                 AS unit_order,
      ROW_NUMBER() OVER (
        PARTITION BY rm.root_id
        ORDER BY
          (CASE WHEN u.`order` IS NULL THEN 0 ELSE 1 END) DESC,
          u.`order` DESC,
          COALESCE(p.unit_of_measurement_count, 1) DESC,
          p.product_id ASC
      ) AS rn
    FROM root_map rm
    JOIN products p
      ON p.product_id = rm.product_id
     AND p.isActive = 1
    LEFT JOIN units u
      ON u.unit_id = p.unit_of_measurement
  ),

  box_pick AS (
    SELECT
      br.root_id,
      br.product_id AS box_product_id,
      br.umc        AS pieces_per_box
    FROM box_rank br
    WHERE br.rn = 1
  )

  SELECT
    si.invoice_id AS invoice_id,
    si.order_id   AS order_id,
    c.customer_name AS customer_name,
    CASE
      WHEN NULLIF(TRIM(c.city),'') IS NOT NULL AND NULLIF(TRIM(c.province),'') IS NOT NULL THEN TRIM(c.city) || ', ' || TRIM(c.province)
      WHEN NULLIF(TRIM(c.city),'') IS NOT NULL THEN TRIM(c.city)
      WHEN NULLIF(TRIM(c.province),'') IS NOT NULL THEN TRIM(c.province)
      ELSE ''
    END AS customer_address,
    c.city AS customer_city,
    c.province AS customer_province,
    si.invoice_no AS invoice_no,
    (CAST(s.id AS TEXT) || ' - ' || COALESCE(s.salesman_name,'')) AS salesman,

    /* Division NAME with fallback if divisions table has no data */
    COALESCE(
      d.division_name,
      CASE s.division_id
        WHEN 1 THEN 'Industrial'
        WHEN 2 THEN 'Dry Goods'
        WHEN 3 THEN 'Frozen Goods'
        WHEN 4 THEN 'Mama Pina''s'
        ELSE 'N/A'
      END
    ) AS salesman_division,

    b.branch_name AS branch,
    si.invoice_date AS invoice_date,
    si.dispatch_date AS dispatch_date,
    si.due_date AS due_date,
    pt.payment_name AS payment_terms,
    si.transaction_status AS transaction_status,
    si.payment_status AS payment_status,
    si.total_amount AS total_amount,
    si.discount_amount AS discount_amount,
    (IFNULL(si.total_amount,0) - IFNULL(si.discount_amount,0)) AS amount,

    /* === INVOICE-LEVEL RETURNS === */
    IFNULL((
      SELECT SUM(IFNULL(sr.total_amount,0))
      FROM sales_return sr
      WHERE TRIM(sr.order_id)=TRIM(si.order_id)
        AND TRIM(sr.invoice_no)=TRIM(si.invoice_no)
    ),0) AS return_amount_total,

    IFNULL((
      SELECT SUM(IFNULL(sr.discount_amount,0))
      FROM sales_return sr
      WHERE TRIM(sr.order_id)=TRIM(si.order_id)
        AND TRIM(sr.invoice_no)=TRIM(si.invoice_no)
    ),0) AS return_discount_total,

    /* Net return */
    (
      IFNULL((
        SELECT SUM(IFNULL(sr.total_amount,0))
        FROM sales_return sr
        WHERE TRIM(sr.order_id)=TRIM(si.order_id)
          AND TRIM(sr.invoice_no)=TRIM(si.invoice_no)
      ),0)
      - IFNULL((
        SELECT SUM(IFNULL(sr.discount_amount,0))
        FROM sales_return sr
        WHERE TRIM(sr.order_id)=TRIM(si.order_id)
          AND TRIM(sr.invoice_no)=TRIM(si.invoice_no)
      ),0)
    ) AS return_amount,

    /* Collection = Net Sales − Net Returns */
    (
      (IFNULL(si.total_amount,0) - IFNULL(si.discount_amount,0))
      - (
        IFNULL((
          SELECT SUM(IFNULL(sr.total_amount,0))
          FROM sales_return sr
          WHERE TRIM(sr.order_id)=TRIM(si.order_id)
            AND TRIM(sr.invoice_no)=TRIM(si.invoice_no)
        ),0)
        - IFNULL((
          SELECT SUM(IFNULL(sr.discount_amount,0))
          FROM sales_return sr
          WHERE TRIM(sr.order_id)=TRIM(si.order_id)
            AND TRIM(sr.invoice_no)=TRIM(si.invoice_no)
        ),0)
      )
    ) AS collection,

    o.operation_name AS sales_type,
    sit.type AS invoice_type,
    si.price_type AS price_type,
    (u1.user_fname || ' ' || u1.user_lname) AS created_by,
    si.created_date AS created_date,
    (u2.user_fname || ' ' || u2.user_lname) AS modified_by,
    si.modified_date AS modified_date,

    /* Flags: provide camelCase AND snake_case aliases */
    IFNULL(si.isReceipt,0)      AS isReceipt,
    IFNULL(si.is_posted,0)      AS isPosted,
    IFNULL(si.is_posted,0)      AS is_posted,
    IFNULL(si.isDispatched,0)   AS isDispatched,
    IFNULL(si.isDispatched,0)   AS is_dispatched,
    IFNULL(si.isRemitted,0)     AS isRemitted,

    p.product_name AS product_name,
    cat.category_name AS product_category,
    br.brand_name AS product_brand,
    (
      SELECT s2.supplier_name
      FROM product_per_supplier pps2
      JOIN suppliers s2 ON s2.id = pps2.supplier_id
      WHERE pps2.product_id = IFNULL(p.parent_id, p.product_id)
      LIMIT 1
    ) AS product_supplier,
    sid.unit_price AS product_unit_price,
    sid.quantity AS product_quantity,

    /* ✅ IN CASES: only when there is a real BOX (pieces_per_box > 1) */
    CASE
      WHEN bp.pieces_per_box IS NOT NULL
           AND bp.pieces_per_box > 1
        THEN (sid.quantity * COALESCE(p.unit_of_measurement_count, 1)) * 1.0
             / bp.pieces_per_box
      ELSE 0
      -- if you prefer blank instead of 0, use: ELSE NULL
    END AS in_cases,

    u.unit_name AS product_unit,
    sid.total_amount AS product_total_amount,
    sid.discount_amount AS product_discount_amount,
    (IFNULL(sid.total_amount,0) - IFNULL(sid.discount_amount,0)) AS product_net_amount,

    IFNULL((
      SELECT SUM(IFNULL(srd.quantity,0))
      FROM sales_return_details srd
      JOIN sales_return sr2 ON sr2.return_number = srd.return_no
      WHERE TRIM(sr2.order_id)=TRIM(si.order_id)
        AND TRIM(sr2.invoice_no)=TRIM(si.invoice_no)
        AND srd.product_id=sid.product_id
    ),0) AS return_quantity,

    IFNULL((
      SELECT SUM(IFNULL(srd.total_amount,0))
      FROM sales_return_details srd
      JOIN sales_return sr2 ON sr2.return_number = srd.return_no
      WHERE TRIM(sr2.order_id)=TRIM(si.order_id)
        AND TRIM(sr2.invoice_no)=TRIM(si.invoice_no)
        AND srd.product_id=sid.product_id
    ),0) AS return_total_amount,

    IFNULL((
      SELECT SUM(IFNULL(srd.discount_amount,0))
      FROM sales_return_details srd
      JOIN sales_return sr2 ON sr2.return_number = srd.return_no
      WHERE TRIM(sr2.order_id)=TRIM(si.order_id)
        AND TRIM(sr2.invoice_no)=TRIM(si.invoice_no)
        AND srd.product_id=sid.product_id
    ),0) AS return_discount_amount,

    (
      (IFNULL(sid.total_amount,0) - IFNULL(sid.discount_amount,0))
      - (
        IFNULL((
          SELECT SUM(IFNULL(srd.total_amount,0))
          FROM sales_return_details srd
          JOIN sales_return sr2 ON sr2.return_number = srd.return_no
          WHERE TRIM(sr2.order_id)=TRIM(si.order_id)
            AND TRIM(sr2.invoice_no)=TRIM(si.invoice_no)
            AND srd.product_id=sid.product_id
        ),0)
        - IFNULL((
          SELECT SUM(IFNULL(srd.discount_amount,0))
          FROM sales_return_details srd
          JOIN sales_return sr2 ON sr2.return_number = srd.return_no
          WHERE TRIM(sr2.order_id)=TRIM(si.order_id)
            AND TRIM(sr2.invoice_no)=TRIM(si.invoice_no)
            AND srd.product_id=sid.product_id
        ),0)
      )
    ) AS product_sales_amount

  FROM sales_invoice si
  LEFT JOIN customer c   ON c.customer_code=si.customer_code
  LEFT JOIN salesman s   ON s.id=si.salesman_id
  LEFT JOIN divisions d  ON d.division_id = s.division_id
  LEFT JOIN branches b   ON b.id=si.branch_id
  LEFT JOIN payment_terms pt ON pt.id=si.payment_terms
  LEFT JOIN operation o  ON o.id=si.sales_type
  LEFT JOIN sales_invoice_type sit ON sit.id=si.invoice_type
  LEFT JOIN user u1      ON u1.user_id=si.created_by
  LEFT JOIN user u2      ON u2.user_id=si.modified_by

  /* ✅ FIX: DO NOT require sid.order_id = si.order_id.
     Details reliably link to header via sid.invoice_no = si.invoice_id. */
  JOIN sales_invoice_details sid
    ON sid.invoice_no = si.invoice_id

  LEFT JOIN products p   ON p.product_id=sid.product_id
  LEFT JOIN root_map rm2 ON rm2.product_id = p.product_id
  LEFT JOIN box_pick bp  ON bp.root_id    = rm2.root_id
  LEFT JOIN categories cat ON cat.category_id=p.product_category
  LEFT JOIN brand br     ON br.brand_id=p.product_brand
  LEFT JOIN units u      ON u.unit_id=sid.unit;
  ''');
  }

  /* -------------------------------------------------------------------------- */
  /*                 Legacy compat (flags + division lookups)                   */
  /* -------------------------------------------------------------------------- */

  static Future<void> _createCompatViews(Database db) async {
    // Legacy flags
    await db.execute('DROP VIEW IF EXISTS v_sales_report_itemized_compat;');
    await db.execute('''
      CREATE VIEW v_sales_report_itemized_compat AS
      SELECT
        t.*,
        t.isPosted     AS is_posted,
        t.isDispatched AS is_dispatched
      FROM v_sales_report_itemized t;
    ''');

    // 🔁 Division lookup compat:
    // some code expects `division` table
    await db.execute('DROP VIEW IF EXISTS division;');
    await db.execute('''
      CREATE VIEW division AS
      SELECT
        division_id,
        division_name,
        division_description,
        division_head,
        division_code,
        date_added,
        division_id AS id,     -- alias
        division_name AS name  -- alias
      FROM divisions;
    ''');

    // some code expects `salesman_division`
    await db.execute('DROP VIEW IF EXISTS salesman_division;');
    await db.execute('''
      CREATE VIEW salesman_division AS
      SELECT
        division_id,
        division_name,
        division_description,
        division_head,
        division_code,
        date_added,
        division_id AS id,     -- alias
        division_name AS name  -- alias
      FROM divisions;
    ''');
  }

  /* -------------------------------------------------------------------------- */
  /*                                  Indices                                   */
  /* -------------------------------------------------------------------------- */

  static Future<void> _createIndices(Database db) async {
    // Sales / AR side
    await db.execute('CREATE INDEX IF NOT EXISTS idx_si_invoice_date ON sales_invoice(invoice_date);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sip_invoice_id ON sales_invoice_payments(invoice_id);');

    // AP / Disbursement side
    await db.execute('CREATE INDEX IF NOT EXISTS idx_d_trx_date ON disbursement(transaction_date);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_d_payee ON disbursement(payee);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dp_did ON disbursement_payables(disbursement_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dp_coa ON disbursement_payables(coa_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dpmts_did ON disbursement_payments(disbursement_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dpmts_date ON disbursement_payments(date);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_coa_title ON chart_of_accounts(account_title);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_bank_name ON bank_accounts(bank_name);');

    // Junction / itemized
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sisr_invoice_no ON sales_invoice_sales_return(invoice_no);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sisr_return_no ON sales_invoice_sales_return(return_no);');

    // Products parent for supplier fallback
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_parent ON products(parent_id);');

    // Divisions / salesman mapping
    await db.execute('CREATE INDEX IF NOT EXISTS idx_divisions_name ON divisions(division_name);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_salesman_division ON salesman(division_id);');

    // 🆕 Assets & Equipment filters (table name now matches sync)
    await db.execute('CREATE INDEX IF NOT EXISTS idx_assets_department ON assets_and_equipment(department);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_assets_condition  ON assets_and_equipment(condition);');
  }

  static Future<void> _createSalesReportIndices(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sr_order_invoice ON sales_return(order_id, invoice_no);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_si_order_invoice ON sales_invoice(order_id, invoice_no);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_si_salesman ON sales_invoice(salesman_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_si_branch ON sales_invoice(branch_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_si_dates ON sales_invoice(invoice_date, dispatch_date, due_date);');
  }

  static Future<void> _createItemizedIndices(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sid_order_invoice ON sales_invoice_details(order_id, invoice_no);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sid_product ON sales_invoice_details(product_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_srd_return_no ON sales_return_details(return_no);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_srd_product ON sales_return_details(product_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pps_product ON product_per_supplier(product_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_brand ON products(product_brand);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_category ON products(product_category);');
  }

  /* -------------------------------------------------------------------------- */
  /*                                Helpers                                     */
  /* -------------------------------------------------------------------------- */

  static Future<void> _safeAddColumn(Database db, String table, String col, String type) async {
    final res = await db.rawQuery("PRAGMA table_info($table);");
    final exists = res.any((r) => (r['name'] as String?) == col);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $col $type;');
    }
  }

  static Future<void> _createPpsUniqueIndex(Database db) async {
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS ux_pps_supplier_product ON product_per_supplier(supplier_id, product_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pps_supplier ON product_per_supplier(supplier_id);');
  }

  // ▶️ Divisions table (now includes compat columns)
  static Future<void> _createDivisionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS divisions (
        division_id INTEGER PRIMARY KEY,
        division_name TEXT,
        division_description TEXT,
        division_head TEXT,
        division_code TEXT,
        date_added TEXT,
        /* compat columns for legacy queries */
        id INTEGER,
        name TEXT
      );
    ''');
    // Backfill compat columns on fresh create
    await db.execute('UPDATE divisions SET id = division_id WHERE id IS NULL;');
    await db.execute('UPDATE divisions SET name = division_name WHERE name IS NULL;');
  }

  /* -------------------------------------------------------------------------- */
  /*   NEW: helper for consolidated historical SQL (in cases)                   */
  /* -------------------------------------------------------------------------- */

  /// Build SQL equivalent of consolidatedHistoricalSQL_FAMILY_AGG_RANGE_PIECES
  /// from the Java backend. This returns one row per supplier x product family,
  /// with `forecast_sum` already in *cases* (pcs / pieces_per_box).
  ///
  /// Parameters:
  /// - filterSupplier: when true, adds `WHERE fb.supplier_id = ?`
  /// - branchIds: optional list of branch IDs for inventory & history filters
  static String buildConsolidatedHistoricalSqlFamilyAggRangePieces({
    required bool filterSupplier,
    List<int>? branchIds,
  }) {
    String branchFilterInIvJoin;
    String histBranchFilter;

    if (branchIds != null && branchIds.isNotEmpty) {
      final inList = branchIds.join(',');
      branchFilterInIvJoin = '''
            LEFT JOIN v_running_inventory inv
              ON inv.product_id = p2.product_id
             AND inv.branch_id IN ($inList)
''';
      histBranchFilter = '''
      AND si.branch_id IN ($inList)
''';
    } else {
      branchFilterInIvJoin = '''
            LEFT JOIN v_running_inventory inv
              ON inv.product_id = p2.product_id
''';
      histBranchFilter = '';
    }

    final supplierWhere = filterSupplier ? 'WHERE fb.supplier_id = ?\n' : '';

    return '''
WITH RECURSIVE root_map AS (
    SELECT p.product_id, p.parent_id, p.product_id AS root_id
    FROM products p
    WHERE p.parent_id IS NULL
    UNION ALL
    SELECT c.product_id, c.parent_id, r.root_id
    FROM products c
    JOIN root_map r ON c.parent_id = r.product_id
),

/* Pick the BOX candidate per family (same logic as forecast mode) */
box_rank AS (
    SELECT
        rm.root_id,
        p.product_id,
        u."order"                                   AS unit_order,
        COALESCE(p.unit_of_measurement_count, 1)    AS umc,
        ROW_NUMBER() OVER (
            PARTITION BY rm.root_id
            ORDER BY
                (CASE WHEN u."order" IS NULL THEN 0 ELSE 1 END) DESC,
                u."order" DESC,
                COALESCE(p.unit_of_measurement_count, 1) DESC,
                p.product_id ASC
        ) AS rn
    FROM root_map rm
    JOIN products p           ON p.product_id = rm.product_id AND p.isActive = 1
    LEFT JOIN units u         ON u.unit_id = p.unit_of_measurement
),
box_pick AS (
    SELECT
        br.root_id,
        br.product_id      AS box_product_id,
        br.umc             AS pieces_per_box
    FROM box_rank br
    WHERE br.rn = 1
),

/* Family base (one row per supplier x root_id) */
fb AS (
    SELECT
        pps.supplier_id                         AS supplier_id,
        rm.root_id                              AS root_id,
        bp.box_product_id                       AS box_product_id,
        COALESCE(bp.pieces_per_box, 1)          AS pieces_per_box,

        MAX(COALESCE(p_box.product_name, p_root.product_name))          AS product_name,
        MAX(COALESCE(b_box.brand_name,  b_root.brand_name))             AS brand_name,
        MAX(COALESCE(c_box.category_name, c_root.category_name))        AS category_name,
        MAX(COALESCE(u_box.unit_name,    u_root.unit_name))             AS unit_name,

        COALESCE(MAX(p_box.cost_per_unit), MAX(p_root.cost_per_unit), 0) AS last_cost,

        COALESCE(
            MAX(pclr.abc_class_forecast), MAX(pcl.abc_class_forecast),
            MAX(pclr.abc_class),         MAX(pcl.abc_class),
            'B'
        ) AS abc_class
    FROM product_per_supplier pps
    JOIN products p_map        ON p_map.product_id = pps.product_id AND p_map.isActive = 1
    JOIN root_map rm           ON rm.product_id    = p_map.product_id
    LEFT JOIN products p_root  ON p_root.product_id = rm.root_id
    LEFT JOIN brand   b_root   ON b_root.brand_id   = p_root.product_brand
    LEFT JOIN categories c_root ON c_root.category_id = p_root.product_category
    LEFT JOIN units   u_root   ON u_root.unit_id    = p_root.unit_of_measurement
    LEFT JOIN product_classification pcl  ON pcl.product_id  = p_map.product_id
    LEFT JOIN product_classification pclr ON pclr.product_id = p_root.product_id

    LEFT JOIN box_pick bp         ON bp.root_id         = rm.root_id
    LEFT JOIN products p_box      ON p_box.product_id   = bp.box_product_id
    LEFT JOIN brand   b_box       ON b_box.brand_id     = p_box.product_brand
    LEFT JOIN categories c_box    ON c_box.category_id  = p_box.product_category
    LEFT JOIN units   u_box       ON u_box.unit_id      = p_box.unit_of_measurement

    GROUP BY pps.supplier_id, rm.root_id, bp.box_product_id, bp.pieces_per_box
),

/* Historical demand in PCS across family (from dispatched invoices) */
hist AS (
    SELECT
        pps.supplier_id        AS supplier_id,
        rm2.root_id            AS root_id,
        SUM(
            sid.quantity * COALESCE(p.unit_of_measurement_count, 1)
        ) AS demand_pcs
    FROM sales_invoice_details sid
    JOIN sales_invoice si
      ON si.invoice_id = sid.invoice_no
     AND si.dispatch_date >= ?
     AND si.dispatch_date <  ?
$histBranchFilter
    JOIN products p
      ON p.product_id = sid.product_id
     AND p.isActive = 1
    JOIN root_map rm2
      ON rm2.product_id = p.product_id
    JOIN product_per_supplier pps
      ON pps.product_id = p.product_id
    GROUP BY
        pps.supplier_id,
        rm2.root_id
),

/* Inventory in PCS across family (branch-specific; as-of now) */
iv AS (
    SELECT
        rm3.root_id                        AS root_id,
        SUM(COALESCE(inv.running_inventory, 0)) AS stock_pcs
    FROM products p2
    JOIN root_map rm3 ON rm3.product_id = p2.product_id
$branchFilterInIvJoin
    GROUP BY rm3.root_id
)

SELECT
    fb.supplier_id                                           AS supplier_id,
    fb.root_id                                               AS key_product_id,
    fb.box_product_id                                        AS parent_id,
    fb.product_name                                          AS product_name,
    fb.brand_name                                            AS brand_name,
    fb.category_name                                         AS category_name,
    fb.unit_name                                             AS unit_name,
    fb.last_cost                                             AS last_cost,

    /* ✅ Only convert to CASES when pieces_per_box > 1 (real box exists) */
    CASE
        WHEN fb.pieces_per_box IS NOT NULL AND fb.pieces_per_box > 1
            THEN COALESCE(iv.stock_pcs, 0) * 1.0 / fb.pieces_per_box
        ELSE 0
    END AS current_stock,

    CASE
        WHEN fb.pieces_per_box IS NOT NULL AND fb.pieces_per_box > 1
            THEN COALESCE(hist.demand_pcs, 0) * 1.0 / fb.pieces_per_box
        ELSE 0
    END AS forecast_sum,

    fb.abc_class                                            AS abc_class
FROM fb
LEFT JOIN hist ON hist.supplier_id = fb.supplier_id AND hist.root_id = fb.root_id
LEFT JOIN iv   ON iv.root_id      = fb.root_id
$supplierWhere
ORDER BY fb.brand_name, fb.category_name, fb.product_name
''';
  }

  /* -------------------------------------------------------------------------- */
  /*                      AP / Disbursement base tables                         */
  /* -------------------------------------------------------------------------- */

  static Future<void> _createAPTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS disbursement (
        id INTEGER PRIMARY KEY,
        doc_no TEXT,
        transaction_date TEXT,
        encoder_id INTEGER,
        approver_id INTEGER,
        date_approved TEXT,
        date_created TEXT,
        date_posted TEXT,
        date_updated TEXT,
        division_id INTEGER,
        payee INTEGER,
        total_amount REAL,
        paid_amount REAL,
        isPosted INTEGER DEFAULT 0,
        posted_by INTEGER,
        remarks TEXT,
        transaction_type INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS disbursement_payables (
        id INTEGER PRIMARY KEY,
        disbursement_id INTEGER,
        coa_id INTEGER,
        amount REAL,
        reference_no TEXT,
        remarks TEXT,
        division_id INTEGER,
        date TEXT,
        date_created TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS disbursement_payments (
        id INTEGER PRIMARY KEY,
        disbursement_id INTEGER,
        coa_id INTEGER,
        bank_id INTEGER,
        amount REAL,
        check_no TEXT,
        date TEXT,
        date_created TEXT,
        remarks TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chart_of_accounts (
        coa_id INTEGER PRIMARY KEY,
        gl_code TEXT,
        account_title TEXT,
        account_type INTEGER,
        memo_type INTEGER,
        bsis_code INTEGER,
        balance_type INTEGER,
        description TEXT,
        is_payment INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bank_accounts (
        bank_id INTEGER PRIMARY KEY,
        bank_name TEXT,
        bank_description TEXT,
        account_number TEXT,
        branch TEXT,
        city TEXT,
        province TEXT,
        baranggay TEXT,
        contact_person TEXT,
        email TEXT,
        mobile_no TEXT,
        opening_balance REAL,
        is_active INTEGER,
        created_at TEXT,
        created_by INTEGER,
        ifsc_code TEXT
      );
    ''');
  }

  /* -------------------------------------------------------------------------- */
  /*                   NEW: Assets & Equipment schema & views                   */
  /* -------------------------------------------------------------------------- */

  static Future<void> _createAssetsTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assets_and_equipment (
        id INTEGER PRIMARY KEY,
        item_id INTEGER,
        item_image TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        rfid_code TEXT,
        barcode TEXT,
        department INTEGER,
        employee INTEGER,
        cost_per_item REAL,
        total REAL,
        condition TEXT,
        life_span INTEGER,
        date_acquired TEXT,
        date_created TEXT
      );
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_assets_department ON assets_and_equipment(department);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_assets_condition  ON assets_and_equipment(condition);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_assets_employee   ON assets_and_equipment(employee);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_assets_item_id    ON assets_and_equipment(item_id);');
  }

  static Future<void> _createAssetsViews(Database db) async {
    await db.execute('DROP VIEW IF EXISTS v_assets_equipment;');
    await db.execute('''
    CREATE VIEW v_assets_equipment AS
    SELECT
      a.id,
      a.item_id,
      a.item_image,
      COALESCE(a.quantity,1) AS quantity,
      a.rfid_code,
      a.barcode,
      a.department,
      a.employee,
      a.cost_per_item,
      COALESCE(a.total, COALESCE(a.cost_per_item,0) * COALESCE(a.quantity,1)) AS total,
      COALESCE(a.condition,'') AS condition,
      a.life_span AS life_span,
      CASE
        WHEN COALESCE(a.life_span,0) > 0
          THEN COALESCE(a.total, COALESCE(a.cost_per_item,0) * COALESCE(a.quantity,1)) * 1.0 / a.life_span
        ELSE 0
      END AS depreciation_value_year,
      a.date_acquired,
      a.date_created
    FROM assets_and_equipment a;
  ''');
  }
}