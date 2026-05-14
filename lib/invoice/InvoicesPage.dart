import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:tra_list/services/pdf/delivery_note_pdf.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:tra_list/services/pdf/payment_reminder_pdf.dart';
import 'package:tra_list/services/pdf/proforma_pdf.dart';
import 'package:tra_list/services/pdf/advance_payment_pdf.dart';
import 'package:tra_list/services/pdf/quotation_pdf.dart';

import 'InvoicePage.dart' as invoice_page;
import 'advance_invoice_page.dart';
import 'quotation_page.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  final _searchC = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  // Beautiful UI colors
  final Color primary = const Color(0xFF2563EB); // Modern blue
  final Color primaryDark = const Color(0xFF1E3A8A);
  final Color accent = const Color(0xFF3B82F6);
  final Color bgColor = const Color(0xFFF8FAFC); // Slate 50
  final Color surfaceColor = Colors.white;
  final Color textMain = const Color(0xFF0F172A); // Slate 900
  final Color textMuted = const Color(0xFF64748B); // Slate 500

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text(
            'My Documents',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          elevation: 0,
          foregroundColor: Colors.white,
          centerTitle: true,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryDark, primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_outline, size: 48, color: primary),
                ),
                const SizedBox(height: 24),
                Text(
                  'Authentication Required',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textMain,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please sign in to view and manage your documents safely.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textMuted),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.login),
                    onPressed: () async {
                      await FirebaseAuth.instance.signInAnonymously();
                      Get.snackbar(
                        'Signed in',
                        'Anonymous sign-in complete',
                        backgroundColor: Colors.green,
                        colorText: Colors.white,
                      );
                    },
                    label: const Text(
                      'Sign In Anonymously',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('invoices')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: bgColor,
      floatingActionButton: FloatingActionButton.extended(
        elevation: 4,
        highlightElevation: 8,
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const invoice_page.InvoicePage()),
          );
        },
        label: const Text(
          'New Document',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        icon: const Icon(Icons.add_circle_outline),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: primary));
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade400,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Something went wrong',
                    style: TextStyle(
                      color: textMain,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snap.error}',
                    style: TextStyle(color: textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final all = snap.data?.docs ?? [];
          final filtered = all.where((d) {
            if (_query.isEmpty) return true;
            final data = d.data();
            final invNo = ((data['invoice'] as Map?)?['number'] ?? '')
                .toString();
            final client = ((data['client'] as Map?)?['name'] ?? '').toString();
            return invNo.toLowerCase().contains(_query) ||
                client.toLowerCase().contains(_query);
          }).toList();

          final invoiceTotalSum = filtered.fold<num>(
            0,
            (sum, d) => (d.data()['kind'] == 'invoice')
                ? sum + ((d.data()['total'] as num?) ?? 0)
                : sum,
          );

          return RefreshIndicator(
            color: primary,
            onRefresh: () async {
              setState(() {});
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  expandedHeight: 140.0,
                  floating: false,
                  pinned: true,
                  elevation: 0,
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  actions: [
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        tooltip: 'New Quotation',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const QuotationPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.request_quote),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        tooltip: 'New Advance Invoice',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdvanceInvoicePage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.payments_outlined),
                      ),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    title: const Text(
                      'My Invoices',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primaryDark, primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -50,
                            top: -50,
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.05),
                              ),
                            ),
                          ),
                          Positioned(
                            left: -30,
                            bottom: -20,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.05),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Column(
                      children: [
                        _buildSearchBar(),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            _StatCard(
                              label: 'Total Invoices',
                              value: '${filtered.length}',
                              icon: Icons.description_outlined,
                              color: const Color(0xFF8B5CF6), // Violet
                              bgColor: const Color(0xFFF5F3FF),
                            ),
                            const SizedBox(width: 16),
                            _StatCard(
                              label: 'Total Revenue',
                              value: 'TSH ${_money(invoiceTotalSum)}',
                              icon: Icons.account_balance_wallet_outlined,
                              color: const Color(0xFF10B981), // Emerald
                              bgColor: const Color(0xFFECFDF5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      onCreate: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const invoice_page.InvoicePage(),
                          ),
                        );
                      },
                      onCreateAdvance: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdvanceInvoicePage(),
                          ),
                        );
                      },
                      primary: primary,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      10,
                      20,
                      100,
                    ), // padding bottom for fab
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final doc = filtered[i];
                        return _buildDocumentCard(doc);
                      }, childCount: filtered.length),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchC,
        onChanged: (q) => setState(() => _query = q.toLowerCase()),
        style: TextStyle(color: textMain, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Search by client or invoice no...',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: Icon(Icons.search, color: textMuted),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: textMuted),
                  onPressed: () {
                    _searchC.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: surfaceColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final invoice = (data['invoice'] as Map?) ?? {};
    final kind = (data['kind']?.toString() ?? 'invoice');
    final client = (data['client'] as Map?) ?? {};
    final created = _asDate(data['createdAt']);
    final total = (data['total'] as num?) ?? 0;

    final kindColor = _getColorForKind(kind);
    final kindBg = kindColor.withOpacity(0.1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey(doc.id),
        direction: DismissDirection.endToStart,
        background: _swipeBg(),
        confirmDismiss: (dir) => _confirmDismiss(context),
        onDismissed: (_) async {
          await doc.reference.delete();
          Get.snackbar(
            'Deleted',
            'Document moved to trash',
            snackPosition: SnackPosition.BOTTOM,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _previewPdf(data, kind),
              onLongPress: () => _showActions(context, doc),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 52,
                          width: 52,
                          decoration: BoxDecoration(
                            color: kindBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: kindColor.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            _getIconForKind(kind),
                            color: kindColor,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      client['name'] ?? 'Unknown client',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: textMain,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: kindBg,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          _getTitleForKind(kind),
                                          style: TextStyle(
                                            color: kindColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                        icon: Icon(
                                          Icons.more_vert,
                                          color: textMuted,
                                          size: 22,
                                        ),
                                        onPressed: () =>
                                            _showActions(context, doc),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '#${invoice['number'] ?? doc.id.substring(0, 6)}',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey.shade100, height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 14,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _fmt(created),
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            if ((invoice['paymentMethod'] ?? '')
                                .toString()
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.payment_outlined,
                                    size: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    (invoice['paymentMethod'] ?? '').toString(),
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Total Amount',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'TSH ${_money(total)}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: textMain,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showActions(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final kind = data['kind']?.toString() ?? 'invoice';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Document Options',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textMain,
                ),
              ),
              const SizedBox(height: 16),
              _ActionTile(
                icon: Icons.edit_outlined,
                title: 'Edit Document',
                color: textMain,
                onTap: () {
                  Navigator.pop(context);
                  _editInvoice(doc);
                },
              ),
              _ActionTile(
                icon: Icons.visibility_outlined,
                title: 'Preview PDF',
                color: textMain,
                onTap: () {
                  Navigator.pop(context);
                  _previewPdf(data, kind);
                },
              ),
              _ActionTile(
                icon: Icons.download_outlined,
                title: 'Download Original PDF',
                color: textMain,
                onTap: () {
                  Navigator.pop(context);
                  _savePdf(data, kind);
                },
              ),
              Divider(color: Colors.grey.shade100, height: 24),
              ExpansionTile(
                leading: Icon(Icons.file_copy_outlined, color: textMain),
                title: Text(
                  'Generate As...',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: textMain,
                  ),
                ),
                childrenPadding: const EdgeInsets.only(left: 16),
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Invoice',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'invoice');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Quotation',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'quotation');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Proforma',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'proforma');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Delivery Note',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'delivery');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Payment Reminder',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'reminder');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Advance Payment',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'advance');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.table_chart_outlined,
                    title: 'Export as Excel',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _saveAsExcel(data);
                    },
                  ),
                ],
              ),
              Divider(color: Colors.grey.shade100, height: 24),
              _ActionTile(
                icon: Icons.delete_outline,
                title: 'Delete Document',
                color: Colors.red,
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await _confirmDismiss(context);
                  if (ok == true) {
                    await doc.reference.delete();
                    Get.snackbar(
                      'Deleted',
                      'Document removed',
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static String _fmt(DateTime? d) {
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year}';
  }

  Widget _swipeBg() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade400,
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Icon(Icons.delete_outline, color: Colors.white, size: 32),
    );
  }

  Future<bool?> _confirmDismiss(BuildContext context) async {
    return await Get.dialog<bool>(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Text('Delete Document?'),
          ],
        ),
        content: const Text(
          'This action cannot be undone. Are you sure you want to proceed?',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Get.back(result: true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  static String _money(num v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  Color _getColorForKind(String kind) {
    return switch (kind) {
      'proforma' => const Color(0xFFF59E0B), // Amber
      'quotation' => const Color(0xFF8B5CF6), // Violet
      'delivery' => const Color(0xFF10B981), // Emerald
      'reminder' => const Color(0xFFEF4444), // Red
      'advance' => const Color(0xFF06B6D4), // Cyan
      _ => primary, // invoice (Blue)
    };
  }

  IconData _getIconForKind(String kind) {
    return switch (kind) {
      'proforma' => Icons.request_quote_outlined,
      'quotation' => Icons.request_quote,
      'delivery' => Icons.local_shipping_outlined,
      'reminder' => Icons.alarm_on_outlined,
      'advance' => Icons.payments_outlined,
      _ => Icons.receipt_long, // invoice
    };
  }

  String _getTitleForKind(String kind) {
    return switch (kind) {
      'proforma' => 'Proforma',
      'quotation' => 'Quotation',
      'delivery' => 'Delivery Note',
      'reminder' => 'Reminder',
      'advance' => 'Advance Payment Invoice',
      _ => 'Invoice',
    };
  }

  void _savePdf(Map<String, dynamic> data, String kind) async {
    try {
      final clean = Map<String, dynamic>.from(data);
      final ts = clean['createdAt'];
      if (ts is Timestamp) clean['createdAt'] = ts.toDate().toIso8601String();

      final no = (clean['invoice'] as Map?)?['number']?.toString();
      final fileNameBase = (no == null || no.isEmpty)
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : no;
      final fileName = '${kind}_$fileNameBase.pdf';

      final pathOrName = await ({
        'invoice': () => InvoicePdf.generateAndSave(clean, fileName: fileName),
        'proforma': () =>
            ProformaPdf.generateAndSave(clean, fileName: fileName),
        'delivery': () =>
            DeliveryNotePdf.generateAndSave(clean, fileName: fileName),
        'reminder': () =>
            PaymentReminderPdf.generateAndSave(clean, fileName: fileName),
        'advance': () =>
            AdvancePaymentPdf.generateAndSave(clean, fileName: fileName),
        'quotation': () =>
            QuotationPdf.generateAndSave(clean, fileName: fileName),
      }[kind]!).call();

      Get.snackbar(
        kIsWeb ? 'PDF downloaded' : 'PDF saved',
        pathOrName,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _previewPdf(Map<String, dynamic> data, String kind) async {
    try {
      await ({
        'invoice': () => InvoicePdf.generate(data),
        'proforma': () => ProformaPdf.generate(data),
        'delivery': () => DeliveryNotePdf.generate(data),
        'reminder': () => PaymentReminderPdf.generate(data),
        'advance': () => AdvancePaymentPdf.generate(data),
        'quotation': () => QuotationPdf.generate(data),
      }[kind]!).call();
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to generate preview: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _saveAsExcel(Map<String, dynamic> data) async {
    try {
      Get.snackbar(
        'Excel export',
        'Excel export is not available in this build.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save Excel file: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _editInvoice(DocumentSnapshot<Map<String, dynamic>> doc) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => invoice_page.InvoicePage(invoice: doc)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onCreate,
    required this.onCreateAdvance,
    required this.primary,
  });

  final VoidCallback onCreate;
  final VoidCallback onCreateAdvance;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.description_outlined, size: 80, color: primary),
            ),
            const SizedBox(height: 24),
            const Text(
              'No documents yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Create your first invoice or quotation and keep track of your business easily.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text(
                'Create New Document',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onCreateAdvance,
              icon: const Icon(Icons.payments_outlined),
              label: const Text(
                'Create Advance Invoice',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: Colors.grey.shade300,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color color;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}
