import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'AddReceiptPage.dart';
import 'PDFService.dart';
import 'ReceiptPage.dart';
import 'services/business_access_service.dart';

const _kBrand = Color(0xFFFFE500);
const _kDark = Color(0xFF1A1A2E);
const _kAccent = Color(0xFF16213E);

String _formatNumber(dynamic number) {
  if (number == null) return '0.00';
  final value = number is double
      ? number
      : double.tryParse(number.toString()) ?? 0.0;
  return value
      .toStringAsFixed(2)
      .replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
}

class ReceiptsListPage extends StatefulWidget {
  const ReceiptsListPage({super.key});

  @override
  State<ReceiptsListPage> createState() => _ReceiptsListPageState();
}

class _ReceiptsListPageState extends State<ReceiptsListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('receipts')
            .where('businessUid', isEqualTo: BusinessAccessService.businessId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          final allDocs = snapshot.data?.docs ?? [];
          final docs = _query.isEmpty
              ? allDocs
              : allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final customer =
                      (data['customer'] as Map<String, dynamic>? ?? {});
                  final meta = (data['meta'] as Map<String, dynamic>? ?? {});
                  final name = (customer['name'] as String? ?? '')
                      .toLowerCase();
                  final receiptNo = (meta['receiptNo'] as String? ?? '')
                      .toLowerCase();
                  return name.contains(_query) || receiptNo.contains(_query);
                }).toList();

          return CustomScrollView(
            slivers: [
              _buildSliverAppBar(context, allDocs.length),
              if (snapshot.hasError)
                SliverFillRemaining(
                  child: _buildErrorState(context, snapshot.error),
                )
              else if (snapshot.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(child: _LoadingState())
              else if (docs.isEmpty)
                const SliverFillRemaining(child: _EmptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      return _ReceiptCard(
                        data: data,
                        onView: () => _viewReceipt(context, data),
                        onEdit: BusinessAccessService.can('receipts', 'edit')
                            ? () => _editReceipt(context, data)
                            : null,
                        onDownload: () => _downloadReceipt(context, data),
                      );
                    }, childCount: docs.length),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: BusinessAccessService.can('receipts', 'create')
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddReceiptPage()),
              ),
              backgroundColor: _kBrand,
              foregroundColor: _kDark,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'New Receipt',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
              elevation: 4,
            )
          : null,
    );
  }

  Widget _buildSliverAppBar(BuildContext context, int totalCount) {
    return SliverAppBar(
      expandedHeight: 130,
      pinned: true,
      backgroundColor: _kDark,
      foregroundColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Receipts',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      centerTitle: false,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by customer or receipt no…',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Colors.white54,
                size: 20,
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white54,
                        size: 18,
                      ),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kDark, _kAccent],
            ),
          ),
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 62),
                child: _StatChip(
                  icon: Icons.receipt_long_rounded,
                  label: 'Total Receipts',
                  value: '$totalCount',
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (BusinessAccessService.can('receipts', 'create'))
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddReceiptPage()),
            ),
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Add New Receipt',
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: Colors.orange.shade600,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Firestore Unavailable',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _kDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please enable Firestore in your Firebase Console to load receipts.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Setup steps:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final step in const [
                    '1. Open Firebase Console',
                    '2. Select "Firestore Database"',
                    '3. Click "Create database"',
                    '4. Choose "Start in test mode"',
                    '5. Select a location & confirm',
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        step,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You can still create new receipts in the meantime.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.green.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat chip shown in the collapsible app bar header
// ---------------------------------------------------------------------------
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _kBrand, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3, color: _kBrand),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading receipts…',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 52,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No receipts yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "New Receipt" to create your first one.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Receipt card
// ---------------------------------------------------------------------------
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.data,
    required this.onView,
    required this.onEdit,
    required this.onDownload,
  });

  final Map<String, dynamic> data;
  final VoidCallback onView;
  final VoidCallback? onEdit;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final customer = data['customer'] as Map<String, dynamic>? ?? {};
    final meta = data['meta'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List? ?? [];
    final totalInclTax = data['totalInclTax'] ?? 0.0;
    final verificationCode = data['verificationCode'] as String? ?? '';

    final customerName = customer['name'] as String? ?? 'Unknown Customer';
    final initials = _initials(customerName);
    final firstItem = items.isNotEmpty ? items[0] as Map<String, dynamic> : {};
    final itemDescription = firstItem['description'] as String? ?? 'No items';
    final receiptNo = meta['receiptNo'] as String? ?? 'N/A';
    final receiptDate = meta['receiptDate'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onView,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Header row: avatar + name + amount badge ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_kDark, _kAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: _kBrand,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name & description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customerName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _kDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            itemDescription,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Amount badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'TZS ${_formatNumber(totalInclTax)}',
                        style: const TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(height: 1, thickness: 1),
                const SizedBox(height: 10),

                // --- Meta row: receipt no + date ---
                Row(
                  children: [
                    const Icon(
                      Icons.tag_rounded,
                      size: 14,
                      color: Color(0xFF9E9E9E),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      receiptNo,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF616161),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: Color(0xFF9E9E9E),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      receiptDate,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF757575),
                      ),
                    ),
                  ],
                ),

                if (verificationCode.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: Color(0xFF1976D2),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          verificationCode,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1976D2),
                            fontFamily: 'monospace',
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 10),
                const Divider(height: 1, thickness: 1),
                const SizedBox(height: 4),

                // --- Action row ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _ActionButton(
                      icon: Icons.visibility_rounded,
                      label: 'View',
                      color: _kDark,
                      onPressed: onView,
                    ),
                    const SizedBox(width: 6),
                    if (onEdit != null) ...[
                      _ActionButton(
                        icon: Icons.edit_rounded,
                        label: 'Edit',
                        color: const Color(0xFF1565C0),
                        onPressed: onEdit!,
                      ),
                      const SizedBox(width: 6),
                    ],
                    _ActionButton(
                      icon: Icons.download_rounded,
                      label: 'PDF',
                      color: const Color(0xFF2E7D32),
                      onPressed: onDownload,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// Small action button used in the card footer
// ---------------------------------------------------------------------------
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers & business logic extracted from ReceiptsListPage
// ---------------------------------------------------------------------------
extension on _ReceiptsListPageState {
  void _editReceipt(BuildContext context, Map<String, dynamic> data) {
    // TODO: Implement edit functionality
    print('Edit receipt: ${data['meta']?['receiptNo']}');
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
          vrn: customer['vrn'] ?? '',
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
        MaterialPageRoute(
          builder: (context) => AddReceiptPage(receiptData: receiptData),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading receipt for editing: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _downloadReceipt(BuildContext context, Map<String, dynamic> data) {
    PDFService.generatePDF(data);
  }

  void _viewReceipt(
    BuildContext context,
    Map<String, dynamic> data, {
    bool download = false,
  }) async {
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
          vrn: customer['vrn'] ?? '',
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

      if (download) {
        final bytes = await buildReceiptPdf(receiptData);
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'receipt_${receiptData.meta.receiptNo}.pdf',
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReceiptPage(data: receiptData),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading receipt: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
