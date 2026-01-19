import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../data/local/app_db.dart';

/// Depreciation period selector (matches your UI chips)
enum DepreciationPeriod { day, week, month, bimonth, year }

extension DepreciationPeriodLabel on DepreciationPeriod {
  String get label {
    switch (this) {
      case DepreciationPeriod.day:
        return 'Day';
      case DepreciationPeriod.week:
        return 'Week';
      case DepreciationPeriod.month:
        return 'Month';
      case DepreciationPeriod.bimonth:
        return 'Bimonth';
      case DepreciationPeriod.year:
        return 'Year';
    }
  }
}

/// Plain model representing a row from v_assets_equipment.
class AssetRecord {
  final int id;
  final String? itemImage;
  final String itemType;
  final int quantity;
  final String? rfidCode;
  final String? barcode;
  final String department;
  final String employee;
  final double costPerItem;
  final double total;
  final String condition;
  final int? lifeSpan; // years (life_span from view)
  final double depreciationValueYear;
  final String encoder;
  final String? dateAcquired;
  final String? dateCreated;

  AssetRecord({
    required this.id,
    required this.itemImage,
    required this.itemType,
    required this.quantity,
    required this.rfidCode,
    required this.barcode,
    required this.department,
    required this.employee,
    required this.costPerItem,
    required this.total,
    required this.condition,
    required this.lifeSpan,
    required this.depreciationValueYear,
    required this.encoder,
    required this.dateAcquired,
    required this.dateCreated,
  });

  /// Build from SQLite map (view: v_assets_equipment).
 factory AssetRecord.fromRow(Map<String, Object?> r) {

  double toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is int) return v.toDouble();
    if (v is double) return v;
    return double.tryParse(v.toString()) ?? 0.0;
  }

  int? toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  String str(dynamic v) => (v?.toString() ?? '').trim();

  return AssetRecord(
    id: toInt(r['id']) ?? 0,
    itemImage: r['item_image']?.toString(),
    itemType: str(r['item_type']),
    quantity: toInt(r['quantity']) ?? 0,
    rfidCode: r['rfid_code']?.toString(),
    barcode: r['barcode']?.toString(),
    department: str(r['department']),
    employee: str(r['employee']),
    costPerItem: toDouble(r['cost_per_item']),
    total: toDouble(r['total']),
    condition: str(r['condition']),
    lifeSpan: toInt(r['life_span']),
    depreciationValueYear: toDouble(r['depreciation_value_year']),
    encoder: str(r['encoder']),
    dateAcquired: r['date_acquired']?.toString(),
    dateCreated: r['date_created']?.toString(),
  );
}


}

/// State holder for the Assets & Equipment screen.
class AssetsAndEquipmentsState extends ChangeNotifier {
  // ------------------ Filters / selections ------------------
  DepreciationPeriod _period = DepreciationPeriod.year;
  String _search = '';
  String _department = 'All Departments';
  String _condition = 'All Conditions';

  // ------------------ Data (raw + filtered) ------------------
  List<AssetRecord> _all = [];
  bool _loading = false;
  String? _error;

  // Dropdown sources (department/condition). Department list is built from data.
  // Conditions can be static or from data; we’ll merge both.
  final List<String> _baseDepartments = const ['All Departments'];

  final List<String> _baseConditions = const [
    'All Conditions',
    'Excellent',
    'Good',
    'Fair',
    'Poor',
  ];

  // ------------------ Public getters ------------------
  bool get isLoading => _loading;
  String? get error => _error;

  DepreciationPeriod get period => _period;
  String get search => _search;
  String get selectedDepartment => _department;
  String get selectedCondition => _condition;

  List<AssetRecord> get allAssets => _all;

  List<String> get departments {
    final dynamicDeps = _all.map((e) => e.department).where((e) => e.isNotEmpty).toSet().toList()
      ..sort();
    return {..._baseDepartments, ...dynamicDeps}.toList();
  }

  List<String> get conditions {
    final fromData = _all.map((e) => e.condition).where((e) => e.isNotEmpty).toSet().toList()
      ..sort();
    // put base first, then union (without duplicates)
    final merged = <String>[];
    for (final v in _baseConditions) {
      if (!merged.contains(v)) merged.add(v);
    }
    for (final v in fromData) {
      if (!merged.contains(v)) merged.add(v);
    }
    return merged;
  }

