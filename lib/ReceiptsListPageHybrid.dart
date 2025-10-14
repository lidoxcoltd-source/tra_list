import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
// Remove url_launcher import
import 'ReceiptPage.dart';
import 'LocalStorageService.dart';
import 'routes.dart';
import 'services/profile_service.dart';
import 'PDFService.dart'; // Use PDFService for printing

// Add conditional import for web
import 'dart:html' as html show window;

class ReceiptsListPage extends StatefulWidget {
  const ReceiptsListPage({super.key});

  @override
  State<ReceiptsListPage> createState() => _ReceiptsListPageState();
}

class _ReceiptsListPageState extends State<ReceiptsListPage> {
  bool _useLocalStorage = false;
  List<Map<String, dynamic>> _localReceipts = [];
  // Dynamic colors from profile
  Color _brandColor = const Color(0xFF1976D2);
  Color _accentColor = const Color(0xFFFFA000);

  @override
  void initState() {
    super.initState();
    _loadProfileColors();
    _loadLocalReceipts();
  }

  void _loadLocalReceipts() {
    setState(() {
      _localReceipts = LocalStorageService.getReceipts();
    });
  }

  Future<void> _loadProfileColors() async {
    try {
      final profile = await ProfileService.loadOrCreate();
      if (mounted && profile.containsKey('colors')) {
        final colors = profile['colors'] as Map<String, dynamic>;
        setState(() {
          _brandColor = Color(colors['brand'] as int? ?? 0xFF1976D2);
          _accentColor = Color(colors['accent'] as int? ?? 0xFFFFA000);
        });
      }
    } catch (e) {
      debugPrint('Failed to load profile colors: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_useLocalStorage ? 'Local Receipts' : 'All Receipts'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_brandColor, _accentColor]),
          ),
        ),
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

        return RefreshIndicator(
          onRefresh: () async {
            // Re-trigger the stream build
            setState(() {});
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: receipts.length,
            itemBuilder: (context, index) {
              final doc = receipts[index];
              final data = doc.data() as Map<String, dynamic>;
              return _buildReceiptCard(data, isLocal: false);
            },
          ),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Print',
              icon: const Icon(Icons.print),
              onPressed: () => _printReceipt(data),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
        onTap: () => _viewReceipt(data),
      ),
    );
  }

  void _printReceipt(Map<String, dynamic> data) async {
    try {
      await PDFService.generatePDF(data);
      // PDFService shows success; no extra snackbar here to avoid duplicates.
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to print receipt: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _viewReceipt(Map<String, dynamic> data) async {
    final verificationCode = (data['verificationCode'] ?? '').toString();
    if (verificationCode.isNotEmpty) {
      final url =
          'https://tra-verify-system.web.app/#/receipt/$verificationCode';

      // Use different approach based on platform
      try {
        if (kIsWeb) {
          // For web platform, use dart:html
          html.window.open(url, '_blank');
        } else {
          // For mobile platforms, show URL for manual opening
          _showUrlDialog(url);
        }
      } catch (e) {
        Get.snackbar(
          'Error',
          'Failed to open receipt: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } else {
      Get.snackbar(
        'Error',
        'No verification code found for this receipt',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _showUrlDialog(String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receipt URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Copy this URL to view the receipt in your browser:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              // Copy to clipboard
              try {
                // This will work on most platforms
                Clipboard.setData(ClipboardData(text: url));
                Navigator.pop(context);
                Get.snackbar(
                  'Success',
                  'URL copied to clipboard',
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  'Failed to copy URL',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                );
              }
            },
            child: const Text('Copy URL'),
          ),
        ],
      ),
    );
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
              await LocalStorageService.clearAllReceipts();
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
