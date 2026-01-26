part of "sr_view.dart";

/* ======================= PRESENTATION WIDGETS ======================= */

class _InvoiceList extends StatefulWidget {
  final List<SalesReportRow> rows;
  final bool hasMore;
  final VoidCallback onNeedMore;
  final bool isTablet;

  const _InvoiceList({
    required this.rows,
    required this.hasMore,
    required this.onNeedMore,
    required this.isTablet,
  });

  @override
  State<_InvoiceList> createState() => _InvoiceListState();
}

class _InvoiceListState extends State<_InvoiceList> {
  bool _askedMore = false;

  @override
  Widget build(BuildContext context) {
    final pad =
    widget.isTablet ? const EdgeInsets.all(18) : const EdgeInsets.all(16);

    if (!widget.isTablet) {
      // Phone: ListView
      return ListView.separated(
        padding: pad,
        itemCount: widget.rows.length + (widget.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= widget.rows.length) {
            if (!_askedMore) {
              _askedMore = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.onNeedMore();
                _askedMore = false;
              });
            }
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            );
          }
          final row = widget.rows[index];
          return _SalesInvoiceCard(row: row, isTablet: false);
        },
      );
    }

    // Tablet: Grid (2–3 columns based on width)
    final width = MediaQuery.sizeOf(context).width;
    final columns = width ~/ 520; // target ~520px per card
    final crossAxisCount = columns.clamp(2, 3);

    return GridView.builder(
      padding: pad,
      itemCount: widget.rows.length + (widget.hasMore ? 1 : 0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: 320,
      ),
      itemBuilder: (context, index) {
        if (index >= widget.rows.length) {
          if (!_askedMore) {
            _askedMore = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onNeedMore();
              _askedMore = false;
            });
          }
          return const Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final row = widget.rows[index];
        return _SalesInvoiceCard(row: row, isTablet: true);
      },
    );
  }
}

class _CompactMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isTablet;

  const _CompactMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 14 : 12, vertical: isTablet ? 12 : 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: isTablet ? 20 : 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isTablet ? 11 : 10,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: isTablet ? 16 : 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isTablet;

  const _CompactFilterChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 12 : 10, vertical: isTablet ? 9 : 8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isTablet ? 16 : 14, color: Colors.grey[700]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: isTablet ? 13 : 12,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: isTablet ? 20 : 18, color: Colors.grey[700]),
          ],
        ),
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorWidget({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red[700], size: 48),
            const SizedBox(height: 16),
            Text(
              "Error Loading Data",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("Retry"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWidget extends StatelessWidget {
  const _EmptyWidget();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            "No Results Found",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Try adjusting your filters",
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesInvoiceCard extends StatelessWidget {
  final SalesReportRow row;
  final bool isTablet;

  const _SalesInvoiceCard({required this.row, this.isTablet = false});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat("MMM dd, yyyy");
    final dateStr = row.invoiceDate != null ? dateFormat.format(row.invoiceDate!) : "—";
    final currency = NumberFormat.currency(symbol: "₱", decimalDigits: 2);

    final paid = row.paymentStatus.toLowerCase() == "paid";

    return InkWell(
      onTap: () {
        // TODO: Navigate to invoice details if needed
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isTablet ? 16 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row - Invoice & Amount
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.invoiceNo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isTablet ? 16 : 15,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: isTablet ? 13 : 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currency.format(row.collection),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 18 : 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _StatusBadge(
                      label: row.paymentStatus,
                      color: paid ? Colors.green : Colors.orange,
                      isTablet: isTablet,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey[200]),
            const SizedBox(height: 10),

            // Customer Info
            Row(
              children: [
                Icon(Icons.person, size: isTablet ? 15 : 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    row.customerName,
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on, size: isTablet ? 15 : 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    row.customerAddress,
                    style: TextStyle(
                      fontSize: isTablet ? 13 : 12,
                      color: Colors.grey[700],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey[200]),
            const SizedBox(height: 10),

            // Sales Details
            Row(
              children: [
                Expanded(
                  child: _CompactInfoItem(
                    icon: Icons.person_outline,
                    label: row.salesman,
                    isTablet: isTablet,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CompactInfoItem(
                    icon: Icons.store,
                    label: row.branch,
                    isTablet: isTablet,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CompactInfoItem(
                    icon: Icons.payment,
                    label: row.paymentTerms,
                    isTablet: isTablet,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CompactInfoItem(
                    icon: Icons.category,
                    label: row.salesType,
                    isTablet: isTablet,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey[200]),
            const SizedBox(height: 10),

            // Amount Breakdown - Compact
            _CompactAmountRow(label: "Total", amount: row.totalAmount, isTablet: isTablet),
            if (row.discountAmount > 0) ...[
              const SizedBox(height: 4),
              _CompactAmountRow(
                label: "Discount",
                amount: row.discountAmount,
                isNegative: true,
                isTablet: isTablet,
              ),
            ],
            if (row.returnAmount > 0) ...[
              const SizedBox(height: 4),
              _CompactAmountRow(
                label: "Returns",
                amount: row.returnAmount,
                isNegative: true,
                isTablet: isTablet,
              ),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: isTablet ? 15 : 14, color: Colors.green[700]),
                      const SizedBox(width: 6),
                      Text(
                        "Collection",
                        style: TextStyle(
                          fontSize: isTablet ? 13 : 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                  Text(
                    NumberFormat.currency(symbol: "₱", decimalDigits: 2).format(row.collection),
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),

            if (row.isPosted || row.isDispatched) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (row.isPosted)
                    _TinyBadge(
                        label: "Posted",
                        icon: Icons.check_circle,
                        color: Colors.blue,
                        isTablet: isTablet),
                  if (row.isDispatched) const SizedBox(width: 6),
                  if (row.isDispatched)
                    _TinyBadge(
                        label: "Dispatched",
                        icon: Icons.local_shipping,
                        color: Colors.purple,
                        isTablet: isTablet),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactInfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isTablet;

  const _CompactInfoItem({
    required this.icon,
    required this.label,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: isTablet ? 14 : 13, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isTablet ? 13 : 12,
              color: Colors.grey[800],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CompactAmountRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool isNegative;
  final bool isTablet;

  const _CompactAmountRow({
    required this.label,
    required this.amount,
    this.isNegative = false,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: "₱", decimalDigits: 2);
    final displayAmount =
    isNegative ? "-${formatter.format(amount)}" : formatter.format(amount);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: isTablet ? 13 : 12, color: Colors.grey[700])),
          Text(
            displayAmount,
            style: TextStyle(
              fontSize: isTablet ? 13 : 12,
              color: isNegative ? Colors.red[700] : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool isTablet;

  const _StatusBadge({
    required this.label,
    required this.color,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: isTablet ? 11 : 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isTablet;

  const _TinyBadge({
    required this.label,
    required this.icon,
    required this.color,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 7 : 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isTablet ? 11 : 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: isTablet ? 10 : 9,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
