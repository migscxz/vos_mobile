// lib/modules/disbursement/disbursement_view.dart
import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:getwidget/getwidget.dart";
import "package:intl/intl.dart";

import "package:vos_mobile/state/disbursement/disbursement_providers.dart";
import "package:vos_mobile/state/disbursement/disbursement_state.dart";
import "package:vos_mobile/modules/reports/disbursement/coa_graph.dart";

class DisbursementView extends ConsumerStatefulWidget {
  const DisbursementView({Key? key}) : super(key: key);

  @override
  ConsumerState<DisbursementView> createState() => _DisbursementViewState();
}

class _DisbursementViewState extends ConsumerState<DisbursementView> {
  String _selectedFilterLabel = "All";
  final List<String> _filterOptions = const [
    "All",
    "Trade",
    "Non-Trade",
    "Posted",
    "Unpaid",
  ];

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      // Rebuild to toggle suffix clear button visibility.
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(disbursementControllerProvider.notifier).setSearch(value.trim());
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(disbursementControllerProvider.notifier).setSearch("");
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(disbursementControllerProvider);
    final dataState = asyncState.asData?.value;

    final currentFilterLabel =
        dataState?.query.filter.label ?? _selectedFilterLabel;

    final totalDisbursement = dataState?.totalDisbursement ?? 0.0;
    final totalGroups = dataState?.totalGroups ?? 0;
    final totalItems = dataState?.totalItems ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          "Disbursement Report",
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon:
            const Icon(Icons.bar_chart_rounded, color: Color(0xFF6366F1)),
            tooltip: "COA Analytics",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CoaGraphsView()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined,
                color: Color(0xFF6366F1)),
            onPressed: () => _showSnackbar("Export feature"),
          ),
          IconButton(
            icon:
            const Icon(Icons.print_outlined, color: Color(0xFF6366F1)),
            onPressed: () => _showSnackbar("Print feature"),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final isTablet = w >= 720;
          final isCompact = w < 420;

          final slivers = <Widget>[
            SliverToBoxAdapter(
              child: _buildSummaryCards(
                isTablet: isTablet,
                loading: asyncState.isLoading,
                totalDisbursement: totalDisbursement,
                totalGroups: totalGroups,
                totalItems: totalItems,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: _buildSearchAndDateFilter(
                isTablet: isTablet,
                isCompact: isCompact,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: _buildFilterChips(currentFilterLabel),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ];

          final contentSlivers = asyncState.when(
            loading: () => <Widget>[_buildLoadingSliverList()],
            error: (e, _) => <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildErrorState(e.toString()),
              ),
            ],
            data: (s) {
              if (s.groups.isEmpty) {
                return <Widget>[
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  ),
                ];
              }

              return <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildDisbursementCard(
                        s.groups[index],
                        isTablet: isTablet,
                        isCompact: isCompact,
                      ),
                      childCount: s.groups.length,
                    ),
                  ),
                ),
              ];
            },
          );

          slivers.addAll(contentSlivers);

          return Scrollbar(
            thumbVisibility: isTablet,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: slivers,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards({
    required bool isTablet,
    required bool loading,
    required double totalDisbursement,
    required int totalGroups,
    required int totalItems,
  }) {
    Widget totalCard() {
      return GFCard(
        elevation: 0,
        color: const Color(0xFF6366F1),
        padding: const EdgeInsets.all(20),
        boxFit: BoxFit.cover,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Total Disbursement",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              loading ? "—" : "₱${_formatAmount(totalDisbursement)}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    Widget txnCard() {
      return GFCard(
        elevation: 0,
        color: const Color(0xFF10B981),
        padding: const EdgeInsets.all(20),
        boxFit: BoxFit.cover,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Transactions",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              loading ? "—" : "$totalGroups DVs",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              loading ? "" : "$totalItems line items",
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: isTablet
          ? Row(
        children: [
          Expanded(child: totalCard()),
          const SizedBox(width: 12),
          Expanded(child: txnCard()),
        ],
      )
          : Column(
        children: [
          totalCard(),
          const SizedBox(height: 12),
          txnCard(),
        ],
      ),
    );
  }

  Widget _buildSearchAndDateFilter({
    required bool isTablet,
    required bool isCompact,
  }) {
    Widget searchField() {
      return TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: "Search by DV No, Payee, Reference, Account...",
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300] ?? Colors.grey),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300] ?? Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
          ),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6366F1)),
          suffixIcon: _searchController.text.trim().isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear, color: Colors.grey),
            onPressed: _clearSearch,
          )
              : null,
          filled: true,
          fillColor: Colors.grey[50] ?? Colors.grey.shade50,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
    }

    Widget dateButtons() {
      final startBtn = GFButton(
        onPressed: () => _selectStartDate(context),
        text: _startDate == null
            ? "Start Date"
            : DateFormat('MMM dd, yyyy').format(_startDate!),
        icon: Icon(
          Icons.calendar_today,
          size: 16,
          color: _startDate == null ? Colors.grey.shade700 : Colors.white,
        ),
        color:
        _startDate == null ? Colors.grey.shade200 : const Color(0xFF6366F1),
        textColor: _startDate == null ? Colors.grey.shade700 : Colors.white,
        shape: GFButtonShape.standard,
        size: GFSize.MEDIUM,
        fullWidthButton: true,
      );

      final endBtn = GFButton(
        onPressed: () => _selectEndDate(context),
        text: _endDate == null
            ? "End Date"
            : DateFormat('MMM dd, yyyy').format(_endDate!),
        icon: Icon(
          Icons.calendar_today,
          size: 16,
          color: _endDate == null ? Colors.grey.shade700 : Colors.white,
        ),
        color:
        _endDate == null ? Colors.grey.shade200 : const Color(0xFF6366F1),
        textColor: _endDate == null ? Colors.grey.shade700 : Colors.white,
        shape: GFButtonShape.standard,
        size: GFSize.MEDIUM,
        fullWidthButton: true,
      );

      final clearBtn = (_startDate != null || _endDate != null)
          ? Padding(
        padding: const EdgeInsets.only(left: 8),
        child: GFIconButton(
          onPressed: () {
            setState(() {
              _startDate = null;
              _endDate = null;
            });
            ref.read(disbursementControllerProvider.notifier).clearDates();
          },
          icon: const Icon(
            Icons.clear,
            color: Colors.white,
            size: 18,
          ),
          color: Colors.red.shade400,
          shape: GFIconButtonShape.circle,
          size: GFSize.MEDIUM,
        ),
      )
          : const SizedBox.shrink();

      if (isCompact) {
        return Column(
          children: [
            startBtn,
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: endBtn),
                clearBtn,
              ],
            ),
          ],
        );
      }

      return Row(
        children: [
          Expanded(child: startBtn),
          const SizedBox(width: 12),
          Expanded(child: endBtn),
          clearBtn,
        ],
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: isTablet
          ? Column(
        children: [
          Row(
            children: [
              Expanded(flex: 3, child: searchField()),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: dateButtons()),
            ],
          ),
        ],
      )
          : Column(
        children: [
          searchField(),
          const SizedBox(height: 12),
          dateButtons(),
        ],
      ),
    );
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6366F1),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1A1A1A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _startDate = picked);
      await ref
          .read(disbursementControllerProvider.notifier)
          .setDateRange(from: _startDate, to: _endDate);
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6366F1),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1A1A1A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _endDate = picked);
      await ref
          .read(disbursementControllerProvider.notifier)
          .setDateRange(from: _startDate, to: _endDate);
    }
  }

  Widget _buildFilterChips(String currentFilterLabel) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filterOptions.map((label) {
            final isSelected = currentFilterLabel == label;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GFButton(
                onPressed: () async {
                  setState(() => _selectedFilterLabel = label);
                  await ref
                      .read(disbursementControllerProvider.notifier)
                      .setFilter(DisbursementFilter.fromLabel(label));
                },
                text: label,
                size: GFSize.SMALL,
                color: isSelected ? const Color(0xFF6366F1) : Colors.grey[200]!,
                textColor: isSelected ? Colors.white : Colors.grey[700],
                shape: GFButtonShape.pills,
                type: GFButtonType.solid,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDisbursementCard(
      DisbursementGroup disbursement, {
        required bool isTablet,
        required bool isCompact,
      }) {
    final transactionTypeLabel = disbursement.transactionTypeName;
    final payeeName = disbursement.payeeName ?? "—";
    final remarks = disbursement.disbursementRemarks ?? "—";
    final date = disbursement.transactionDate;

    return GFCard(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: Colors.white,
      padding: EdgeInsets.zero,
      content: Column(
        children: [
          // Header Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: GFBadge(
                        text: disbursement.docNo,
                        color: const Color(0xFF6366F1),
                        textColor: Colors.white,
                        size: GFSize.MEDIUM,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GFBadge(
                      text: transactionTypeLabel,
                      color: transactionTypeLabel == "Trade"
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                      textColor: Colors.white,
                      size: GFSize.SMALL,
                    ),
                    const Spacer(),
                    if (disbursement.posted)
                      const GFBadge(
                        text: "Posted",
                        color: Color(0xFF10B981),
                        textColor: Colors.white,
                        size: GFSize.SMALL,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.business,
                        size: 18, color: Color(0xFF6366F1)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        payeeName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      date == null ? "—" : _formatDate(date),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.description,
                        size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        remarks,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Personnel Info Section (responsive)
          Container(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, c) {
                final width = c.maxWidth;
                const gap = 8.0;
                final itemW =
                isTablet ? (width - gap * 2) / 3 : (width - gap) / 2;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: itemW,
                      child: _buildPersonnelChip(
                        "Encoder",
                        disbursement.encoderName ?? "—",
                        Icons.edit,
                      ),
                    ),
                    SizedBox(
                      width: itemW,
                      child: _buildPersonnelChip(
                        "Approver",
                        disbursement.approverName ?? "—",
                        Icons.check_circle,
                      ),
                    ),
                    SizedBox(
                      width: isTablet ? itemW : width,
                      child: _buildPersonnelChip(
                        "Posted By",
                        disbursement.postedByName ?? "—",
                        Icons.publish,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Items Accordion (tablet table vs mobile cards)
          GFAccordion(
            titleChild: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.list_alt,
                      size: 20, color: Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "${disbursement.items.length} Line Items",
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    "₱${_formatAmount(disbursement.totalAmount)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),
            ),
            contentChild: Container(
              color: Colors.grey[50],
              padding: const EdgeInsets.all(16),
              child: isTablet
                  ? Column(
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            "Ref No",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "Division",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "Account",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            "Remarks",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "Amount",
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...disbursement.items
                      .map((i) => _buildItemRowTable(i))
                      .toList(),
                ],
              )
                  : Column(
                children: [
                  ...disbursement.items
                      .map((i) => _buildItemCardMobile(i,
                      compact: isCompact))
                      .toList(),
                ],
              ),
            ),
            collapsedIcon: const Icon(Icons.keyboard_arrow_down,
                color: Color(0xFF6366F1)),
            expandedIcon: const Icon(Icons.keyboard_arrow_up,
                color: Color(0xFF6366F1)),
            titleBorderRadius: BorderRadius.zero,
            contentBorderRadius: BorderRadius.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildPersonnelChip(String label, String name, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Tablet/table layout row
  Widget _buildItemRowTable(DisbursementItem item) {
    final refNo = item.referenceNo ?? "—";
    final division = item.divisionName ?? "—";
    final account = item.coaTitle ?? "—";
    final remarks = item.payableRemarks ?? "—";

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              refNo,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6366F1),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              division,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              account,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              remarks,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              "₱${_formatAmount(item.amount)}",
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mobile-friendly line item card
  Widget _buildItemCardMobile(DisbursementItem item, {required bool compact}) {
    final refNo = item.referenceNo ?? "—";
    final division = item.divisionName ?? "—";
    final account = item.coaTitle ?? "—";
    final remarks = item.payableRemarks ?? "—";

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  refNo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
              Text(
                "₱${_formatAmount(item.amount)}",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _kvLine("Division", division),
          const SizedBox(height: 6),
          _kvLine("Account", account),
          const SizedBox(height: 6),
          _kvLine(
            "Remarks",
            remarks,
            maxLines: compact ? 2 : 3,
          ),
        ],
      ),
    );
  }

  Widget _kvLine(String k, String v, {int maxLines = 2}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            k,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey[600],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            v,
            style: TextStyle(fontSize: 12, color: Colors.grey[800]),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingSliverList() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
              (_, __) => GFCard(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            color: Colors.white,
            padding: EdgeInsets.zero,
            content: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    height: 14,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          childCount: 6,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              "No disbursements found",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Try adjusting your filters",
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            GFButton(
              onPressed: () => ref
                  .read(disbursementControllerProvider.notifier)
                  .refresh(),
              text: "Refresh",
              size: GFSize.SMALL,
              color: const Color(0xFF6366F1),
              textColor: Colors.white,
              shape: GFButtonShape.pills,
              type: GFButtonType.solid,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 70, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(
              "Failed to load disbursements",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            GFButton(
              onPressed: () => ref
                  .read(disbursementControllerProvider.notifier)
                  .refresh(),
              text: "Retry",
              size: GFSize.SMALL,
              color: const Color(0xFF6366F1),
              textColor: Colors.white,
              shape: GFButtonShape.pills,
              type: GFButtonType.solid,
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF6366F1),
      ),
    );
  }

  String _formatAmount(double amount) {
    return amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"),
          (Match m) => "${m[1]},",
    );
  }

  String _formatDate(DateTime date) {
    return "${date.month}/${date.day}/${date.year}";
  }
}
