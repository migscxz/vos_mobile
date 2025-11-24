import 'package:flutter/material.dart';

class DisbursementView extends StatefulWidget {
  const DisbursementView({Key? key}) : super(key: key);

  @override
  State<DisbursementView> createState() => _DisbursementViewState();
}

class _DisbursementViewState extends State<DisbursementView> {
  final List<SupplierAccount> _suppliers = [
    SupplierAccount(
      supplierName: 'ABC Electronics Co.',
      accounts: [
        AccountEntry(remarks: 'Office equipment - Laptops', amount: 45000.00),
        AccountEntry(remarks: 'Monitor stands and accessories', amount: 8500.50),
        AccountEntry(remarks: 'Printer and scanner units', amount: 12300.00),
      ],
    ),
    SupplierAccount(
      supplierName: 'XYZ Supplies Inc.',
      accounts: [
        AccountEntry(remarks: 'Office supplies - Paper, pens', amount: 3500.00),
        AccountEntry(remarks: 'Cleaning materials', amount: 2100.75),
      ],
    ),
    SupplierAccount(
      supplierName: 'Tech Solutions Ltd.',
      accounts: [
        AccountEntry(remarks: 'Software licenses renewal', amount: 25000.00),
        AccountEntry(remarks: 'Cloud storage subscription', amount: 5400.00),
        AccountEntry(remarks: 'IT maintenance service', amount: 8900.00),
      ],
    ),
  ];

  double get totalDisbursement {
    double total = 0;
    for (var supplier in _suppliers) {
      for (var account in supplier.accounts) {
        total += account.amount;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Disbursement Report',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download, color: Color(0xFF6366F1)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export feature')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.print, color: Color(0xFF6366F1)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Print feature')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTotalSummary(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _suppliers.length,
              itemBuilder: (context, index) {
                return _buildSupplierCard(_suppliers[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6366F1),
            const Color(0xFF8B5CF6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Total Disbursement',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₱${_formatAmount(totalDisbursement)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_suppliers.length} Suppliers',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierCard(SupplierAccount supplier) {
    final supplierTotal = supplier.accounts.fold<double>(
      0,
          (sum, account) => sum + account.amount,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Supplier Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.business,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supplier.supplierName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${supplier.accounts.length} account${supplier.accounts.length > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '₱${_formatAmount(supplierTotal)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Accounts Table
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Table Header
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Remarks',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.grey[700],
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Amount',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.grey[700],
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Account Rows
                ...supplier.accounts.asMap().entries.map((entry) {
                  final index = entry.key;
                  final account = entry.value;
                  return _buildAccountRow(account, index == supplier.accounts.length - 1);
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRow(AccountEntry account, bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        border: !isLast
            ? Border(
          bottom: BorderSide(
            color: Colors.grey[200]!,
            width: 1,
          ),
        )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    account.remarks,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[800],
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text(
              '₱${_formatAmount(account.amount)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    return amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
    );
  }
}

// Data Models
class SupplierAccount {
  final String supplierName;
  final List<AccountEntry> accounts;

  SupplierAccount({
    required this.supplierName,
    required this.accounts,
  });
}

class AccountEntry {
  final String remarks;
  final double amount;

  AccountEntry({
    required this.remarks,
    required this.amount,
  });
}