import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';
import '../local/app_db.dart';

/// Simple progress model for UI
class SyncProgress {
  final int step;
  final int total;
  final String label;

  const SyncProgress({
    required this.step,
    required this.total,
    required this.label,
  });
}

/// Error per sync task (we keep going even if some fail)
class SyncTaskError {
  final String label;
  final Object error;
  final StackTrace stackTrace;

  const SyncTaskError({
    required this.label,
    required this.error,
    required this.stackTrace,
  });
}

/// Internal description of one sync task
class _SyncTask {
  final String label;
  final Future<void> Function() run;

  const _SyncTask(this.label, this.run);
}

class SyncRepository {
  final ApiClient api;
  SyncRepository(this.api);

  Future<Database> get _db async => AppDb.get();

  // =============================
  // META / SAFETY
  // =============================

  /// Ensures we never mix data from two different servers.
  /// If the base URL changed, wipe local tables once.
  /// 
  /// 
  /// 
  /// 
  /// 
  Future<void> _ensureProductClassificationTable(DatabaseExecutor exec) async {
  await exec.execute('''
    CREATE TABLE IF NOT EXISTS product_classification (
      product_id INTEGER PRIMARY KEY,
      abc_class TEXT,
      abc_class_forecast TEXT,
      abc_class_sold TEXT,
      forecast_multiplier REAL
    )
  ''');
}

