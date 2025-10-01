import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // added

import 'InvoicePage.dart';
import '../services/pdf/invoice_pdf.dart';

class InvoicesPage extends StatelessWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Invoices')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              await FirebaseAuth.instance.signInAnonymously();
              Get.snackbar('Signed in', 'Anonymous sign-in complete');
            },
            child: const Text('Sign in to view invoices'),
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
      appBar: AppBar(
        title: const Text('My Invoices'),
        actions: [
          IconButton(
            tooltip: 'New invoice',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const InvoicePage()));
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No invoices yet'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              final invoice = (data['invoice'] as Map?) ?? {};
              final client = (data['client'] as Map?) ?? {};
              final createdAt = data['createdAt'];
              final created = _asDate(createdAt);
              final total = (data['total'] as num?) ?? 0;

              return ListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text('Invoice #${invoice['number'] ?? doc.id}'),
                subtitle: Text(
                  '${client['name'] ?? 'Unknown client'} • ${_fmt(created)}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Total', style: TextStyle(fontSize: 12)),
                    Text(
                      _money(total),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                onTap: () => _savePdf(data), // changed from preview to save
                onLongPress: () => _showActions(context, doc),
              );
            },
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

  static String _money(num v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  void _savePdf(Map<String, dynamic> data) async {
    try {
      final clean = Map<String, dynamic>.from(data);
      final ts = clean['createdAt'];
      if (ts is Timestamp) clean['createdAt'] = ts.toDate().toIso8601String();

      final no = (clean['invoice'] as Map?)?['number']?.toString();
      final fileName =
          'invoice_${(no == null || no.isEmpty) ? DateTime.now().millisecondsSinceEpoch : no}.pdf';

      final pathOrName = await InvoicePdf.generateAndSave(
        clean,
        fileName: fileName,
      );

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

  void _previewPdf(Map<String, dynamic> data) {
    // Preview is not implemented in this build; fall back to saving the PDF.
    // This avoids the missing method compile error and provides a sensible default.
    _savePdf(data);
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
                _previewPdf(doc.data());
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Save PDF'),
              onTap: () {
                Navigator.pop(context);
                _savePdf(doc.data()); // changed action
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(context);
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
}