  /// Filtered list according to current search/department/condition.
  List<AssetRecord> get filteredAssets {
    final q = _search.trim().toLowerCase();
    return _all.where((a) {
      final matchesSearch =
          q.isEmpty ||
          a.itemType.toLowerCase().contains(q) ||
          a.employee.toLowerCase().contains(q) ||
          (a.rfidCode ?? '').toLowerCase().contains(q) ||
          (a.barcode ?? '').toLowerCase().contains(q);

      final matchesDept = (_department == 'All Departments') || a.department == _department;
      final matchesCond = (_condition == 'All Conditions') || a.condition == _condition;

      return matchesSearch && matchesDept && matchesCond;
    }).toList();
  }

  /// Total current value of filtered assets (using the depreciation rule of the selected period).
  double get totalCurrentValue {
    return filteredAssets.fold<double>(0.0, (sum, a) {
      return sum + currentValueFor(a);
    });
  }

  // ------------------ Mutations ------------------
  void setPeriod(DepreciationPeriod p) {
    if (_period == p) return;
    _period = p;
    notifyListeners();
  }

  void setSearch(String value) {
    _search = value;
    notifyListeners();
  }

  void setDepartment(String value) {
    _department = value;
    notifyListeners();
  }

  void setCondition(String value) {
    _condition = value;
    notifyListeners();
  }

  // ------------------ Data actions ------------------

  /// Load from local SQLite.
  ///
  /// We prefer the view `v_assets_equipment`. If it doesn’t exist yet,
  /// we fall back to a direct read from `assets_equipment`.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final db = await AppDb.get();

      // Detect if view exists
      final views = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='view' AND name='v_assets_equipment';",
      );

      List<Map<String, Object?>> rows;

      if (views.isNotEmpty) {
        rows = await db.rawQuery('SELECT * FROM v_assets_equipment;');
      } else {
        // Fallback: direct from assets_equipment with aliases matching the view.
        rows = await db.rawQuery('''
          SELECT
            id,
            item_image,
            item_type,
            COALESCE(quantity, 1) AS quantity,
            rfid_code,
            barcode,
            COALESCE(department, '') AS department,
            COALESCE(employee, '')   AS employee,
            cost_per_item,
            COALESCE(total, COALESCE(cost_per_item,0) * COALESCE(quantity,1)) AS total,
            COALESCE(condition, '') AS condition,
            life_span_years AS life_span,
            COALESCE(
              depreciation_value_year,
              CASE
                WHEN COALESCE(life_span_years,0) > 0
                  THEN COALESCE(total, COALESCE(cost_per_item,0) * COALESCE(quantity,1)) * 1.0 / life_span_years
                ELSE 0
              END
            ) AS depreciation_value_year,
            COALESCE(encoder,'') AS encoder,
            date_acquired,
            date_created
          FROM assets_equipment;
        ''');
      }

      _all = rows.map(AssetRecord.fromRow).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _loading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Convenience to force a reload (e.g., after sync).
  Future<void> refresh() => load();

  // ------------------ Business logic ------------------

  /// Compute current value using the rules:
  ///
  /// Day    : total_cost – (depreciation_value_year / 365)
  /// Week   : total_cost – (depreciation_value_year / 52)
  /// Month  : total_cost – (depreciation_value_year / 12)
  /// Bimonth: total_cost – (depreciation_value_year / 2)
  /// Year   : total_cost – depreciation_value_year
  ///
  /// Result is clamped to a minimum of 0.
  double currentValueFor(AssetRecord a) {
    final total = a.total;
    final depYear = a.depreciationValueYear;

    double stepDep;
    switch (_period) {
      case DepreciationPeriod.day:
        stepDep = depYear / 365.0;
        break;
      case DepreciationPeriod.week:
        stepDep = depYear / 52.0;
        break;
      case DepreciationPeriod.month:
        stepDep = depYear / 12.0;
        break;
      case DepreciationPeriod.bimonth:
        stepDep = depYear / 2.0;
        break;
      case DepreciationPeriod.year:
        stepDep = depYear;
        break;
    }

    final value = total - stepDep;
    return max(0.0, value);
  }
}
