import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/local/app_db.dart';

/// Depreciation period options (must match your UI labels)
enum DepreciationPeriod { day, week, month, bimonth, year }

extension DepreciationPeriodExt on DepreciationPeriod {
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

/// Filters state (search + dropdowns + depreciation period)
@immutable
class AssetsFilters {
  final String search;
  final String department; // 'All Departments' sentinel means no filter
  final String condition;  // 'All Conditions' sentinel means no filter
  final DepreciationPeriod period;

  const AssetsFilters({
    this.search = '',
    this.department = 'All Departments',
    this.condition = 'All Conditions',
    this.period = DepreciationPeriod.year,
  });

  AssetsFilters copyWith({
    String? search,
    String? department,
    String? condition,
    DepreciationPeriod? period,
  }) {
    return AssetsFilters(
      search: search ?? this.search,
      department: department ?? this.department,
      condition: condition ?? this.condition,
      period: period ?? this.period,
    );
  }
}

/// Notifier for filters
class AssetsFiltersNotifier extends Notifier<AssetsFilters> {
  @override
  AssetsFilters build() => const AssetsFilters();

  void setSearch(String s) => state = state.copyWith(search: s);
  void setDepartment(String d) => state = state.copyWith(department: d);
  void setCondition(String c) => state = state.copyWith(condition: c);
  void setPeriod(DepreciationPeriod p) => state = state.copyWith(period: p);
}

final assetsFiltersProvider =
NotifierProvider<AssetsFiltersNotifier, AssetsFilters>(
      () => AssetsFiltersNotifier(),
);

/// Row model mirroring v_assets_equipment
@immutable
class AssetRow {
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
  final int? lifeSpan; // life_span (years) from view
  final double depreciationValueYear; // total / life_span_years (from view)
  final String encoder;
  final String? dateAcquired;
  final String? dateCreated;

  const AssetRow({
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

  factory AssetRow.fromDb(Map<String, Object?> r) {
    double _num(Object? v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int? _intN(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    String _str(Object? v) => (v?.toString() ?? '').trim();

    return AssetRow(
      id: _intN(r['id']) ?? 0,
      itemImage: r['item_image']?.toString(),
      itemType: _str(r['item_type']),
      quantity: _intN(r['quantity']) ?? 0,
      rfidCode: r['rfid_code']?.toString(),
      barcode: r['barcode']?.toString(),
      department: _str(r['department']),
      employee: _str(r['employee']),
      costPerItem: _num(r['cost_per_item']),
      total: _num(r['total']),
      condition: _str(r['condition']),
      lifeSpan: _intN(r['life_span']),
      depreciationValueYear: _num(r['depreciation_value_year']),
      encoder: _str(r['encoder']),
      dateAcquired: r['date_acquired']?.toString(),
      dateCreated: r['date_created']?.toString(),
    );
  }
}

/// Loads ALL rows from local SQLite (view first, fallback to base table)
final assetsAllRowsProvider = FutureProvider<List<AssetRow>>((ref) async {
  final Database db = await AppDb.get();

  // Does the view exist?
  final viewExists = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='view' AND name='v_assets_equipment';",
  );

  List<Map<String, Object?>> rows;
  if (viewExists.isNotEmpty) {
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

  return rows.map(AssetRow.fromDb).toList();
});

/// Apply filters (search/department/condition) to rows
final assetsRowsProvider = FutureProvider<List<AssetRow>>((ref) async {
  final filters = ref.watch(assetsFiltersProvider);
  final all = await ref.watch(assetsAllRowsProvider.future);

  final q = filters.search.trim().toLowerCase();
  return all.where((a) {
    final matchesSearch = q.isEmpty ||
        a.itemType.toLowerCase().contains(q) ||
        a.employee.toLowerCase().contains(q) ||
        (a.rfidCode ?? '').toLowerCase().contains(q) ||
        (a.barcode ?? '').toLowerCase().contains(q);

    final matchesDept =
        (filters.department == 'All Departments') || a.department == filters.department;
    final matchesCond =
        (filters.condition == 'All Conditions') || a.condition == filters.condition;

    return matchesSearch && matchesDept && matchesCond;
  }).toList();
});

/// Distinct departments (with 'All Departments' first)
final assetsDepartmentsProvider = FutureProvider<List<String>>((ref) async {
  final all = await ref.watch(assetsAllRowsProvider.future);
  final set = <String>{};
  for (final r in all) {
    if (r.department.trim().isNotEmpty) set.add(r.department.trim());
  }
  final list = set.toList()..sort();
  return ['All Departments', ...list];
});

/// Distinct conditions (with 'All Conditions' first)
final assetsConditionsProvider = FutureProvider<List<String>>((ref) async {
  final all = await ref.watch(assetsAllRowsProvider.future);
  final set = <String>{};
  for (final r in all) {
    if (r.condition.trim().isNotEmpty) set.add(r.condition.trim());
  }
  final list = set.toList()..sort();
  return ['All Conditions', ...list];
});

/// Helper: compute current value given period (clamped >= 0)
double _currentValue({
  required double total,
  required double depreciationYear,
  required DepreciationPeriod period,
}) {
  double step;
  switch (period) {
    case DepreciationPeriod.day:
      step = depreciationYear / 365.0;
      break;
    case DepreciationPeriod.week:
      step = depreciationYear / 52.0;
      break;
    case DepreciationPeriod.month:
      step = depreciationYear / 12.0;
      break;
    case DepreciationPeriod.bimonth:
      step = depreciationYear / 2.0;
      break;
    case DepreciationPeriod.year:
      step = depreciationYear;
      break;
  }
  return max(0.0, total - step);
}

/// Aggregated metrics for the list
@immutable
class AssetsMetrics {
  final int count;
  final double currentTotalValue;

  const AssetsMetrics({
    required this.count,
    required this.currentTotalValue,
  });
}

/// Computes metrics for the **filtered** rows (uses selected depreciation period)
final assetsMetricsProvider = FutureProvider<AssetsMetrics>((ref) async {
  final filters = ref.watch(assetsFiltersProvider);
  final rows = await ref.watch(assetsRowsProvider.future);

  double total = 0.0;
  for (final a in rows) {
    total += _currentValue(
      total: a.total,
      depreciationYear: a.depreciationValueYear,
      period: filters.period,
    );
  }

  return AssetsMetrics(
    count: rows.length,
    currentTotalValue: total,
  );
});
