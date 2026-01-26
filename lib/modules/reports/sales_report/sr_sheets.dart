part of "sr_view.dart";

/* ======================= PICKERS / FILTERS MIXIN ======================= */

mixin SalesReportSheetsMixin<T extends StatefulWidget> on State<T> {
  SalesReportState get state;

  void _showFilterDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PickerSheet(
        title: "Quick Filters",
        items: kPeriods,
        autoClose: false, // handler will close (prevents double-pop)
        onSelected: (value) => _handlePeriodSelect(context, value),
      ),
    );
  }

  // New period picker with tabs
  void _showPeriodSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PeriodPickerSheet(
        onPresetSelected: (value) => _handlePeriodSelect(context, value),
        onPickMonth: (year, month) {
          state.setMonth(year, month);
          Navigator.pop(context);
        },
        onPickRange: (DateTimeRange range) {
          state.setCustomRange(range.start, range.end);
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _handlePeriodSelect(BuildContext context, String value) async {
    if (value == "Custom") {
      final now = DateTime.now();
      final first = DateTime(now.year, now.month, 1);
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year + 3),
        initialDateRange: DateTimeRange(start: first, end: now),
        helpText: "Select custom period",
      );
      if (picked != null) {
        state.setCustomRange(picked.start, picked.end);
      }
    } else {
      state.setPeriod(value);
    }
    if (mounted) Navigator.pop(context);
  }

  void _showBranchPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PickerSheet(
        title: "Select Branch",
        items: state.branchOptions,
        onSelected: state.setBranch,
      ),
    );
  }

  void _showSalesmanPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PickerSheet(
        title: "Select Salesman",
        items: state.salesmanOptions,
        onSelected: state.setSalesman,
      ),
    );
  }

  void _showPaymentStatusPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PickerSheet(
        title: "Payment Status",
        items: state.paymentStatusOptions,
        onSelected: state.setPaymentStatus,
      ),
    );
  }

  // Supplier picker
  void _showSupplierPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PickerSheet(
        title: "Select Supplier",
        items: state.supplierOptions,
        onSelected: state.setSupplier,
      ),
    );
  }
}

/* ======================= SHEETS ======================= */

class _PickerSheet extends StatelessWidget {
  final String title;
  final List<String> items;
  final Function(String) onSelected;
  final bool autoClose;

  const _PickerSheet({
    required this.title,
    required this.items,
    required this.onSelected,
    this.autoClose = true,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(item, style: const TextStyle(fontSize: 14)),
                      dense: true,
                      onTap: () {
                        onSelected(item);
                        if (autoClose) Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Period picker with tabs ---
class _PeriodPickerSheet extends StatefulWidget {
  final void Function(String preset) onPresetSelected;
  final void Function(int year, int month) onPickMonth;
  final void Function(DateTimeRange range) onPickRange;

  const _PeriodPickerSheet({
    required this.onPresetSelected,
    required this.onPickMonth,
    required this.onPickRange,
  });

  @override
  State<_PeriodPickerSheet> createState() => _PeriodPickerSheetState();
}

class _PeriodPickerSheetState extends State<_PeriodPickerSheet> {
  late int _year;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
  }

  @override
  Widget build(BuildContext context) {
    final months = const [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];
    final maxH = MediaQuery.of(context).size.height * 0.8;

    return DefaultTabController(
      length: 3,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Text(
                    "Select Period",
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const TabBar(
              labelColor: Colors.black87,
              tabs: [
                Tab(text: "Presets"),
                Tab(text: "Month"),
                Tab(text: "Range"),
              ],
            ),
            const Divider(height: 1),

            // Content
            Expanded(
              child: TabBarView(
                children: [
                  // Presets
                  ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in kPeriods)
                        ListTile(
                          title: Text(p),
                          dense: true,
                          onTap: () => widget.onPresetSelected(p),
                        ),
                    ],
                  ),

                  // Month picker
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: "Previous Year",
                              onPressed: () => setState(() => _year--),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  "$_year",
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: "Next Year",
                              onPressed: () => setState(() => _year++),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.7,
                            ),
                            itemCount: 12,
                            itemBuilder: (_, i) {
                              final monthIdx = i + 1;
                              return OutlinedButton(
                                onPressed: () =>
                                    widget.onPickMonth(_year, monthIdx),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                                ),
                                child: Text(
                                  months[i],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Date range picker
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Pick a custom date range",
                            style: TextStyle(
                                fontSize: 14, color: Colors.black54),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.date_range),
                            label: const Text("Choose Date Range"),
                            onPressed: () async {
                              final now = DateTime.now();
                              final first = DateTime(now.year - 3, 1, 1);
                              final last = DateTime(now.year + 3, 12, 31);
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: first,
                                lastDate: last,
                                helpText: "Select custom period",
                              );
                              if (picked != null) {
                                widget.onPickRange(picked);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
