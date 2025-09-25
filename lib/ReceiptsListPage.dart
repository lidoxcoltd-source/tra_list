import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ReceiptPage.dart';
import 'AddReceiptPage.dart';

class ReceiptsListPage extends StatelessWidget {
  const ReceiptsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('All Receipts'),
        centerTitle: true,
        backgroundColor: const Color(0xFFFFE500),
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddReceiptPage()),
              );
            },
            icon: const Icon(Icons.add),
            tooltip: 'Add New Receipt',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('receipts')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 64,
                      color: Colors.orange.shade400,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Firestore Connection Error',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please enable Firestore in Firebase Console:',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '1. Go to Firebase Console',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const Text('2. Select "Firestore Database"'),
                          const Text('3. Click "Create database"'),
                          const Text('4. Choose "Start in test mode"'),
                          const Text('5. Select a location'),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              // You can add URL launch here if needed
                            },
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open Firebase Console'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'You can still create receipts using "Add New Receipt"',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading receipts...'),
                ],
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No receipts found',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add your first receipt',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              return _buildReceiptCard(context, data);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddReceiptPage()),
          );
        },
        backgroundColor: const Color(0xFFFFE500),
        foregroundColor: Colors.black87,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildReceiptCard(BuildContext context, Map<String, dynamic> data) {
    final customer = data['customer'] as Map<String, dynamic>? ?? {};
    final meta = data['meta'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List? ?? [];
    final totalInclTax = data['totalInclTax'] ?? 0.0;
    final verificationCode = data['verificationCode'] ?? '';

    final firstItem = items.isNotEmpty ? items[0] as Map<String, dynamic> : {};
    final itemDescription = firstItem['description'] ?? 'No items';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _viewReceipt(context, data),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      customer['name'] ?? 'Unknown Customer',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'TZS ${_formatNumber(totalInclTax)}',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                itemDescription,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Receipt: ${meta['receiptNo'] ?? 'N/A'}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                  Text(
                    meta['receiptDate'] ?? '',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Code: $verificationCode',
                style: TextStyle(
                  color: Colors.blue.shade600,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _viewReceipt(BuildContext context, Map<String, dynamic> data) {
    try {
      final company = data['company'] as Map<String, dynamic>? ?? {};
      final customer = data['customer'] as Map<String, dynamic>? ?? {};
      final meta = data['meta'] as Map<String, dynamic>? ?? {};
      final items = data['items'] as List? ?? [];

      final receiptData = ReceiptData(
        company: CompanyInfo(
          name: company['name'] ?? '',
          addressLine: company['addressLine'] ?? '',
          mobile: company['mobile'] ?? '',
          tin: company['tin'] ?? '',
          vrn: company['vrn'] ?? '',
          serialNo: company['serialNo'] ?? '',
          uim: company['uim'] ?? '',
          taxOffice: company['taxOffice'] ?? '',
          logo: const AssetImage('assets/tra-logo.png'),
        ),
        customer: CustomerInfo(
          name: customer['name'] ?? '',
          idType: customer['idType'] ?? '',
          idNo: customer['idNo'] ?? '',
          mobile: customer['mobile'] ?? '',
        ),
        meta: ReceiptMeta(
          receiptNo: meta['receiptNo'] ?? '',
          zNumber: meta['zNumber'] ?? '',
          receiptDate: meta['receiptDate'] ?? '',
          receiptTime: meta['receiptTime'] ?? '',
        ),
        items: items.map((item) {
          final itemData = item as Map<String, dynamic>;
          return LineItem(
            description: itemData['description'] ?? '',
            qty: itemData['qty'] ?? 1,
            amount: (itemData['amount'] ?? 0.0).toDouble(),
          );
        }).toList(),
        totalExclTax: (data['totalExclTax'] ?? 0.0).toDouble(),
        tax: (data['tax'] ?? 0.0).toDouble(),
        totalInclTax: (data['totalInclTax'] ?? 0.0).toDouble(),
        verificationCode: data['verificationCode'] ?? '',
        qr: const AssetImage('assets/frame.png'),
      );

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ReceiptPage(data: receiptData)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading receipt: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatNumber(dynamic number) {
    if (number == null) return '0.00';
    final value = number is double
        ? number
        : double.tryParse(number.toString()) ?? 0.0;
    return value
        .toStringAsFixed(2)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }
}
