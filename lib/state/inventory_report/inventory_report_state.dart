import "package:flutter/material.dart";

/// State for the Inventory (Running Inventory) report.
///
/// UI-friendly:
/// - Holds raw rows
/// - Holds loading/error
/// - Holds current filters (optional - wire later)
@immutable
class InventoryReportState {
  final bool loading;
  final String? error;

  final List<RunningInventoryRow> rows;

  // Optional filters (wire later)
  final String searchQuery;
  final DateTimeRange? cutoffRange;
  final int? branchId;
  final int? supplierId;

  const InventoryReportState({
    required this.loading,
    required this.error,
    required this.rows,
    required this.searchQuery,
    required this.cutoffRange,
    required this.branchId,
    required this.supplierId,
  });

  factory InventoryReportState.initial() {
    return const InventoryReportState(
      loading: true,
      error: null,
      rows: [],
      searchQuery: "",
      cutoffRange: null,
      branchId: null,
      supplierId: null,
    );
  }

  InventoryReportState copyWith({
    bool? loading,
    String? error,
    List<RunningInventoryRow>? rows,
    String? searchQuery,
    DateTimeRange? cutoffRange,
    int? branchId,
    int? supplierId,
    bool clearError = false,
  }) {
    return InventoryReportState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      rows: rows ?? this.rows,
      searchQuery: searchQuery ?? this.searchQuery,
      cutoffRange: cutoffRange ?? this.cutoffRange,
      branchId: branchId ?? this.branchId,
      supplierId: supplierId ?? this.supplierId,
    );
  }
}

/// Model aligned to v_running_inventory columns.
@immutable
class RunningInventoryRow {
  final String id; // concat(branch_id, '-', product_id, '-', supplier_id)
  final int productId;
  final String productCode;
  final String productName;
  final String unitName;
  final num unitCount;
  final int branchId;
  final String branchName;
  final DateTime lastCutoff;
  final num lastCount;
  final num movementAfter;
  final num runningInventory;
  final String supplierShortcut;
  final int supplierId;

  const RunningInventoryRow({
    required this.id,
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.unitName,
    required this.unitCount,
    required this.branchId,
    required this.branchName,
    required this.lastCutoff,
    required this.lastCount,
    required this.movementAfter,
    required this.runningInventory,
    required this.supplierShortcut,
    required this.supplierId,
  });

  factory RunningInventoryRow.fromDb(Map<String, Object?> m) {
    int asInt(Object? v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    num asNum(Object? v) {
      if (v == null) return 0;
      if (v is num) return v;
      return double.tryParse(v.toString()) ?? 0;
    }

    String asStr(Object? v) => (v ?? "").toString();

    DateTime parseDate(Object? v) {
      final s = asStr(v).trim();
      if (s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
      return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    return RunningInventoryRow(
      id: asStr(m["id"]),
      productId: asInt(m["product_id"]),
      productCode: asStr(m["product_code"]),
      productName: asStr(m["product_name"]),
      unitName: asStr(m["unit_name"]),
      unitCount: asNum(m["unit_count"]),
      branchId: asInt(m["branch_id"]),
      branchName: asStr(m["branch_name"]),
      lastCutoff: parseDate(m["last_cutoff"]),
      lastCount: asNum(m["last_count"]),
      movementAfter: asNum(m["movement_after"]),
      runningInventory: asNum(m["running_inventory"]),
      supplierShortcut: asStr(m["supplier_shortcut"]),
      supplierId: asInt(m["supplier_id"]),
    );
  }
}

/// Simple stats helper (for KPI cards).
@immutable
class RunningStats {
  final int rowCount;
  final num totalRunning;
  final num totalMovementAfter;
  final num totalLastCount;
  final int distinctProducts;
  final int distinctCutoffs;
  final DateTime? earliestCutoff;
  final DateTime? latestCutoff;

  const RunningStats({
    required this.rowCount,
    required this.totalRunning,
    required this.totalMovementAfter,
    required this.totalLastCount,
    required this.distinctProducts,
    required this.distinctCutoffs,
    required this.earliestCutoff,
    required this.latestCutoff,
  });

  static RunningStats empty() {
    return const RunningStats(
      rowCount: 0,
      totalRunning: 0,
      totalMovementAfter: 0,
      totalLastCount: 0,
      distinctProducts: 0,
      distinctCutoffs: 0,
      earliestCutoff: null,
      latestCutoff: null,
    );
  }

  static RunningStats fromRows(List<RunningInventoryRow> rows) {
    if (rows.isEmpty) return RunningStats.empty();

    num totalRunning = 0;
    num totalMove = 0;
    num totalLast = 0;

    final productSet = <int>{};
    final cutoffSet = <String>{};

    DateTime? minCut;
    DateTime? maxCut;

    for (final r in rows) {
      totalRunning += r.runningInventory;
      totalMove += r.movementAfter;
      totalLast += r.lastCount;

      productSet.add(r.productId);

      // Normalize cutoff to date-string granularity for distinct count
      final key = "${r.lastCutoff.year.toString().padLeft(4, "0")}-"
          "${r.lastCutoff.month.toString().padLeft(2, "0")}-"
          "${r.lastCutoff.day.toString().padLeft(2, "0")}";
      cutoffSet.add(key);

      if (r.lastCutoff.millisecondsSinceEpoch > 0) {
        minCut = (minCut == null || r.lastCutoff.isBefore(minCut)) ? r.lastCutoff : minCut;
        maxCut = (maxCut == null || r.lastCutoff.isAfter(maxCut)) ? r.lastCutoff : maxCut;
      }
    }

    return RunningStats(
      rowCount: rows.length,
      totalRunning: totalRunning,
      totalMovementAfter: totalMove,
      totalLastCount: totalLast,
      distinctProducts: productSet.length,
      distinctCutoffs: cutoffSet.length,
      earliestCutoff: minCut,
      latestCutoff: maxCut,
    );
  }
}
