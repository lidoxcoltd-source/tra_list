import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'market_models.dart';
import 'market_palette.dart';
import 'market_service.dart';

class AdminMarketReportsPage extends StatefulWidget {
  const AdminMarketReportsPage({super.key});

  @override
  State<AdminMarketReportsPage> createState() => _AdminMarketReportsPageState();
}

class _AdminMarketReportsPageState extends State<AdminMarketReportsPage> {
  bool _showOpen = true;

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _resolve(
    String reportId, {
    required String status,
    String? deletePostId,
  }) async {
    try {
      await MarketService.resolveMarketReport(
        reportId,
        status: status,
        deletePostId: deletePostId,
      );
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _confirmRemove(String reportId, String postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('market_report_admin_remove'.tr),
        content: Text('market_delete_post_confirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _resolve(reportId, status: 'removed', deletePostId: postId);
    }
  }

  String _reasonLabel(String reason) => switch (reason) {
    'spam' => 'market_report_spam'.tr,
    'unsafe' => 'market_report_unsafe'.tr,
    _ => 'market_report_other'.tr,
  };

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        appBar: AppBar(
          backgroundColor: MarketPalette.topBar,
          foregroundColor: Colors.white,
          title: Text('market_report_admin_title'.tr),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text('market_report_admin_open'.tr),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('market_report_admin_closed'.tr),
                  ),
                ],
                selected: {_showOpen},
                onSelectionChanged: (value) =>
                    setState(() => _showOpen = value.first),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: MarketService.watchMarketReports(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('explore_error'.tr));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs.where((doc) {
                    final open = (doc.data()['status'] ?? 'open') == 'open';
                    return open == _showOpen;
                  }).toList();
                  if (docs.isEmpty) {
                    return Center(child: Text('market_report_admin_empty'.tr));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final postId = (data['postId'] ?? '').toString();
                      final created = (data['createdAt'] as Timestamp?)
                          ?.toDate();
                      return Card(
                        color: MarketPalette.surface,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.flag_rounded,
                                    color: MarketPalette.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _reasonLabel(
                                        (data['reason'] ?? '').toString(),
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (created != null)
                                    Text(
                                      DateFormat(
                                        'dd MMM, HH:mm',
                                      ).format(created),
                                      style: const TextStyle(
                                        color: MarketPalette.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              FutureBuilder<MarketPost?>(
                                future: MarketService.getPost(postId),
                                builder: (context, postSnapshot) {
                                  final post = postSnapshot.data;
                                  if (postSnapshot.connectionState !=
                                      ConnectionState.done) {
                                    return const LinearProgressIndicator();
                                  }
                                  if (post == null) {
                                    return Text(
                                      'market_post_unavailable'.tr,
                                      style: const TextStyle(
                                        color: MarketPalette.textMuted,
                                      ),
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (post.images.isNotEmpty)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.network(
                                            post.images.first,
                                            width: 72,
                                            height: 72,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                const SizedBox(
                                                  width: 72,
                                                  height: 72,
                                                  child: Icon(
                                                    Icons.broken_image_outlined,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              post.authorName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (post.caption.isNotEmpty)
                                              Text(
                                                post.caption,
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              if (_showOpen) ...[
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          _resolve(doc.id, status: 'dismissed'),
                                      child: Text(
                                        'market_report_admin_dismiss'.tr,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: MarketPalette.red,
                                      ),
                                      onPressed: () =>
                                          _confirmRemove(doc.id, postId),
                                      child: Text(
                                        'market_report_admin_remove'.tr,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