  Future<void> _resetIfServerBaseChanged() async {
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kv_store (
        k TEXT PRIMARY KEY,
        v TEXT
      )
    ''');

    final base = api.baseUrl; // <-- keep exactly this
    final rows =
    await db.query('kv_store', where: 'k = ?', whereArgs: ['api_base']);
    final saved = rows.isNotEmpty ? rows.first['v'] as String? : null;

    if (saved == null || saved != base) {
      // Different server (or first run) → wipe local rows to avoid mixing.
      await wipeLocal();
      await db.insert(
        'kv_store',
        {'k': 'api_base', 'v': base},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // =============================
  // FULL RESET + PURGE UTILITIES
  // =============================

  /// Drop data (not schema) from all local tables used by sync.
  Future<void> wipeLocal() async {
    final db = await _db;

    // Discover which tables actually exist so we don't crash
    final existingRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final existingTables =
    existingRows.map((e) => (e['name'] as String?) ?? '').toSet();

    final tables = <String>[
      // Delivery
      'post_dispatch_invoices',
      'post_dispatch_plan',
      'post_dispatch_budgeting',
      'post_dispatch_plan_staff',

      // Sales & AR
      'sales_invoice_payments',
      'sales_invoice',
      'sales_order',

      // Itemized dependencies / returns
      'sales_return',
      'salesman',
      'payment_terms',
      'operation',
      'sales_invoice_type',
      'products',
      'sales_invoice_details',
      'sales_return_details',
      'sales_invoice_sales_return',

      // Master refs for products
      'brand',
      'categories',
      'product_per_supplier',
      'units',
      'divisions',

      // Masterfiles
      'user',
      'branches',
      'vehicles',
      'customer',
      'suppliers',

      // Assets & Equipment
      'assets_and_equipment',

      // AP / Disbursement
      'bank_accounts',
      'chart_of_accounts',
      'disbursement_payments',
      'disbursement_payables',
      'disbursement',
 // ADD THIS (since you sync it)
  'product_classification',
      // Stock Transfer
'stock_transfer_local',


    ];

    final batch = db.batch();
    for (final t in tables) {
      if (existingTables.contains(t)) {
        batch.delete(t);
      }
    }
    await batch.commit(noResult: true);
  }

  // -----------------------------
  // SAFE PURGE (FIXED)
  // -----------------------------

  bool _isSafeIdent(String s) {
    // allow only [a-zA-Z_][a-zA-Z0-9_]* to avoid SQL injection via identifiers
    final re = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
    return re.hasMatch(s);
  }

  Future<String> _inferPkSqliteType(DatabaseExecutor exec, String table, String pk) async {
    // Default to TEXT if we cannot infer.
    try {
      final info = await exec.rawQuery('PRAGMA table_info($table)');
      for (final row in info) {
        final name = row['name']?.toString();
        if (name == pk) {
          final t = (row['type']?.toString() ?? '').toUpperCase();
          if (t.contains('INT')) return 'INTEGER';
          // Some schemas use TEXT / VARCHAR / CHAR
          if (t.contains('CHAR') || t.contains('CLOB') || t.contains('TEXT')) return 'TEXT';
          // REAL/NUMERIC are fine too, but PRIMARY KEY is usually INTEGER/TEXT
          return t.isEmpty ? 'TEXT' : t;
        }
      }
    } catch (_) {
      // ignore
    }
    return 'TEXT';
  }

  /// Remove local rows whose primary key is NOT in [remoteIds].
  ///
  /// FIX: Uses a TEMP table + chunked inserts, then deletes using NOT EXISTS
  /// so the DELETE statement has 0 bound variables (avoids "too many SQL variables").
  Future<void> _purgeNotIn({
    required String table,
    required String pk,
    required Iterable<Object?> remoteIds,
  }) async {
    final db = await _db;

    if (!_isSafeIdent(table) || !_isSafeIdent(pk)) {
      throw ArgumentError('Unsafe table/pk identifier: table="$table", pk="$pk"');
    }

    final ids = remoteIds.where((e) => e != null).toList(growable: false);

    // If server returned nothing, wipe table (fresh/empty server).
    if (ids.isEmpty) {
      await db.delete(table);
      return;
    }

    // IMPORTANT: syncAll() uses Future.wait(), so multiple purges can run concurrently.
    // Use a unique temp table name per purge call to avoid collisions.
    final tmp =
        'tmp_keep_${table}_${pk}_${DateTime.now().microsecondsSinceEpoch}';

    await db.transaction((txn) async {
      final pkType = await _inferPkSqliteType(txn, table, pk);

      // Create a dedicated TEMP table for this purge
      await txn.execute('DROP TABLE IF EXISTS $tmp');
      await txn.execute('CREATE TEMP TABLE $tmp (id $pkType PRIMARY KEY)');

      // Insert remote IDs into temp table in chunks to respect variable limits.
      // Keep chunks comfortably under 999.
      const maxVarsPerStmt = 500;

      for (var i = 0; i < ids.length; i += maxVarsPerStmt) {
        final end = (i + maxVarsPerStmt <= ids.length) ? i + maxVarsPerStmt : ids.length;
        final part = ids.sublist(i, end);

        final valuesSql = List.filled(part.length, '(?)').join(',');
        final sql = 'INSERT OR IGNORE INTO $tmp(id) VALUES $valuesSql';

        // Keep argument types intact when possible (int stays int, etc.)
        await txn.rawInsert(sql, part);
      }

      // Delete any local rows whose pk is not in temp keep table
      // (No variables used here).
      await txn.execute('''
        DELETE FROM $table
        WHERE NOT EXISTS (
          SELECT 1
          FROM $tmp k
          WHERE k.id = $table.$pk
        )
      ''');

      // Clean up temp table
      await txn.execute('DROP TABLE IF EXISTS $tmp');
    });
  }

  // =============================
  // SYNC ORCHESTRATION
  // =============================

  /// Original sync (parallel, no progress). Used by app init.
  /// Set [purge]=true to drop local rows not present on server.
  Future<void> syncAll({bool purge = false}) async {
    // Guard against server switch
    await _resetIfServerBaseChanged();
    await Future.wait([
      // Delivery
      syncPostDispatchPlan(purge: purge),
      syncPostDispatchInvoices(purge: purge),
      syncPostDispatchBudgeting(purge: purge),
      syncPostDispatchPlanStaff(purge: purge),

      // Sales & AR
      syncSalesInvoice(purge: purge),
      syncSalesInvoicePayments(purge: purge),
      syncSalesOrder(purge: purge),

      // Master refs for products
      syncBrand(purge: purge),
      syncCategories(purge: purge),
      syncUnits(purge: purge),
      syncProductPerSupplier(purge: purge),
      syncProductClassification(purge: purge),

      // Itemized dependencies / returns
      syncProducts(purge: purge),
      syncSalesInvoiceDetails(purge: purge),
      syncSalesReturnDetails(purge: purge),
      syncSalesInvoiceSalesReturn(purge: purge),

      // Supporting master & lookups
      syncSalesInvoiceType(purge: purge),
      syncOperation(purge: purge),
      syncPaymentTerms(purge: purge),
      syncSalesman(purge: purge),
      syncSalesReturn(purge: purge),
      syncDivisions(purge: purge),

      // Masterfiles
      syncUsers(purge: purge),
      syncBranches(purge: purge),
      syncVehicles(purge: purge),
      syncCustomers(purge: purge),
      syncSuppliers(purge: purge),

      // Assets & Equipment
      syncAssetsAndEquipment(purge: purge),

      // AP / Disbursement
      syncBankAccounts(purge: purge),
      syncChartOfAccounts(purge: purge),
      syncDisbursement(purge: purge),
      syncDisbursementPayables(purge: purge),
      syncDisbursementPayments(purge: purge),
      // Stock Transfer 
      syncStockTransfer(purge: purge),

    ]);
  }

  /// Full reseed—wipe local then re-sync everything with purge.
  Future<void> syncAllFullReset() async {
    await wipeLocal();
    await syncAll(purge: true);
  }

  /// Build the ordered list of sync tasks (so we can reuse for progress mode).
  List<_SyncTask> _buildSyncTasks(bool purge) {
    return <_SyncTask>[
      // Delivery
      _SyncTask('Post Dispatch Plan', () => syncPostDispatchPlan(purge: purge)),
      _SyncTask('Post Dispatch Invoices', () => syncPostDispatchInvoices(purge: purge)),
      _SyncTask('Post Dispatch Budgeting', () => syncPostDispatchBudgeting(purge: purge)),
      _SyncTask('Post Dispatch Plan Staff', () => syncPostDispatchPlanStaff(purge: purge)),

      // Sales & AR
      _SyncTask('Sales Invoice', () => syncSalesInvoice(purge: purge)),
      _SyncTask('Sales Invoice Payments', () => syncSalesInvoicePayments(purge: purge)),
      _SyncTask('Sales Order', () => syncSalesOrder(purge: purge)),

      // Master refs for products
      _SyncTask('Brand', () => syncBrand(purge: purge)),
      _SyncTask('Categories', () => syncCategories(purge: purge)),
      _SyncTask('Units', () => syncUnits(purge: purge)),
      _SyncTask('Product Per Supplier', () => syncProductPerSupplier(purge: purge)),
      _SyncTask('Product Classification', () => syncProductClassification(purge: purge)),

      // Itemized dependencies & returns
      _SyncTask('Products', () => syncProducts(purge: purge)),
      _SyncTask('Sales Invoice Details', () => syncSalesInvoiceDetails(purge: purge)),
      _SyncTask('Sales Return Details', () => syncSalesReturnDetails(purge: purge)),
      _SyncTask('Invoice ↔ Sales Return Link', () => syncSalesInvoiceSalesReturn(purge: purge)),

      // Supporting master & lookups
      _SyncTask('Sales Invoice Type', () => syncSalesInvoiceType(purge: purge)),
      _SyncTask('Operation', () => syncOperation(purge: purge)),
      _SyncTask('Payment Terms', () => syncPaymentTerms(purge: purge)),
      _SyncTask('Salesman', () => syncSalesman(purge: purge)),
      _SyncTask('Sales Return', () => syncSalesReturn(purge: purge)),
      _SyncTask('Divisions', () => syncDivisions(purge: purge)),

      // Masterfiles
      _SyncTask('Users', () => syncUsers(purge: purge)),
      _SyncTask('Branches', () => syncBranches(purge: purge)),
      _SyncTask('Vehicles', () => syncVehicles(purge: purge)),
      _SyncTask('Customers', () => syncCustomers(purge: purge)),
      _SyncTask('Suppliers', () => syncSuppliers(purge: purge)),

      // Assets & Equipment
      _SyncTask('Assets & Equipment', () => syncAssetsAndEquipment(purge: purge)),

      // AP / Disbursement
      _SyncTask('Bank Accounts', () => syncBankAccounts(purge: purge)),
      _SyncTask('Chart Of Accounts', () => syncChartOfAccounts(purge: purge)),
      _SyncTask('Disbursement Headers', () => syncDisbursement(purge: purge)),
      _SyncTask('Disbursement Payables', () => syncDisbursementPayables(purge: purge)),
      _SyncTask('Disbursement Payments', () => syncDisbursementPayments(purge: purge)),

      // Stock Transfer
_SyncTask('Stock Transfer', () => syncStockTransfer(purge: purge)),

    ];
  }




Future<void> syncStockTransfer({bool purge = false}) async {
  final db = await _db;

  await _ensureStockTransferLocalTable(db);

  final rows = await api.getList('/items/stock_transfer?limit=-1');

  final allowedCols = await _getTableColumns(db, 'stock_transfer_local');

  await db.transaction((txn) async {
    final batch = txn.batch();

    for (final r in rows) {
      final payload = <String, Object?>{
        'id': _asIntNullable(r['id']),
        'order_no': _asStringNullable(r['order_no']),
        'product_id': _asIntNullable(r['product_id']),
        'ordered_quantity': _asDouble(r['ordered_quantity']),
        'received_quantity': _asDouble(r['received_quantity']),
        'source_branch': _asIntNullable(r['source_branch']),
        'target_branch': _asIntNullable(r['target_branch']),
        'status': _asStringNullable(r['status']),
        'remarks': _asStringNullable(r['remarks']),
        'amount': _asDouble(r['amount']),
        'encoder_id': _asIntNullable(r['encoder_id']),
        'receiver_id': _asIntNullable(r['receiver_id']),
        'date_requested': _asStringNullable(r['date_requested']),
        'date_received': _asStringNullable(r['date_received']),
        'date_encoded': _asStringNullable(r['date_encoded']),
        'lead_date': _asStringNullable(r['lead_date']),
      };

      payload.removeWhere((k, _) => !allowedCols.contains(k));

      batch.insert(
        'stock_transfer_local',
        payload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  });

  if (purge) {
    await _purgeNotIn(
      table: 'stock_transfer_local',
      pk: 'id',
      remoteIds: rows.map((e) => e['id']),
    );
  }
}



Future<void> _ensureStockTransferLocalTable(DatabaseExecutor exec) async {
  await exec.execute('''
    CREATE TABLE IF NOT EXISTS stock_transfer_local (
      id INTEGER PRIMARY KEY,
      order_no TEXT,
      product_id INTEGER,
      ordered_quantity REAL,
      received_quantity REAL,
      source_branch INTEGER,
      target_branch INTEGER,
      status TEXT,
      remarks TEXT,
      amount REAL,
      encoder_id INTEGER,
      receiver_id INTEGER,
      date_requested TEXT,
      date_received TEXT,
      date_encoded TEXT,
      lead_date TEXT,

      -- Boss offline approval fields
      boss_status_override TEXT,
      boss_action_at TEXT,
      boss_action_by TEXT,
      boss_rejected INTEGER DEFAULT 0,
      boss_reject_reason TEXT,

      -- Upload tracking
      boss_synced INTEGER DEFAULT 0,
      boss_sync_error TEXT
    )
  ''');
}

Future<void> _ensureStockTransferBossColumnsLocal(DatabaseExecutor exec) async {
  final info = await exec.rawQuery("PRAGMA table_info(stock_transfer_local)");
  final cols = info.map((e) => (e["name"]?.toString() ?? "")).toSet();

  Future<void> addCol(String name, String type, {String? defaultSql}) async {
    if (cols.contains(name)) return;
    final def = (defaultSql != null && defaultSql.trim().isNotEmpty)
        ? " DEFAULT $defaultSql"
        : "";
    await exec.execute("ALTER TABLE stock_transfer_local ADD COLUMN $name $type$def");
  }

  await addCol("boss_status_override", "TEXT");
  await addCol("boss_action_at", "TEXT");
  await addCol("boss_action_by", "TEXT");
  await addCol("boss_rejected", "INTEGER", defaultSql: "0");
  await addCol("boss_reject_reason", "TEXT");
  await addCol("boss_synced", "INTEGER", defaultSql: "0");
  await addCol("boss_sync_error", "TEXT");
}


Future<Set<String>> _getTableColumns(DatabaseExecutor exec, String table) async {
  final rows = await exec.rawQuery('PRAGMA table_info($table)');
  return rows
      .map((e) => e['name']?.toString() ?? '')
      .where((s) => s.isNotEmpty)
      .toSet();
}





// /// Returns the set of columns existing in a SQLite table.
// Future<Set<String>> _getTableColumns(DatabaseExecutor exec, String table) async {
//   final rows = await exec.rawQuery('PRAGMA table_info($table)');
//   return rows
//       .map((e) => e['name']?.toString() ?? '')
//       .where((s) => s.isNotEmpty)
//       .toSet();
// }



  Future<void> syncProductClassification({bool purge = false}) async {
  final db = await _db;

  await _ensureProductClassificationTable(db);

  final rows = await api.getList('/items/product_classification?limit=-1');
  final batch = db.batch();

  for (final r in rows) {
    batch.insert(
      'product_classification',
      {
        'product_id': _asIntNullable(r['product_id']),
        'abc_class': _asStringNullable(r['abc_class']),
        'abc_class_forecast': _asStringNullable(r['abc_class_forecast']),
        'abc_class_sold': _asStringNullable(r['abc_class_sold']),
        'forecast_multiplier': _asDouble(r['forecast_multiplier']),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  await batch.commit(noResult: true);

  if (purge) {
    await _purgeNotIn(
      table: 'product_classification',
      pk: 'product_id',
      remoteIds: rows.map((e) => e['product_id']),
    );
  }
}

  Future<List<SyncTaskError>> syncAllWithProgress({
    bool purge = false,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    await _resetIfServerBaseChanged();

    final tasks = _buildSyncTasks(purge);
    final total = tasks.length;
    final errors = <SyncTaskError>[];

    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];

      // Notify UI
      onProgress?.call(SyncProgress(
        step: i + 1,
        total: total,
        label: task.label,
      ));

      try {
        await task.run();
      } catch (e, st) {
        // Keep going but record the error
        errors.add(
          SyncTaskError(label: task.label, error: e, stackTrace: st),
        );
        // ignore: avoid_print
        print('Sync error in ${task.label}: $e');
      }
    }

    return errors;
  }

  /* ----------------- parsers ----------------- */

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return 0.0;
    return double.tryParse(s) ?? 0.0;
  }

  int? _asIntNullable(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// Converts assorted truthy/falsy payloads (bool/int/string/Buffer map) to 0/1
  int _asBoolToInt(dynamic v) {
    if (v == null) return 0;
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v != 0 ? 1 : 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      return (s == '1' || s == 'true' || s == 't' || s == 'yes' || s == 'y')
          ? 1
          : 0;
    }
    // Directus-like Buffer: { type: 'Buffer', data: [0|1] }
    if (v is Map && v['data'] is List && (v['data'] as List).isNotEmpty) {
      final first = (v['data'] as List).first;
      if (first is num) return first != 0 ? 1 : 0;
    }
    return 0;
  }

  String? _asStringNullable(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  /* ----------------- SYNC FUNCTIONS (with purge) ----------------- */

  /// NEW: Assets & Equipment
  Future<void> syncAssetsAndEquipment({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/assets_and_equipment?limit=-1');
    final batch = db.batch();

    for (final r in rows) {
      batch.insert(
        'assets_and_equipment',
        {
          'id': r['id'],
          'item_id': _asIntNullable(r['item_id']),
          'item_image': _asStringNullable(r['item_image']),
          'quantity': _asIntNullable(r['quantity']),
          'rfid_code': _asStringNullable(r['rfid_code']),
          'barcode': _asStringNullable(r['barcode']),
          'department': _asIntNullable(r['department']),
          'employee': _asIntNullable(r['employee']),
          'cost_per_item': _asDouble(r['cost_per_item']),
          'total': _asDouble(r['total']),
          'condition': _asStringNullable(r['condition']),
          'life_span': _asIntNullable(r['life_span']),
          'date_acquired': _asStringNullable(r['date_acquired']),
          'date_created': _asStringNullable(r['date_created']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'assets_and_equipment',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncPostDispatchInvoices({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/post_dispatch_invoices?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'post_dispatch_invoices',
        {
          'id': r['id'],
          'invoice_id': r['invoice_id'],
          'post_dispatch_plan_id': r['post_dispatch_plan_id'],
          'sequence': r['sequence'],
          'status': r['status'],
          'distance': _asDouble(r['distance']),
          'invoiceAt': r['invoiceAt'],
          'isCleared': r['isCleared'] ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'post_dispatch_invoices',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncPostDispatchPlan({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/post_dispatch_plan?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'post_dispatch_plan',
        {
          'id': r['id'],
          'doc_no': r['doc_no'],
          'driver_id': r['driver_id'],
          'encoder_id': r['encoder_id'],
          'starting_point': r['starting_point'],
          'vehicle_id': r['vehicle_id'],
          'status': r['status'],
          'amount': _asDouble(r['amount']),
          'estimated_time_of_dispatch': r['estimated_time_of_dispatch'],
          'estimated_time_of_arrival': r['estimated_time_of_arrival'],
          'time_of_dispatch': r['time_of_dispatch'],
          'time_of_arrival': r['time_of_arrival'],
          'date_encoded': r['date_encoded'],
          'remarks': r['remarks'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'post_dispatch_plan',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  // includes payment_terms + due_date + is_posted (+ new v10 fields if present)
  Future<void> syncSalesInvoice({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/sales_invoice?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'sales_invoice',
        {
          'invoice_id': r['invoice_id'],
          'invoice_no': r['invoice_no'],
          'invoice_date': r['invoice_date'],
          'customer_code': r['customer_code'],
          'branch_id': r['branch_id'],
          'gross_amount': _asDouble(r['gross_amount']),
          'total_amount': _asDouble(r['total_amount']),
          'discount_amount': _asDouble(r['discount_amount']),
          'net_amount': _asDouble(r['net_amount']),
          'order_id': r['order_id']?.toString(),
          'dispatch_date': r['dispatch_date'],
          'payment_status': r['payment_status'],
          'transaction_status': r['transaction_status'],
          'due_date': r['due_date'],
          'payment_terms': _asIntNullable(r['payment_terms']),
          'is_posted': _asBoolToInt(r['isPosted']),

          // v10 fields (safe if missing)
          'salesman_id': _asIntNullable(r['salesman_id']),
          'sales_type': _asIntNullable(r['sales_type']),
          'invoice_type': _asIntNullable(r['invoice_type']),
          'price_type': _asStringNullable(r['price_type']),
          'created_by': _asIntNullable(r['created_by']),
          'created_date': _asStringNullable(r['created_date']),
          'modified_by': _asIntNullable(r['modified_by']),
          'modified_date': _asStringNullable(r['modified_date']),
          'isReceipt': _asBoolToInt(r['isReceipt']),
          'isDispatched': _asBoolToInt(r['isDispatched']),
          'isRemitted': _asBoolToInt(r['isRemitted']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'sales_invoice',
        pk: 'invoice_id',
        remoteIds: rows.map((e) => e['invoice_id']),
      );
    }
  }

  Future<void> syncSalesInvoicePayments({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/sales_invoice_payments?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'sales_invoice_payments',
        {
          'id': r['id'],
          'invoice_id': r['invoice_id'],
          'order_id': r['order_id']?.toString(),
          'coa_id': r['coa_id'],
          'bank_id': r['bank_id'],
          'reference_no': r['reference_no'],
          'paid_amount': _asDouble(r['paid_amount']),
          'date_paid': r['date_paid'],
          'date_encoded': r['date_encoded'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'sales_invoice_payments',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncSalesOrder({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/sales_order?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'sales_order',
        {
          'order_id': r['order_id'],
          'order_no': r['order_no'],
          'customer_code': r['customer_code'],
          'supplier_id': r['supplier_id'],
          'branch_id': r['branch_id'],
          'order_status': r['order_status'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'sales_order',
        pk: 'order_id',
        remoteIds: rows.map((e) => e['order_id']),
      );
    }
  }

  /// /items/brand?limit=-1
  Future<void> syncBrand({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/brand?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'brand',
        {
          'brand_id': r['brand_id'],
          'brand_name': r['brand_name'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    if (purge) {
      await _purgeNotIn(
        table: 'brand',
        pk: 'brand_id',
        remoteIds: rows.map((e) => e['brand_id']),
      );
    }
  }

  /// /items/categories?limit=-1
  Future<void> syncCategories({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/categories?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'categories',
        {
          'category_id': r['category_id'],
          'category_name': r['category_name'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    if (purge) {
      await _purgeNotIn(
        table: 'categories',
        pk: 'category_id',
        remoteIds: rows.map((e) => e['category_id']),
      );
    }
  }

  /// /items/units?limit=-1
  Future<void> syncUnits({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/units?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'units',
        {
          'unit_id': r['unit_id'],
          'unit_name': r['unit_name'],
          'unit_shortcut': r['unit_shortcut'],
          'order': _asIntNullable(r['order']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    if (purge) {
      await _purgeNotIn(
        table: 'units',
        pk: 'unit_id',
        remoteIds: rows.map((e) => e['unit_id']),
      );
    }
  }

  /// /items/product_per_supplier?limit=-1
  Future<void> syncProductPerSupplier({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/product_per_supplier?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'product_per_supplier',
        {
          'id': r['id'],
          'supplier_id': r['supplier_id'],
          'product_id': r['product_id'],
          'discount_type': _asIntNullable(r['discount_type']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    if (purge) {
      await _purgeNotIn(
        table: 'product_per_supplier',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  /// /items/products?limit=-1
  Future<void> syncProducts({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/products?limit=-1');
    final batch = db.batch();

    for (final r in rows) {
      batch.insert(
        'products',
        {
          'product_id': r['product_id'],
          'product_code': _asStringNullable(r['product_code']),
          'barcode': _asStringNullable(r['barcode']),
          'product_name': r['product_name'],
          'short_description': _asStringNullable(r['short_description']),
          'description': _asStringNullable(r['description']),
          'product_image': _asStringNullable(r['product_image']),
          'product_brand': _asIntNullable(r['product_brand']),
          'product_category': _asIntNullable(r['product_category']),
          'parent_id': _asIntNullable(r['parent_id'] ?? r['parentId'] ?? r['parent']),
          'isActive': _asBoolToInt(r['isActive']),
          'product_class': _asIntNullable(r['product_class']),
          'product_segment': _asIntNullable(r['product_segment']),
          'product_section': _asIntNullable(r['product_section']),
          'product_shelf_life': _asStringNullable(r['product_shelf_life']),
          'product_weight': _asDouble(r['product_weight']),
          'maintaining_quantity': _asDouble(r['maintaining_quantity']),
          'unit_of_measurement': _asIntNullable(r['unit_of_measurement']),
          'unit_of_measurement_count': _asIntNullable(r['unit_of_measurement_count']),
          'estimated_unit_cost': _asDouble(r['estimated_unit_cost']),
          'estimated_extended_cost': _asDouble(r['estimated_extended_cost']),
          'price_per_unit': _asDouble(r['price_per_unit']),
          'cost_per_unit': _asDouble(r['cost_per_unit']),
          'priceA': _asDouble(r['priceA']),
          'priceB': _asDouble(r['priceB']),
          'priceC': _asDouble(r['priceC']),
          'priceD': _asDouble(r['priceD']),
          'priceE': _asDouble(r['priceE']),
          'product_type': _asStringNullable(r['product_type']),
          'external_id': _asStringNullable(r['external_id']),
          'date_added': _asStringNullable(r['date_added']),
          'last_updated': _asStringNullable(r['last_updated']),
          'created_at': _asStringNullable(r['created_at']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'products',
        pk: 'product_id',
        remoteIds: rows.map((e) => e['product_id']),
      );
    }
  }

  /// /items/sales_invoice_details?limit=-1
  Future<void> syncSalesInvoiceDetails({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/sales_invoice_details?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'sales_invoice_details',
        {
          'detail_id': r['detail_id'],
          'order_id': r['order_id']?.toString(),
          'invoice_no': r['invoice_no'],
          'product_id': r['product_id'],
          'unit': r['unit'],
          'unit_price': _asDouble(r['unit_price']),
          'quantity': _asDouble(r['quantity']),
          'discount_amount': _asDouble(r['discount_amount']),
          'total_amount': _asDouble(r['total_amount']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'sales_invoice_details',
        pk: 'detail_id',
        remoteIds: rows.map((e) => e['detail_id']),
      );
    }
  }

  /// /items/sales_return_details?limit=-1
  Future<void> syncSalesReturnDetails({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/sales_return_details?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'sales_return_details',
        {
          'detail_id': r['detail_id'],
          'return_no': r['return_no']?.toString(),
          'product_id': r['product_id'],
          'quantity': _asDouble(r['quantity']),
          'unit_price': _asDouble(r['unit_price']),
          'total_amount': _asDouble(r['total_amount']),
          'discount_amount': _asDouble(r['discount_amount']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'sales_return_details',
        pk: 'detail_id',
        remoteIds: rows.map((e) => e['detail_id']),
      );
    }
  }

  /// /items/sales_invoice_sales_return?limit=-1 (junction)
  Future<void> syncSalesInvoiceSalesReturn({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/sales_invoice_sales_return?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'sales_invoice_sales_return',
        {
          'id': r['id'],
          'return_no': r['return_no'],
          'invoice_no': r['invoice_no'],
          'linked_by': r['linked_by'],
          'created_at': r['created_at'],
          'updated_at': r['updated_at'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'sales_invoice_sales_return',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  // ---------- Supporting tables for views ----------

  Future<void> syncSalesReturn({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/sales_return?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'sales_return',
        {
          'return_id': r['return_id'],
          'return_number': r['return_number'],
          'customer_code': r['customer_code'],
          'salesman_id': r['salesman_id'],
          'branch_id': r['branch_id'],
          'return_date': r['return_date'],
          'total_amount': _asDouble(r['total_amount']),
          'discount_amount': _asDouble(r['discount_amount']),
          'gross_amount': _asDouble(r['gross_amount']),
          'remarks': r['remarks'],
          'created_by': r['created_by'],
          'order_id': r['order_id'],
          'invoice_no': r['invoice_no'],
          'created_at': r['created_at'],
          'updated_at': r['updated_at'],
          'received_at': r['received_at'],
          'isThirdParty': _asBoolToInt(r['isThirdParty']),
          'price_type': r['price_type'],
          'status': r['status'],
          'isPosted': _asBoolToInt(r['isPosted']),
          'isApplied': _asBoolToInt(r['isApplied']),
          'isReceived': _asBoolToInt(r['isReceived']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'sales_return',
        pk: 'return_id',
        remoteIds: rows.map((e) => e['return_id']),
      );
    }
  }

  Future<void> syncSalesman({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/salesman?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'salesman',
        {
          'id': r['id'],
          'employee_id': r['employee_id'],
          'salesman_code': r['salesman_code'],
          'salesman_name': r['salesman_name'],
          'truck_plate': r['truck_plate'],
          'division_id': r['division_id'],
          'branch_code': r['branch_code'],
          'bad_branch_code': r['bad_branch_code'],
          'operation': r['operation'],
          'company_code': r['company_code'],
          'supplier_code': r['supplier_code'],
          'price_type': r['price_type'],
          'isActive': _asBoolToInt(r['isActive']),
          'isInventory': _asBoolToInt(r['isInventory']),
          'canCollect': _asBoolToInt(r['canCollect']),
          'inventory_day': r['inventory_day'],
          'modified_date': r['modified_date'],
          'encoder_id': r['encoder_id'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'salesman',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  /// NEW: /items/divisions?limit=-1
  Future<void> syncDivisions({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/division?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      final divId = _asIntNullable(r['division_id'] ?? r['id']);
      final divName = _asStringNullable(r['division_name'] ?? r['name']);

      batch.insert(
        'divisions',
        {
          'division_id': divId,
          'division_name': divName,
          'division_description': _asStringNullable(r['division_description']),
          'division_head': _asStringNullable(r['division_head']),
          'division_code': _asStringNullable(r['division_code']),
          'date_added': _asStringNullable(r['date_added']),
          'id': divId,
          'name': divName,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    if (purge) {
      await _purgeNotIn(
        table: 'divisions',
        pk: 'division_id',
        remoteIds: rows.map((e) => e['division_id'] ?? e['id']),
      );
    }
  }

  Future<void> syncPaymentTerms({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/payment_terms?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'payment_terms',
        {
          'id': r['id'],
          'payment_name': r['payment_name'],
          'payment_days': r['payment_days'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'payment_terms',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncOperation({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/operation?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'operation',
        {
          'id': r['id'],
          'operation_code': r['operation_code'],
          'operation_name': r['operation_name'],
          'date_modified': r['date_modified'],
          'encoder_id': r['encoder_id'],
          'company_id': r['company_id'],
          'type': r['type'],
          'definition': r['definition'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'operation',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncSalesInvoiceType({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/sales_invoice_type?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'sales_invoice_type',
        {
          'id': r['id'],
          'type': r['type'],
          'shortcut': r['shortcut'],
          'max_length': r['max_length'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'sales_invoice_type',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  // ---------- Masterfiles ----------

  Future<void> syncUsers({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/user?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'user',
        {
          'user_id': r['user_id'],
          'user_fname': r['user_fname'],
          'user_mname': r['user_mname'],
          'user_lname': r['user_lname'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'user',
        pk: 'user_id',
        remoteIds: rows.map((e) => e['user_id']),
      );
    }
  }

  Future<void> syncBranches({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/branches?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'branches',
        {
          'id': r['id'],
          'branch_name': r['branch_name'],
          'city': r['city'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'branches',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncVehicles({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/vehicles?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'vehicles',
        {
          'vehicle_id': r['vehicle_id'],
          'vehicle_plate': r['vehicle_plate'],
          'status': r['status'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'vehicles',
        pk: 'vehicle_id',
        remoteIds: rows.map((e) => e['vehicle_id']),
      );
    }
  }

  Future<void> syncCustomers({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/customer?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'customer',
        {
          'customer_code': r['customer_code'],
          'customer_name': r['customer_name'],
          'brgy': r['brgy'],
          'city': r['city'],
          'province': r['province'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'customer',
        pk: 'customer_code',
        remoteIds: rows.map((e) => e['customer_code']),
      );
    }
  }

  Future<void> syncSuppliers({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/suppliers?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'suppliers',
        {
          'id': r['id'],
          'supplier_shortcut': r['supplier_shortcut'],
          'supplier_name': r['supplier_name'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'suppliers',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncPostDispatchBudgeting({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/post_dispatch_budgeting?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'post_dispatch_budgeting',
        {
          'id': r['id'],
          'post_dispatch_plan_id': r['post_dispatch_plan_id'],
          'coa_id': r['coa_id'],
          'remarks': r['remarks'],
          'amount': _asDouble(r['amount']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'post_dispatch_budgeting',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncPostDispatchPlanStaff({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/post_dispatch_plan_staff?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'post_dispatch_plan_staff',
        {
          'id': r['id'],
          'post_dispatch_plan_id': r['post_dispatch_plan_id'],
          'user_id': r['user_id'],
          'role': r['role'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'post_dispatch_plan_staff',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncBankAccounts({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/bank_accounts?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'bank_accounts',
        {
          'bank_id': r['bank_id'],
          'bank_name': r['bank_name'],
          'bank_description': r['bank_description'],
          'account_number': r['account_number'],
          'branch': r['branch'],
          'city': r['city'],
          'province': r['province'],
          'baranggay': r['baranggay'],
          'contact_person': r['contact_person'],
          'email': r['email'],
          'mobile_no': _asStringNullable(r['mobile_no']),
          'opening_balance': _asDouble(r['opening_balance']),
          'is_active': _asBoolToInt(r['is_active']),
          'created_at': r['created_at'],
          'created_by': r['created_by'],
          'ifsc_code': r['ifsc_code'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'bank_accounts',
        pk: 'bank_id',
        remoteIds: rows.map((e) => e['bank_id']),
      );
    }
  }

  Future<void> syncChartOfAccounts({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/chart_of_accounts?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'chart_of_accounts',
        {
          'coa_id': r['coa_id'],
          'gl_code': r['gl_code']?.toString(),
          'account_title': r['account_title'],
          'account_type': r['account_type'],
          'memo_type': r['memo_type'],
          'bsis_code': r['bsis_code'],
          'balance_type': r['balance_type'],
          'description': r['description'],
          'is_payment': _asBoolToInt(r['is_payment'] ?? r['isPayment']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'chart_of_accounts',
        pk: 'coa_id',
        remoteIds: rows.map((e) => e['coa_id']),
      );
    }
  }

  Future<void> syncDisbursement({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/disbursement?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'disbursement',
        {
          'id': r['id'],
          'doc_no': r['doc_no'],
          'transaction_date': r['transaction_date'],
          'encoder_id': r['encoder_id'],
          'approver_id': r['approver_id'],
          'date_approved': r['date_approved'],
          'date_created': r['date_created'],
          'date_posted': r['date_posted'],
          'date_updated': r['date_updated'],
          'division_id': r['division_id'],
          'payee': r['payee'],
          'total_amount': _asDouble(r['total_amount']),
          'paid_amount': _asDouble(r['paid_amount']),
          'isPosted': _asBoolToInt(r['isPosted']),
          'posted_by': r['posted_by'],
          'remarks': r['remarks'],
          'transaction_type': r['transaction_type'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'disbursement',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncDisbursementPayables({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/disbursement_payables?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'disbursement_payables',
        {
          'id': r['id'],
          'disbursement_id': r['disbursement_id'],
          'coa_id': r['coa_id'],
          'amount': _asDouble(r['amount']),
          'reference_no': r['reference_no'],
          'remarks': r['remarks'],
          'division_id': r['division_id'],
          'date': r['date'],
          'date_created': r['date_created'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'disbursement_payables',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  Future<void> syncDisbursementPayments({bool purge = false}) async {
    final db = await _db;
    final rows = await api.getList('/items/disbursement_payments?limit=-1');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'disbursement_payments',
        {
          'id': r['id'],
          'disbursement_id': r['disbursement_id'],
          'coa_id': r['coa_id'],
          'bank_id': r['bank_id'],
          'amount': _asDouble(r['amount']),
          'check_no': _asStringNullable(r['check_no']),
          'date': r['date'],
          'date_created': r['date_created'],
          'remarks': r['remarks'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    if (purge) {
      await _purgeNotIn(
        table: 'disbursement_payments',
        pk: 'id',
        remoteIds: rows.map((e) => e['id']),
      );
    }
  }

  // ============================
  // QUERIES from local SQLite
  // ============================

  Future<List<Map<String, Object?>>> getDeliveryReport({
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _db;
    return db.rawQuery(
      'SELECT * FROM v_delivery_report LIMIT ? OFFSET ?',
      [limit, offset],
    );
  }

  Future<List<Map<String, Object?>>> getDeliveryReportFiltered({
    DateTime? from,
    DateTime? to,
    String? driverName,
    String? search,
  }) async {
    final db = await _db;
    String _toIsoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add("(substr(COALESCE(invoice_date, date_encoded),1,10) >= ?)");
      args.add(_toIsoDate(from));
    }
    if (to != null) {
      where.add("(substr(COALESCE(invoice_date, date_encoded),1,10) <= ?)");
      args.add(_toIsoDate(to));
    }
    if (driverName != null && driverName.trim().isNotEmpty) {
      where.add("driver_name LIKE ?");
      args.add('%$driverName%');
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add(
        "(customer_name LIKE ? OR invoice_no LIKE ? OR doc_no LIKE ? OR city_town_name LIKE ?)",
      );
      args.addAll(List.filled(4, '%$search%'));
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final sql = '''
      SELECT *
      FROM v_delivery_report
      $whereSql
      ORDER BY driver_name, Seq, invoice_no
    ''';

    return db.rawQuery(sql, args);
  }

  Future<List<String>> getDistinctDrivers() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT DISTINCT driver_name
      FROM v_delivery_report
      WHERE driver_name IS NOT NULL AND TRIM(driver_name) <> ''
      ORDER BY driver_name
    ''');
    return rows
        .map((e) => (e['driver_name'] as String?)?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Vendor cards (unpaid only; hide zero balances).
  Future<List<Map<String, Object?>>> getApVendorsSummary({
    String? search,
    String? status, // 'Overdue' | 'Due Soon' | 'Not Due' | 'Settled' (we never return Settled here)
    DateTime? fromDue,
    DateTime? toDue,
    int limit = 500,
    int offset = 0,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    String _iso(DateTime d) =>
        DateFormat('yyyy-MM-dd').format(d);

    if (search != null && search.trim().isNotEmpty) {
      where.add('a.vendor LIKE ?');
      args.add('%${search.trim()}%');
    }
    if (status != null && status.trim().isNotEmpty) {
      where.add('a.status = ?');
      args.add(status.trim());
    }
    if (fromDue != null) {
      where.add('(a.due IS NOT NULL AND a.due >= ?)');
      args.add(_iso(fromDue));
    }
    if (toDue != null) {
      where.add('(a.due IS NOT NULL AND a.due <= ?)');
      args.add(_iso(toDue));
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final sql = '''
      WITH bills AS (
        SELECT
          payee_id,
          payee_name,
          balance,
          due_date,
          header_remarks,
          line_remarks
        FROM v_ap_bills
        WHERE is_posted = 0              -- unpaid only
          AND COALESCE(balance, 0) > 0   -- hide zero/settled
      ),
      agg AS (
        SELECT
          payee_id,
          MAX(payee_name)             AS vendor,
          SUM(balance)                AS total,
          MIN(due_date)               AS due
        FROM bills
        GROUP BY payee_id
      )
      SELECT
        a.payee_id,
        a.vendor                     AS vendor,
        a.total                      AS total,
        a.due                        AS due,
        CASE
          WHEN a.due IS NULL THEN 'Not Due'
          WHEN a.due <  date('now') THEN 'Overdue'
          WHEN a.due <= date('now','+7 day') THEN 'Due Soon'
          ELSE 'Not Due'
        END                          AS status,
        (
          SELECT
            COALESCE(
              NULLIF(TRIM(b.header_remarks), ''),
              NULLIF(TRIM(b.line_remarks), '')
            )
          FROM v_ap_bills b
          WHERE b.payee_id = a.payee_id
            AND b.is_posted = 0
            AND COALESCE(b.balance,0) > 0
            AND (
              (b.header_remarks IS NOT NULL AND TRIM(b.header_remarks) <> '')
               OR
              (b.line_remarks   IS NOT NULL AND TRIM(b.line_remarks)   <> '')
            )
          ORDER BY COALESCE(b.due_date, b.transaction_date) ASC
          LIMIT 1
        )                            AS remarks
      FROM agg a
      $whereSql
      ORDER BY a.total DESC, a.vendor
      LIMIT ? OFFSET ?
    ''';

    args..add(limit)..add(offset);
    return db.rawQuery(sql, args);
  }

  /// Vendor detail bills (unpaid only; non-zero balance).
  Future<List<Map<String, Object?>>> getVendorBillsForUI(int payeeId) async {
    final db = await _db;

    const sql = '''
    SELECT
      v.doc_no                    AS no,
      v.due_date                  AS due,
      v.balance                   AS amount,

      /* Prefer header_remarks -> line_remarks from v_ap_bills.
         If both are empty, fall back to raw line remarks, then header remarks. */
      COALESCE(
        NULLIF(TRIM(v.header_remarks), ''),
        NULLIF(TRIM(v.line_remarks), ''),
        (
          SELECT GROUP_CONCAT(TRIM(x.remarks), ' | ')
          FROM disbursement_payables x
          WHERE x.disbursement_id = v.disbursement_id
            AND x.remarks IS NOT NULL
            AND TRIM(x.remarks) <> ''
        ),
        (
          SELECT TRIM(d.remarks)
          FROM disbursement d
          WHERE d.id = v.disbursement_id
            AND d.remarks IS NOT NULL
            AND TRIM(d.remarks) <> ''
        ),
        ''
      )                           AS remarks,

      v.primary_coa_id,
      v.primary_coa_gl,
      v.primary_coa_title,
      v.coa_list

    FROM v_ap_bills v
    WHERE v.payee_id = ?
      AND v.is_posted = 0              -- unpaid only
      AND COALESCE(v.balance,0) > 0    -- hide settled rows
    ORDER BY COALESCE(v.due_date, v.transaction_date) ASC, v.disbursement_id ASC
  ''';

    return db.rawQuery(sql, [payeeId]);
  }

  /// Per vendor x COA totals.
  Future<List<Map<String, Object?>>> getVendorCoaBreakdown(
      int payeeId) async {
    final db = await _db;
    const sql = '''
      SELECT
        dp.coa_id                         AS coa_id,
        coa.gl_code                       AS gl_code,
        coa.account_title                 AS account_title,
        SUM(COALESCE(dp.amount,0))        AS total_line_amount
      FROM disbursement_payables dp
      JOIN disbursement d        ON d.id = dp.disbursement_id
      LEFT JOIN chart_of_accounts coa ON coa.coa_id = dp.coa_id
      WHERE d.payee = ?
      GROUP BY dp.coa_id, coa.gl_code, coa.account_title
      ORDER BY gl_code, account_title
    ''';
    return db.rawQuery(sql, [payeeId]);
  }

  /// Disbursement headers (book) with computed paid and balance.
  Future<List<Map<String, Object?>>> getDisbursementBook({
    int? posted, // null = all, 0 = unposted, 1 = posted
    DateTime? from,
    DateTime? to,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await _db;
    final args = <Object?>[];
    String _iso(DateTime d) =>
        DateFormat('yyyy-MM-dd').format(d);

    final base = '''
      SELECT
        d.id                               AS disbursement_id,
        d.doc_no                           AS doc_no,
        date(d.transaction_date)           AS transaction_date,
        d.payee                            AS payee_id,
        s.supplier_name                    AS payee_name,
        d.total_amount                     AS total_amount,
        COALESCE((
          SELECT SUM(COALESCE(amount,0))
          FROM disbursement_payments p
          WHERE p.disbursement_id = d.id
        ), 0)                              AS paid_amount,
        MAX(d.total_amount - COALESCE(( 
          SELECT SUM(COALESCE(amount,0))
          FROM disbursement_payments p
          WHERE p.disbursement_id = d.id
        ), 0), 0)                          AS balance,
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
      LEFT JOIN suppliers s ON s.id = d.payee
    ''';

    final where = <String>[];
    if (posted != null) {
      where.add('COALESCE(d.isPosted,0) = ?');
      args.add(posted);
    }
    if (from != null) {
      where.add('date(d.transaction_date) >= ?');
      args.add(_iso(from));
    }
    if (to != null) {
      where.add('date(d.transaction_date) <= ?');
      args.add(_iso(to));
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final sql = '''
      $base
      $whereSql
      ORDER BY d.transaction_date DESC, d.id DESC
      LIMIT ? OFFSET ?
    ''';
    args..add(limit)..add(offset);

    return db.rawQuery(sql, args);
  }

  /// Line-level AP register (detail).
  Future<List<Map<String, Object?>>> getApRegister({
    DateTime? from,
    DateTime? to,
    int? divisionId,
    int? payeeId,
    int limit = 500,
    int offset = 0,
  }) async {
    final db = await _db;
    final args = <Object?>[];
    String _iso(DateTime d) =>
        DateFormat('yyyy-MM-dd').format(d);

    final base = '''
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
    ''';

    final where = <String>[];
    if (from != null) {
      where.add('date(d.transaction_date) >= ?');
      args.add(_iso(from));
    }
    if (to != null) {
      where.add('date(d.transaction_date) <= ?');
      args.add(_iso(to));
    }
    if (divisionId != null) {
      where.add('d.division_id = ?');
      args.add(divisionId);
    }
    if (payeeId != null) {
      where.add('d.payee = ?');
      args.add(payeeId);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final sql = '''
      $base
      $whereSql
      ORDER BY d.transaction_date DESC, d.id, dp.id
      LIMIT ? OFFSET ?
    ''';
    args..add(limit)..add(offset);
    return db.rawQuery(sql, args);
  }

  /// Payment ledger with bank & COA filters.
  Future<List<Map<String, Object?>>> getPaymentLedger({
    int? bankId,
    DateTime? from,
    DateTime? to,
    int limit = 500,
    int offset = 0,
  }) async {
    final db = await _db;
    String _iso(DateTime d) =>
        DateFormat('yyyy-MM-dd').format(d);

    final whereParts = <String>[];
    final params = <Object?>[];

    String base = '''
      SELECT
        dpmt.id                        AS payment_id,
        dpmt.disbursement_id,
        d.doc_no,
        date(dpmt.date)                AS payment_date,
        dpmt.amount,
        dpmt.check_no,
        dpmt.remarks                   AS payment_remarks,
        dpmt.coa_id,
        coa.account_title              AS payment_account_title,
        dpmt.bank_id,
        b.bank_name,
        b.bank_description,
        b.account_number
      FROM disbursement_payments dpmt
      LEFT JOIN disbursement d          ON d.id = dpmt.disbursement_id
      LEFT JOIN chart_of_accounts coa   ON coa.coa_id = dpmt.coa_id
      LEFT JOIN bank_accounts b         ON b.bank_id = dpmt.bank_id
    ''';

    if (bankId != null) {
      whereParts.add('dpmt.bank_id = ?');
      params.add(bankId);
    }
    if (from != null) {
      whereParts.add('date(dpmt.date) >= ?');
      params.add(_iso(from));
    }
    if (to != null) {
      whereParts.add('date(dpmt.date) <= ?');
      params.add(_iso(to));
    }

    final whereSql =
    whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}';
    final sql = '''
      $base
      $whereSql
      ORDER BY dpmt.date DESC, dpmt.id DESC
      LIMIT ? OFFSET ?
    ''';
    params..add(limit)..add(offset);

    return db.rawQuery(sql, params);
  }
}
