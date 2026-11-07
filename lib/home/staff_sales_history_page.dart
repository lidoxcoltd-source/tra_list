import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:tra_list/services/pdf/pdf_saver.dart' as pdf_saver;
import 'package:tra_list/theme/app_theme.dart';

class StaffSalesHistoryPage extends StatefulWidget {
  const StaffSalesHistoryPage({
    super.key,
    required this.staffUid,
    required this.staffName,
    required this.photoUrl,
    this.shopNickname = '',
  });

  final String staffUid;
  final String staffName;
  final String photoUrl;
  final String shopNickname;

  @override
  State<StaffSalesHistoryPage> createState() => _StaffSalesHistoryPageState();
}

class _StaffSalesHistoryPageState extends State<StaffSalesHistoryPage> {
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _history;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _history = _loadHistory();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadHistory() async {
    final invoices = FirebaseFirestore.instance
        .collection('users')
        .doc(BusinessAccessService.businessId)
        .collection('invoices');
    final results = await Future.wait([
      invoices.where('uid', isEqualTo: widget.staffUid).limit(300).get(),
      invoices.where('cashierUid', isEqualTo: widget.staffUid).limit(300).get(),
    ]);
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final result in results) {
      for (final doc in result.docs) {
        final data = doc.data();
        if (data['kind'] == 'quotation') continue;
        final shop = (data['shopNickname'] ?? '').toString();
        if (widget.shopNickname.isNotEmpty && shop.isNotEmpty && shop != widget.shopNickname) continue;
        byId[doc.id] = doc;
      }
    }
    final docs = byId.values.toList();
    docs.sort((a, b) => _date(b.data()).compareTo(_date(a.data())));
    return docs;
  }

  DateTime _date(Map<String, dynamic> data) {
    final value = data['createdAt'] ?? data['receiptTime'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _money(num amount) => amount.toStringAsFixed(0).replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );

  Future<Uint8List> _pdf(Map<String, dynamic> data) => InvoicePdf.generateBytes(data);

  Future<void> _preview(Map<String, dynamic> data, String fileName) async {
    final bytes = await _pdf(data);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 600,
          height: MediaQuery.sizeOf(context).height * .86,
          child: PdfPreview(
            build: (_) async => bytes,
            pdfFileName: fileName,
            canChangePageFormat: false,
            canChangeOrientation: false,
            allowSharing: true,
            maxPageWidth: 520,
          ),
        ),
      ),
    );
  }

  Future<void> _print(Map<String, dynamic> data) async {
    final bytes = await _pdf(data);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _save(Map<String, dynamic> data, String fileName) async {
    final bytes = await _pdf(data);
    await pdf_saver.savePdf(bytes, fileName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Risiti imehifadhiwa: $fileName')),
      );
    }
  }

  Future<void> _runAction(
    String id,
    Future<void> Function() action,
  ) async {
    setState(() => _busyId = id);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imeshindikana: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MjasiColors.background,
    appBar: AppBar(
      title: Text('Historia ya mauzo · ${widget.staffName}'),
      backgroundColor: MjasiColors.primaryNavy,
      foregroundColor: Colors.white,
    ),
    body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Imeshindikana kupakia historia: ${snapshot.error}'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!;
        if (docs.isEmpty) {
          return const Center(child: Text('Hakuna risiti za mauzo zilizopatikana.'));
        }
        final total = docs.fold<double>(0, (sum, doc) => sum + ((doc.data()['total'] as num?)?.toDouble() ?? 0));
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: MjasiColors.primaryNavy, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.white24,
                  foregroundImage: widget.photoUrl.isEmpty
                      ? null
                      : NetworkImage(widget.photoUrl),
                  onForegroundImageError: widget.photoUrl.isEmpty
                      ? null
                      : (_, _) {},
                  child: widget.photoUrl.isEmpty
                      ? const Icon(Icons.person_outline, color: Colors.white, size: 34)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.staffName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('${docs.length} risiti', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('JUMLA YA MAUZO', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w700)),
                  Text('TZS ${_money(total)}', style: const TextStyle(color: Color(0xFF34D399), fontSize: 16, fontWeight: FontWeight.w900)),
                ]),
              ]),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();
                final invoice = Map<String, dynamic>.from(data['invoice'] as Map? ?? const {});
                final number = (invoice['number'] ?? data['invoiceNumber'] ?? doc.id).toString();
                final customer = ((data['client'] as Map?)?['name'] ?? data['customerName'] ?? 'Mteja').toString();
                final items = (data['items'] as List? ?? const [])
                    .whereType<Map>()
                    .map((item) {
                      final name = (item['description'] ?? item['name'] ?? 'Bidhaa').toString();
                      final quantity = item['qty'] ?? item['quantity'] ?? 0;
                      return '$name × $quantity';
                    })
                    .toList();
                final date = _date(data);
                final busy = _busyId == doc.id;
                final fileName = 'Risiti_${number.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.pdf';
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: MjasiColors.border)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.receipt_long_outlined, color: MjasiColors.primaryBlue),
                        const SizedBox(width: 8),
                        Expanded(child: Text(number, style: const TextStyle(fontWeight: FontWeight.w800, color: MjasiColors.primaryNavy))),
                        Text('TZS ${_money((data['total'] as num?) ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w900, color: MjasiColors.success)),
                      ]),
                      const SizedBox(height: 6),
                      Text('$customer  ·  ${date.millisecondsSinceEpoch == 0 ? 'Tarehe haipo' : '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'}', style: const TextStyle(fontSize: 12, color: MjasiColors.textSecondary)),
                      if (items.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(items.take(3).join('  ·  ') + (items.length > 3 ? '  +${items.length - 3}' : ''), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: MjasiColors.textPrimary)),
                      ],
                      const Divider(height: 18),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        TextButton.icon(onPressed: busy ? null : () => _runAction(doc.id, () => _preview(data, fileName)), icon: const Icon(Icons.visibility_outlined), label: const Text('Preview')),
                        TextButton.icon(onPressed: busy ? null : () => _runAction(doc.id, () => _print(data)), icon: const Icon(Icons.print_outlined), label: const Text('Print')),
                        TextButton.icon(onPressed: busy ? null : () => _runAction(doc.id, () => _save(data, fileName)), icon: const Icon(Icons.download_outlined), label: const Text('Hifadhi risiti')),
                      ]),
                      if (busy) const LinearProgressIndicator(minHeight: 2),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    ),
  );
}
