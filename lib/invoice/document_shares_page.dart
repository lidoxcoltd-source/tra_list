import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:tra_list/invoice/document_share_sheet.dart';
import 'package:tra_list/invoice/invoice_share_service.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/theme/app_theme.dart';

class DocumentSharesPage extends StatelessWidget {
  const DocumentSharesPage({super.key, required this.businessUid});

  final String businessUid;

  Query<Map<String, dynamic>> _query() {
    final modules = [
      if (BusinessAccessService.can('invoices', 'view')) 'invoices',
      if (BusinessAccessService.can('quotations', 'view')) 'quotations',
    ];
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(businessUid)
        .collection('documentShares');
    if (modules.isEmpty) {
      return collection.where('module', isEqualTo: '__no_access__').limit(1);
    }
    return modules.length == 1
        ? collection.where('module', isEqualTo: modules.single).limit(300)
        : collection.where('module', whereIn: modules).limit(300);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      appBar: AppBar(title: const Text('Sent documents')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _query().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load sent documents: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final shares = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final aDate = _date(a.data()['sharedAt']);
              final bDate = _date(b.data()['sharedAt']);
              return (bDate ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(aDate ?? DateTime.fromMillisecondsSinceEpoch(0));
            });
          final opened = shares
              .where((share) => share.data()['status'] == 'whatsapp_opened')
              .toList();
          final totalShared = opened.fold<num>(
            0,
            (total, share) => total + ((share.data()['total'] as num?) ?? 0),
          );
          final chart = _lastSixMonths(opened);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'WhatsApp opened',
                      value: '${opened.length}',
                      icon: Icons.send_rounded,
                      color: const Color(0xFF168A62),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      label: 'Shared value',
                      value: 'TSH ${_money(totalShared)}',
                      icon: Icons.account_balance_wallet_outlined,
                      color: MjasiColors.primaryBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ChartCard(chart: chart),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 18, 4, 10),
                child: Text(
                  'Share history',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: MjasiColors.textPrimary,
                  ),
                ),
              ),
              if (shares.isEmpty)
                const _EmptyShares()
              else
                for (final share in shares)
                  _ShareHistoryCard(
                    businessUid: businessUid,
                    data: share.data(),
                  ),
              const SizedBox(height: 20),
              const Text(
                '“WhatsApp opened” means the message composer opened. The customer message is sent only after you confirm it in WhatsApp.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MjasiColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static List<_MonthShare> _lastSixMonths(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> shares,
  ) {
    final now = DateTime.now();
    final months = List.generate(
      6,
      (index) => DateTime(now.year, now.month - 5 + index),
    );
    final counts = <DateTime, int>{for (final month in months) month: 0};
    for (final share in shares) {
      final date = _date(share.data()['sharedAt']);
      if (date == null) continue;
      final month = DateTime(date.year, date.month);
      if (counts.containsKey(month)) counts[month] = counts[month]! + 1;
    }
    return [
      for (final month in months)
        _MonthShare(DateFormat('MMM').format(month), counts[month] ?? 0),
    ];
  }

  static String _money(num value) => value
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

class _MonthShare {
  const _MonthShare(this.label, this.count);
  final String label;
  final int count;
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.chart});
  final List<_MonthShare> chart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: MjasiColors.surface,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        border: Border.all(color: MjasiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WhatsApp shares by month',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: SfCartesianChart(
              margin: EdgeInsets.zero,
              primaryXAxis: CategoryAxis(
                majorGridLines: const MajorGridLines(width: 0),
              ),
              primaryYAxis: NumericAxis(
                minimum: 0,
                interval: 1,
                majorGridLines: MajorGridLines(
                  color: MjasiColors.border.withOpacity(.8),
                ),
              ),
              series: <CartesianSeries<_MonthShare, String>>[
                ColumnSeries<_MonthShare, String>(
                  dataSource: chart,
                  xValueMapper: (point, _) => point.label,
                  yValueMapper: (point, _) => point.count,
                  color: MjasiColors.primaryBlue,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  width: .55,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
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
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MjasiColors.surface,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        border: Border.all(color: MjasiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MjasiColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: MjasiColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareHistoryCard extends StatelessWidget {
  const _ShareHistoryCard({
    required this.businessUid,
    required this.data,
  });

  final String businessUid;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final revoked = data['linkRevoked'] == true;
    final module = (data['module'] ?? 'invoices').toString();
    final canManage = BusinessAccessService.can(module, 'create') ||
        BusinessAccessService.can(module, 'edit');
    final date = DocumentSharesPage._date(data['sharedAt']);
    final status = (data['status'] ?? 'link_ready').toString();
    final token = (data['shareToken'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: MjasiColors.surface,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        border: Border.all(color: MjasiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7F0),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.chat_rounded,
                    color: Color(0xFF168A62),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (data['recipientName']?.toString().trim().isNotEmpty ??
                                false)
                            ? data['recipientName'].toString()
                            : (data['recipientPhone'] ?? 'Customer').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: MjasiColors.textPrimary,
                        ),
                      ),
                      Text(
                        data['recipientPhone']?.toString() ?? '',
                        style: const TextStyle(
                          color: MjasiColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManage && !revoked)
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'send' && !revoked) {
                        showDocumentShareSheet(
                          context: context,
                          businessUid: businessUid,
                          documentId:
                              (data['sourceDocumentId'] ?? '').toString(),
                          existingToken: token,
                          suggestedName: data['recipientName']?.toString(),
                          suggestedPhone: data['recipientPhone']?.toString(),
                          document: {
                            'kind': data['kind'],
                            'invoice': {'number': data['documentNumber']},
                            'client': {'name': data['clientName']},
                            'total': data['total'],
                          },
                        );
                      } else if (action == 'revoke') {
                        _confirmRevoke(context);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'send',
                        child: Text('Send again'),
                      ),
                      const PopupMenuItem(
                        value: 'revoke',
                        child: Text('Revoke customer link'),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${(data['kind'] ?? 'invoice').toString().replaceAll('_', ' ').toUpperCase()}  #${data['documentNumber'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MjasiColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'TSH ${DocumentSharesPage._money((data['total'] as num?) ?? 0)}',
                  style: const TextStyle(
                    color: MjasiColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  revoked
                      ? Icons.link_off_rounded
                      : status == 'whatsapp_opened'
                      ? Icons.done_rounded
                      : Icons.link_rounded,
                  size: 16,
                  color: revoked
                      ? MjasiColors.error
                      : status == 'whatsapp_opened'
                      ? const Color(0xFF168A62)
                      : MjasiColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    revoked
                        ? 'Link revoked'
                        : status == 'whatsapp_opened'
                        ? 'WhatsApp opened'
                        : 'Link ready; not sent',
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  date == null ? 'Just now' : DateFormat('d MMM, h:mm a').format(date),
                  style: const TextStyle(
                    color: MjasiColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke customer link?'),
        content: const Text(
          'The customer will no longer be able to open the invoice page or download its PDF from this link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await InvoiceShareService.revoke(
        businessUid: businessUid,
        token: (data['shareToken'] ?? '').toString(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer link revoked.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not revoke link: $error')),
        );
      }
    }
  }
}

class _EmptyShares extends StatelessWidget {
  const _EmptyShares();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: MjasiColors.surface,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        border: Border.all(color: MjasiColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.send_outlined, size: 36, color: MjasiColors.textSecondary),
          SizedBox(height: 12),
          Text(
            'No shared documents yet',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            'Documents you share through WhatsApp will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MjasiColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
