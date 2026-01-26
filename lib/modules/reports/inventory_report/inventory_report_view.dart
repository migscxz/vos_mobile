import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:getwidget/getwidget.dart";
import "package:intl/intl.dart";

import "package:vos_mobile/state/inventory_report/inventory_providers.dart";
import "package:vos_mobile/state/inventory_report/inventory_report_state.dart";

class InventoryView extends ConsumerStatefulWidget {
  const InventoryView({Key? key}) : super(key: key);

  @override
  ConsumerState<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends ConsumerState<InventoryView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Filters aligned to v_running_inventory
  String _searchQuery = "";
  DateTimeRange? _cutoffRange;

  String _selectedBranchLabel = "All Branches";
  String _selectedSupplierLabel = "All Suppliers";

  // Derived lists (computed from provider rows)
  List<RunningInventoryRow> _filteredRows = [];

  // Dropdown labels to ids
  Map<String, int?> _branchLabelToId = const {"All Branches": null};
  Map<String, int?> _supplierLabelToId = const {"All Suppliers": null};

  int? get _selectedBranchId => _branchLabelToId[_selectedBranchLabel];
  int? get _selectedSupplierId => _supplierLabelToId[_selectedSupplierLabel];

  Timer? _searchDebounce;

  // ✅ Caching (prevents heavy recompute on every build)
  int _lastRowsHash = 0;
  String _lastFilterSig = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(inventoryReportProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------
  // Filtering + options (pure)
  // ---------------------------

  String _filterSig() {
    final rangeSig = _cutoffRange == null
        ? "null"
        : "${_cutoffRange!.start.millisecondsSinceEpoch}-${_cutoffRange!.end.millisecondsSinceEpoch}";
    return "${_searchQuery.trim()}|$_selectedBranchLabel|$_selectedSupplierLabel|$rangeSig";
  }

  int _rowsHash(List<RunningInventoryRow> rows) {
    // Stable enough: hash IDs only (cheap)
    return Object.hashAll(rows.map((e) => e.id));
  }

  Map<String, int?> _buildBranchOptions(List<RunningInventoryRow> rows) {
    final map = <String, int?>{"All Branches": null};
    for (final r in rows) {
      final name = r.branchName.trim();
      if (name.isEmpty) continue;
      map[name] = r.branchId;
    }
    return map;
  }

  Map<String, int?> _buildSupplierOptions(List<RunningInventoryRow> rows) {
    final map = <String, int?>{"All Suppliers": null};
    for (final r in rows) {
      final label = r.supplierShortcut.trim().isEmpty
          ? "No Supplier"
          : r.supplierShortcut.trim();
      map[label] = (r.supplierId == 0) ? null : r.supplierId;
    }
    return map;
  }

  List<RunningInventoryRow> _filterRows(List<RunningInventoryRow> allRows) {
    final q = _searchQuery.trim().toLowerCase();
    final branchId = _selectedBranchId;
    final supplierId = _selectedSupplierId;

    final cutoffStart = _cutoffRange?.start;
    final cutoffEnd = _cutoffRange?.end;

    bool inCutoffRange(DateTime cutoff) {
      if (cutoffStart == null || cutoffEnd == null) return true;
      final c = DateTime(cutoff.year, cutoff.month, cutoff.day);
      final s = DateTime(cutoffStart.year, cutoffStart.month, cutoffStart.day);
      final e = DateTime(cutoffEnd.year, cutoffEnd.month, cutoffEnd.day);
      return (c.isAtSameMomentAs(s) || c.isAfter(s)) &&
          (c.isAtSameMomentAs(e) || c.isBefore(e));
    }

    final out = allRows.where((r) {
      if (branchId != null && r.branchId != branchId) return false;
      if (supplierId != null && r.supplierId != supplierId) return false;

      if (!inCutoffRange(r.lastCutoff)) return false;

      if (q.isEmpty) return true;

      final supplier = r.supplierShortcut.toLowerCase();
      return r.productName.toLowerCase().contains(q) ||
          r.productCode.toLowerCase().contains(q) ||
          r.branchName.toLowerCase().contains(q) ||
          supplier.contains(q);
    }).toList();

    // Enforce ordering (branch_name, product_name)
    out.sort((a, b) {
      final byBranch = a.branchName.compareTo(b.branchName);
      if (byBranch != 0) return byBranch;
      return a.productName.compareTo(b.productName);
    });

    return out;
  }

  void _recomputeDerived(List<RunningInventoryRow> providerRows) {
    final branchMap = _buildBranchOptions(providerRows);
    final supplierMap = _buildSupplierOptions(providerRows);

    if (!branchMap.containsKey(_selectedBranchLabel)) {
      _selectedBranchLabel = "All Branches";
    }
    if (!supplierMap.containsKey(_selectedSupplierLabel)) {
      _selectedSupplierLabel = "All Suppliers";
    }

    _branchLabelToId = branchMap;
    _supplierLabelToId = supplierMap;

    _filteredRows = _filterRows(providerRows);
  }

  // ---------------------------
  // Actions
  // ---------------------------

  void _refreshData() async {
    GFToast.showToast(
      "Refreshing running inventory...",
      context,
      toastPosition: GFToastPosition.BOTTOM,
      textStyle: const TextStyle(color: Colors.white),
    );
    await ref.read(inventoryReportProvider.notifier).refresh();
  }

  void _exportData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Export Running Inventory"),
        content: const Text(
          "Export will use v_running_inventory columns:\n"
              "branch_name, product_code, product_name, unit_name, unit_count, "
              "last_cutoff, last_count, movement_after, running_inventory, supplier_shortcut",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              GFToast.showToast(
                "Exporting to Excel...",
                context,
                toastPosition: GFToastPosition.BOTTOM,
              );
            },
            child: const Text("Excel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              GFToast.showToast(
                "Exporting to PDF...",
                context,
                toastPosition: GFToastPosition.BOTTOM,
              );
            },
            child: const Text("PDF"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // Build
  // ---------------------------

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(inventoryReportProvider);

    // ✅ Only recompute derived data when input rows or filter inputs changed
    final rowsHash = _rowsHash(report.rows);
    final sig = _filterSig();
    final shouldRecompute = rowsHash != _lastRowsHash || sig != _lastFilterSig;

    if (shouldRecompute) {
      _lastRowsHash = rowsHash;
      _lastFilterSig = sig;
      _recomputeDerived(report.rows);
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          "Running Inventory",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.black87),
            onPressed: _exportData,
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: const [
                Tab(text: "Overview"),
                Tab(text: "Movements"),
                Tab(text: "Analytics"),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildFilterSection(),
          Expanded(
            child: report.loading
                ? const Center(child: CircularProgressIndicator())
                : report.error != null
                ? _buildErrorState(report.error!)
                : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildMovementsTab(),
                _buildAnalyticsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // UI Pieces
  // ---------------------------

  Widget _buildErrorState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            const Text(
              "Failed to load running inventory",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            GFButton(
              onPressed: () => ref.read(inventoryReportProvider.notifier).load(),
              text: "Retry",
              icon: const Icon(Icons.refresh, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    final branches = _branchLabelToId.keys.toList()..sort();
    final suppliers = _supplierLabelToId.keys.toList()..sort();

    final showClear = _cutoffRange != null ||
        _searchQuery.trim().isNotEmpty ||
        _selectedBranchLabel != "All Branches" ||
        _selectedSupplierLabel != "All Suppliers";

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            onChanged: (v) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 180), () {
                if (!mounted) return;
                setState(() {
                  _searchQuery = v;
                });
              });
            },
            decoration: InputDecoration(
              hintText: "Search product code/name, branch, supplier...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  icon: Icons.calendar_today,
                  label: _cutoffRange == null
                      ? "Cutoff Range"
                      : "${DateFormat("MMM d").format(_cutoffRange!.start)} - ${DateFormat("MMM d").format(_cutoffRange!.end)}",
                  onTap: _selectCutoffRange,
                ),
                const SizedBox(width: 8),
                _buildDropdownChip(
                  icon: Icons.store,
                  value: _selectedBranchLabel,
                  items: branches,
                  onChanged: (value) {
                    setState(() {
                      _selectedBranchLabel = value ?? "All Branches";
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildDropdownChip(
                  icon: Icons.business,
                  value: _selectedSupplierLabel,
                  items: suppliers,
                  onChanged: (value) {
                    setState(() {
                      _selectedSupplierLabel = value ?? "All Suppliers";
                    });
                  },
                ),
                const SizedBox(width: 8),
                if (showClear)
                  GFButton(
                    onPressed: () {
                      setState(() {
                        _searchQuery = "";
                        _cutoffRange = null;
                        _selectedBranchLabel = "All Branches";
                        _selectedSupplierLabel = "All Suppliers";
                      });
                    },
                    text: "Clear",
                    icon: const Icon(Icons.close, size: 16),
                    size: GFSize.SMALL,
                    type: GFButtonType.outline2x,
                    shape: GFButtonShape.pills,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GFButton(
      onPressed: onTap,
      text: label,
      icon: Icon(icon, size: 16),
      size: GFSize.SMALL,
      type: GFButtonType.outline2x,
      shape: GFButtonShape.pills,
    );
  }

  Widget _buildDropdownChip({
    required IconData icon,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    final safeValue =
    items.contains(value) ? value : (items.isNotEmpty ? items.first : value);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 4),
          DropdownButton<String>(
            value: safeValue,
            underline: const SizedBox(),
            items: items
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // Tabs
  // ---------------------------

  Widget _buildOverviewTab() {
    final stats = _computeStats(_filteredRows);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  "Running Inventory",
                  _fmtNumber(stats.totalRunning),
                  "base qty",
                  Colors.blue,
                  Icons.inventory_2,
                  "Rows: ${stats.rowCount}",
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  "Movement After",
                  _fmtSigned(stats.totalMovementAfter),
                  "net since cutoff",
                  stats.totalMovementAfter >= 0 ? Colors.green : Colors.red,
                  Icons.compare_arrows,
                  "Cutoffs: ${stats.distinctCutoffs}",
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  "Last Count",
                  _fmtNumber(stats.totalLastCount),
                  "base qty",
                  Colors.purple,
                  Icons.fact_check,
                  "Products: ${stats.distinctProducts}",
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  "Latest Cutoff",
                  stats.latestCutoff == null
                      ? "-"
                      : DateFormat("MMM dd, yyyy").format(stats.latestCutoff!),
                  "date",
                  Colors.orange,
                  Icons.calendar_month,
                  stats.latestCutoff == null
                      ? "-"
                      : "Earliest: ${DateFormat("MMM dd").format(stats.earliestCutoff!)}",
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader("Running Inventory Rows"),
          const SizedBox(height: 12),

          // ✅ HUGE PERF FIX: lazy list instead of Column(map(...))
          if (_filteredRows.isEmpty)
            _buildEmptyState()
          else
            SizedBox(
              // keeps the scroll from fighting with the outer SingleChildScrollView
              height: MediaQuery.of(context).size.height * 0.62,
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: _filteredRows.length,
                itemBuilder: (context, index) {
                  return _buildRunningInventoryCard(_filteredRows[index]);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMovementsTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Movement After Cutoff",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              GFButton(
                onPressed: _exportData,
                text: "Export",
                icon: const Icon(Icons.download, size: 16),
                size: GFSize.SMALL,
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredRows.isEmpty
              ? ListView(
            padding: const EdgeInsets.all(16),
            children: [_buildEmptyState()],
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _filteredRows.length,
            itemBuilder: (context, index) =>
                _buildMovementRowCard(_filteredRows[index]),
          ),
        ),
      ],
    );
  }

  // ✅ Lightweight top-N helper: avoids sorting huge lists repeatedly
  List<RunningInventoryRow> _topN(
      List<RunningInventoryRow> rows,
      int n,
      int Function(RunningInventoryRow a, RunningInventoryRow b) compare,
      ) {
    if (rows.isEmpty) return const [];
    if (rows.length <= n) {
      final out = [...rows]..sort(compare);
      return out;
    }
    final out = [...rows]..sort(compare);
    return out.take(n).toList();
  }

  Widget _buildAnalyticsTab() {
    final topRunningTake = _topN(
      _filteredRows,
      5,
          (a, b) => b.runningInventory.compareTo(a.runningInventory),
    );

    final topMoversTake = _topN(
      _filteredRows,
      5,
          (a, b) => b.movementAfter.abs().compareTo(a.movementAfter.abs()),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader("Top by Running Inventory"),
          const SizedBox(height: 12),
          if (topRunningTake.isEmpty)
            _buildEmptyState()
          else
            Column(
              children: topRunningTake
                  .map((r) => _buildTopRowCard(
                title: r.productName,
                subtitle: "${r.branchName} • ${r.productCode}",
                trailing: _fmtNumber(r.runningInventory),
                trailingLabel: "run inv",
                color: Colors.blue,
              ))
                  .toList(),
            ),
          const SizedBox(height: 24),
          _buildSectionHeader("Top Movers (Abs Movement After Cutoff)"),
          const SizedBox(height: 12),
          if (topMoversTake.isEmpty)
            _buildEmptyState()
          else
            Column(
              children: topMoversTake.map((r) {
                final c = r.movementAfter >= 0 ? Colors.green : Colors.red;
                return _buildTopRowCard(
                  title: r.productName,
                  subtitle:
                  "${r.branchName} • Cutoff ${DateFormat("MMM dd").format(r.lastCutoff)}",
                  trailing: _fmtSigned(r.movementAfter),
                  trailingLabel: "movement",
                  color: c,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ---------------------------
  // Cards
  // ---------------------------

  Widget _buildEmptyState() {
    return GFCard(
      elevation: 1,
      content: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.inbox_outlined, color: Colors.grey[500]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "No rows matched your filters.",
                style: TextStyle(color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunningInventoryCard(RunningInventoryRow r) {
    final movementColor = r.movementAfter >= 0 ? Colors.green : Colors.red;
    final supplierLabel =
    r.supplierShortcut.isEmpty ? "No Supplier" : r.supplierShortcut;

    return GFCard(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      content: InkWell(
        onTap: () => _showRunningInventoryDetails(r),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: movementColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  r.movementAfter >= 0
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  color: movementColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.productName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${r.productCode} • ${r.branchName} • $supplierLabel",
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.straighten,
                            size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          "${r.unitName} (x${r.unitCount})",
                          style:
                          TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.calendar_today,
                            size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          "Cutoff: ${r.lastCutoff.millisecondsSinceEpoch == 0 ? "-" : DateFormat("MMM dd, yyyy").format(r.lastCutoff)}",
                          style:
                          TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtNumber(r.runningInventory),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "run inv (base)",
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: movementColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: movementColor.withOpacity(0.25)),
                    ),
                    child: Text(
                      "Δ ${_fmtSigned(r.movementAfter)}",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: movementColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMovementRowCard(RunningInventoryRow r) {
    final movementColor = r.movementAfter >= 0 ? Colors.green : Colors.red;

    return GFCard(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      content: InkWell(
        onTap: () => _showRunningInventoryDetails(r),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: movementColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.compare_arrows, color: movementColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.productName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${r.branchName} • Cutoff ${r.lastCutoff.millisecondsSinceEpoch == 0 ? "-" : DateFormat("MMM dd, yyyy").format(r.lastCutoff)}",
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _miniPill(
                            label: "Last: ${_fmtNumber(r.lastCount)}",
                            color: Colors.purple),
                        const SizedBox(width: 8),
                        _miniPill(
                            label: "Run: ${_fmtNumber(r.runningInventory)}",
                            color: Colors.blue),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtSigned(r.movementAfter),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: movementColor,
                    ),
                  ),
                  Text(
                    "movement",
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMetricCard(
      String title,
      String value,
      String unit,
      Color color,
      IconData icon,
      String change,
      ) {
    return GFCard(
      elevation: 2,
      boxFit: BoxFit.cover,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(unit, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  change,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopRowCard({
    required String title,
    required String subtitle,
    required String trailing,
    required String trailingLabel,
    required Color color,
  }) {
    return GFCard(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      content: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bar_chart, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trailing,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: color,
                ),
              ),
              Text(
                trailingLabel,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  // ---------------------------
  // Details Sheet
  // ---------------------------

  void _showRunningInventoryDetails(RunningInventoryRow r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.50,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Running Inventory Details",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              _buildDetailRow("Branch", "${r.branchName} (#${r.branchId})"),
              _buildDetailRow("Product", r.productName),
              _buildDetailRow("Product Code", r.productCode),
              _buildDetailRow("Product ID", "${r.productId}"),
              _buildDetailRow(
                "Supplier",
                r.supplierShortcut.isEmpty
                    ? "No Supplier (supplier_id=0)"
                    : "${r.supplierShortcut} (#${r.supplierId})",
              ),
              _buildDetailRow("Unit", "${r.unitName} (count=${r.unitCount})"),
              const Divider(height: 28),
              _buildDetailRow(
                "Last Cutoff",
                r.lastCutoff.millisecondsSinceEpoch == 0
                    ? "-"
                    : DateFormat("MMMM dd, yyyy").format(r.lastCutoff),
              ),
              _buildDetailRow("Last Count", _fmtNumber(r.lastCount)),
              _buildDetailRow("Movement After", _fmtSigned(r.movementAfter)),
              _buildDetailRow("Running Inventory", _fmtNumber(r.runningInventory)),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: GFButton(
                      onPressed: () => Navigator.pop(context),
                      text: "Close",
                      type: GFButtonType.outline,
                      size: GFSize.LARGE,
                      fullWidthButton: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectCutoffRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _cutoffRange,
    );

    if (picked != null) {
      setState(() {
        _cutoffRange = picked;
      });
    }
  }

  // ---------------------------
  // Helpers
  // ---------------------------

  String _fmtNumber(num n) => NumberFormat("#,##0.##").format(n);

  String _fmtSigned(num n) {
    final s = NumberFormat("#,##0.##").format(n.abs());
    return n >= 0 ? "+$s" : "-$s";
  }

  RunningStats _computeStats(List<RunningInventoryRow> rows) {
    if (rows.isEmpty) return RunningStats.empty();

    num totalRunning = 0;
    num totalMovementAfter = 0;
    num totalLastCount = 0;

    final productIds = <int>{};
    final cutoffDates = <String>{};

    DateTime? earliest;
    DateTime? latest;

    for (final r in rows) {
      totalRunning += r.runningInventory;
      totalMovementAfter += r.movementAfter;
      totalLastCount += r.lastCount;

      productIds.add(r.productId);
      cutoffDates.add(DateFormat("yyyy-MM-dd").format(r.lastCutoff));

      earliest = earliest == null || r.lastCutoff.isBefore(earliest) ? r.lastCutoff : earliest;
      latest = latest == null || r.lastCutoff.isAfter(latest) ? r.lastCutoff : latest;
    }

    return RunningStats(
      rowCount: rows.length,
      totalRunning: totalRunning,
      totalMovementAfter: totalMovementAfter,
      totalLastCount: totalLastCount,
      distinctProducts: productIds.length,
      distinctCutoffs: cutoffDates.length,
      earliestCutoff: earliest,
      latestCutoff: latest,
    );
  }
}
