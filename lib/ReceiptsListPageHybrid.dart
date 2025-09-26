import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'ReceiptPage.dart';
import 'platform_local_storage_service.dart';
import 'routes.dart';

class ReceiptsListPage extends StatefulWidget {
  const ReceiptsListPage({super.key});

  @override
  State<ReceiptsListPage> createState() => _ReceiptsListPageState();
}

class _ReceiptsListPageState extends State<ReceiptsListPage> {
  bool _useLocalStorage = false;
  List<Map<String, dynamic>> _localReceipts = [];

  @override
  void initState() {
    super.initState();
    _loadLocalReceipts();
  }

  void _loadLocalReceipts() async {
    final receipts = await PlatformLocalStorageService.getReceipts();
    setState(() {
      _localReceipts = receipts;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_useLocalStorage ? 'Local Receipts' : 'All Receipts'),
        centerTitle: true,
        backgroundColor: const Color(0xFFFFE500),
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'toggle') {
                setState(() {
                  _useLocalStorage = !_useLocalStorage;
                  if (_useLocalStorage) {
                    _loadLocalReceipts();
                  }
                });
              } else if (value == 'clear_local') {
                _showClearDialog();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle',
                child: Row(
                  children: [
                    Icon(_useLocalStorage ? Icons.cloud : Icons.storage),
                    const SizedBox(width: 8),
                    Text(
                      _useLocalStorage
                          ? 'Switch to Firebase'
                          : 'Switch to Local',
                    ),
                  ],
                ),
              ),
              if (_useLocalStorage)
                const PopupMenuItem(
                  value: 'clear_local',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Clear Local Data'),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: () async {
              await Get.toNamed(AppRoutes.addReceipt);
              if (_useLocalStorage) {
                _loadLocalReceipts();
              }
            },
            icon: const Icon(Icons.add),
            tooltip: 'Add New Receipt',
          ),
        ],
      ),
      body: _useLocalStorage
          ? _buildLocalReceiptsList()
          : _buildFirestoreReceiptsList(),
    );
  }

  Widget _buildLocalReceiptsList() {
    if (_localReceipts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No receipts saved locally',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text('Create your first receipt!'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _loadLocalReceipts();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _localReceipts.length,
        itemBuilder: (context, index) {
          final receipt = _localReceipts[index];
          return _buildReceiptCard(receipt, isLocal: true);
        },
      ),
    );
  }

  Widget _buildFirestoreReceiptsList() {
    return StreamBuilder<QuerySnapshot>(
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
                    'Firebase Connection Error',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Firestore database is not enabled.',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _useLocalStorage = true;
                        _loadLocalReceipts();
                      });
                    },
                    icon: const Icon(Icons.storage),
                    label: const Text('Use Local Storage'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Get.toNamed(AppRoutes.addReceipt);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create Receipt Anyway'),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final receipts = snapshot.data?.docs ?? [];

        if (receipts.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No receipts found',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text('Create your first receipt!'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: receipts.length,
          itemBuilder: (context, index) {
            final doc = receipts[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildReceiptCard(data, isLocal: false);
          },
        );
      },
    );
  }

  Widget _buildReceiptCard(Map<String, dynamic> data, {required bool isLocal}) {
    final customer = data['customer'] as Map<String, dynamic>? ?? {};
    final meta = data['meta'] as Map<String, dynamic>? ?? {};
    final totalInclTax = data['totalInclTax'] as double? ?? 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isLocal
              ? Colors.blue.shade100
              : Colors.green.shade100,
          child: Icon(
            isLocal ? Icons.storage : Icons.cloud_done,
            color: isLocal ? Colors.blue : Colors.green,
          ),
        ),
        title: Text(
          customer['name'] ?? 'Unknown Customer',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receipt #${meta['receiptNo'] ?? 'N/A'}'),
            Text('Total: TZS ${totalInclTax.toStringAsFixed(2)}'),
            if (isLocal)
              const Text(
                'Stored locally',
                style: TextStyle(color: Colors.blue, fontSize: 12),
              ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _viewReceipt(data),
      ),
    );
  }

  void _viewReceipt(Map<String, dynamic> data) {
    final verificationCode = data['verificationCode'] ?? '';
    if (verificationCode.isNotEmpty) {
      // Navigate using receipt ID in the URL
      Get.toNamed('/receipt/$verificationCode');
    } else {
      // Fallback to direct receipt page navigation
      final receiptData = _mapToReceiptData(data);
      Get.to(() => ReceiptPage(data: receiptData));
    }
  }

  ReceiptData _mapToReceiptData(Map<String, dynamic> data) {
    final company = data['company'] as Map<String, dynamic>? ?? {};
    final customer = data['customer'] as Map<String, dynamic>? ?? {};
    final meta = data['meta'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List<dynamic>? ?? [];

    return ReceiptData(
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
        final itemMap = item as Map<String, dynamic>;
        return LineItem(
          description: itemMap['description'] ?? '',
          qty: itemMap['qty'] ?? 1,
          amount: (itemMap['amount'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList(),
      totalExclTax: (data['totalExclTax'] as num?)?.toDouble() ?? 0.0,
      tax: (data['tax'] as num?)?.toDouble() ?? 0.0,
      totalInclTax: (data['totalInclTax'] as num?)?.toDouble() ?? 0.0,
      verificationCode: data['verificationCode'] ?? '',
      qr: const AssetImage('assets/frame.png'),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Local Data'),
        content: const Text(
          'Are you sure you want to clear all locally stored receipts? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await PlatformLocalStorageService.clearAllReceipts();
              _loadLocalReceipts();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Local data cleared successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
