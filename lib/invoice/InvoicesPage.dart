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

import 'InvoicePage.dart' as invoice_page;
import 'advance_invoice_page.dart';

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

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1976D2);
    const accent = Color(0xFF42A5F5);

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Documents'),
          elevation: 0,
          foregroundColor: Colors.white,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        body: Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.login),
            onPressed: () async {
              await FirebaseAuth.instance.signInAnonymously();
              Get.snackbar('Signed in', 'Anonymous sign-in complete');
            },
            label: const Text('Sign in to view invoices'),
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
      // NEW: Floating Action Button for quick creation
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const invoice_page.InvoicePage()),
          );
        },
        label: const Text('New Document'),
        icon: const Icon(Icons.add),
        backgroundColor: primary,
      ),
      appBar: AppBar(
        elevation: 0,
        title: const Text('My Documents'),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'New Advance Invoice',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdvanceInvoicePage()),
              );
            },
            icon: const Icon(Icons.payments_outlined),
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [primary, accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      backgroundColor: Colors.grey.shade50,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
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

          if (filtered.isEmpty) {
            return _EmptyState(
              onCreate: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const invoice_page.InvoicePage(),
                  ),
                );
              },
              onCreateAdvance: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdvanceInvoicePage()),
                );
              },
            );
          }
          // Only sum the totals for actual invoices
          final invoiceTotalSum = filtered.fold<num>(
            0,
            (sum, d) => (d.data()['kind'] == 'invoice')
                ? sum + ((d.data()['total'] as num?) ?? 0)
                : sum,
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ), // Search bar
                child: TextField(
                  controller: _searchC,
                  onChanged: (q) => setState(() => _query = q.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search by client or invoice no...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchC.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    _StatCard(
                      label: 'Documents',
                      value: '${filtered.length}',
                      icon: Icons.receipt_long,
                      color: primary,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Invoice Total',
                      value: 'TSH ${_money(invoiceTotalSum)}',
                      icon: Icons.summarize_outlined,
                      color: accent,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    // The stream will be rebuilt, providing a refresh.
                    setState(() {});
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final doc = filtered[i];
                      final data = doc.data();
                      final invoice = (data['invoice'] as Map?) ?? {};
                      final kind = (data['kind']?.toString() ?? 'invoice');
                      final client = (data['client'] as Map?) ?? {};
                      final created = _asDate(data['createdAt']);
                      final total = (data['total'] as num?) ?? 0;

                      return Dismissible(
                        key: ValueKey(doc.id),
                        direction: DismissDirection.horizontal,
                        background: _swipeBg(Alignment.centerLeft),
                        secondaryBackground: _swipeBg(Alignment.centerRight),
                        confirmDismiss: (dir) => _confirmDismiss(context),
                        onDismissed: (_) async {
                          await doc.reference.delete();
                          Get.snackbar(
                            'Deleted',
                            'Invoice removed',
                            snackPosition: SnackPosition.BOTTOM,
                          );
                        },
                        child: Card(
                          elevation: 2,
                          shadowColor: Colors.black.withOpacity(0.05),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _previewPdf(data, kind),
                            onLongPress: () => _showActions(context, doc),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 44,
                                    width: 44,
                                    decoration: BoxDecoration(
                                      color: primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _getIconForKind(kind),
                                      color: primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                '${_getTitleForKind(kind)} #${invoice['number'] ?? doc.id}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            // Updated PopupMenuButton with more options
                                            MenuAnchor(
                                              builder:
                                                  (context, controller, child) {
                                                    return IconButton(
                                                      tooltip: 'Actions',
                                                      onPressed: () {
                                                        if (controller.isOpen) {
                                                          controller.close();
                                                        } else {
                                                          controller.open();
                                                        }
                                                      },
                                                      icon: const Icon(
                                                        Icons.more_vert,
                                                      ),
                                                    );
                                                  },
                                              menuChildren: [
                                                MenuItemButton(
                                                  leadingIcon: const Icon(Icons.edit_outlined),
                                                  child: const Text('Edit'),
                                                  onPressed: () => _editInvoice(doc),
                                                ),
                                                const Divider(),
                                                MenuItemButton(
                                                  leadingIcon: const Icon(
                                                    Icons.visibility_outlined,
                                                  ),
                                                  child: Text(
                                                    'Preview ${_getTitleForKind(kind)}',
                                                  ),
                                                  onPressed: () =>
                                                      _previewPdf(data, kind),
                                                ),
                                                MenuItemButton(
                                                  leadingIcon: const Icon(
                                                    Icons.download_outlined,
                                                  ),
                                                  child: Text(
                                                    'Download ${_getTitleForKind(kind)}',
                                                  ),
                                                  onPressed: () =>
                                                      _savePdf(data, kind),
                                                ),
                                                const Divider(),
                                                SubmenuButton(
                                                  leadingIcon: const Icon(
                                                    Icons.file_copy_outlined,
                                                  ),
                                                  menuChildren: [
                                                    MenuItemButton(
                                                      child: const Text(
                                                        'Invoice',
                                                      ),
                                                      onPressed: () => _savePdf(
                                                        data,
                                                        'invoice',
                                                      ),
                                                    ),
                                                    MenuItemButton(
                                                      child: const Text(
                                                        'Proforma',
                                                      ),
                                                      onPressed: () => _savePdf(
                                                        data,
                                                        'proforma',
                                                      ),
                                                    ),
                                                    MenuItemButton(
                                                      child: const Text(
                                                        'Delivery Note',
                                                      ),
                                                      onPressed: () => _savePdf(
                                                        data,
                                                        'delivery',
                                                      ),
                                                    ),
                                                    MenuItemButton(
                                                      child: const Text(
                                                        'Payment Reminder',
                                                      ),
                                                      onPressed: () => _savePdf(
                                                        data,
                                                        'reminder',
                                                      ),
                                                    ),
                                                    MenuItemButton(
                                                      child: const Text(
                                                        'Advance Payment',
                                                      ),
                                                      onPressed: () => _savePdf(
                                                        data,
                                                        'advance',
                                                      ),
                                                    ),
                                                    MenuItemButton(
                                                      child: const Text(
                                                        'Excel',
                                                      ),
                                                      onPressed: () =>
                                                          _saveAsExcel(data),
                                                    ),
                                                  ],
                                                  child: const Text(
                                                    'Generate As...',
                                                  ),
                                                ),
                                                const Divider(),
                                                MenuItemButton(
                                                  leadingIcon: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red,
                                                  ),
                                                  child: const Text(
                                                    'Delete',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                  onPressed: () async {
                                                    final ok =
                                                        await _confirmDismiss(
                                                          context,
                                                        );
                                                    if (ok == true) {
                                                      await doc.reference
                                                          .delete();
                                                      Get.snackbar(
                                                        'Deleted',
                                                        'Document removed',
                                                        snackPosition:
                                                            SnackPosition
                                                                .BOTTOM,
                                                      );
                                                    }
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          client['name'] ?? 'Unknown client',
                                          style: TextStyle(
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.event,
                                              size: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _fmt(created),
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Icon(
                                              Icons.payment,
                                              size: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              (invoice['paymentMethod'] ?? '')
                                                  .toString(),
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'Total',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        _money(total),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
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

  Widget _swipeBg(Alignment alignment) {
    return Container(
      color: Colors.red.shade600,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }

  Future<bool?> _confirmDismiss(BuildContext context) async {
    return await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete Document?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  static String _money(num v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  IconData _getIconForKind(String kind) {
    return switch (kind) {
      'proforma' => Icons.request_quote_outlined,
      'delivery' => Icons.local_shipping_outlined,
      'reminder' => Icons.alarm_on_outlined,
      'advance' => Icons.payments_outlined,
      _ => Icons.receipt_long, // invoice
    };
  }

  String _getTitleForKind(String kind) {
    return switch (kind) {
      'proforma' => 'Proforma',
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
    // Excel export helper not available in this build; inform the user.
    try {
      // If you have a concrete implementation for Excel export, replace
      // the body of this method with a call to that implementation.
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

  void _showActions(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Preview PDF'),
              onTap: () {
                Navigator.pop(context);
                _previewPdf(doc.data(), doc.data()['kind'] ?? 'invoice');
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download PDF'),
              onTap: () {
                Navigator.pop(context);
                _savePdf(doc.data(), doc.data()['kind'] ?? 'invoice');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(context);
                final ok = await _confirmDismiss(context);
                if (ok != true) return;

                await doc.reference.delete();
                Get.snackbar(
                  'Deleted',
                  'Invoice removed',
                  snackPosition: SnackPosition.BOTTOM,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editInvoice(DocumentSnapshot<Map<String, dynamic>> doc) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => invoice_page.InvoicePage(invoice: doc)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate, required this.onCreateAdvance});

  final VoidCallback onCreate;
  final VoidCallback onCreateAdvance;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No documents yet',
            style: TextStyle(fontSize: 20, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Create New Document'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onCreateAdvance,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Create Advance Invoice'),
          ),
        ],
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
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: Colors.grey.shade600)),
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
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
