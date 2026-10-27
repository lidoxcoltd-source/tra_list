import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../theme/app_theme.dart';
import 'market_palette.dart';
import 'market_service.dart';

class MarketCommentsSheet extends StatefulWidget {
  const MarketCommentsSheet({super.key, required this.postId});

  final String postId;

  @override
  State<MarketCommentsSheet> createState() => _MarketCommentsSheetState();
}

class _MarketCommentsSheetState extends State<MarketCommentsSheet> {
  final _controller = TextEditingController();
  String? _replyTo;
  bool _sending = false;
  static const _quickReactions = [
    '❤️',
    '🙌',
    '🔥',
    '👏',
    '😢',
    '😍',
    '😮',
    '😂',
  ];

  void _insertReaction(String emoji) {
    final current = _controller.value;
    final selection = current.selection;
    final start = selection.isValid ? selection.start : current.text.length;
    final end = selection.isValid ? selection.end : current.text.length;
    final text = current.text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  String _commentTime(dynamic value) {
    if (value is! Timestamp) return '';
    final difference = DateTime.now().difference(value.toDate());
    if (difference.inMinutes < 1) return 'now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    if (difference.inDays < 7) return '${difference.inDays}d';
    return '${(difference.inDays / 7).floor()}w';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await MarketService.addComment(
        postId: widget.postId,
        body: body,
        parentId: _replyTo,
      );
      _controller.clear();
      if (mounted) setState(() => _replyTo = null);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: .86,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MarketPalette.textMuted.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Center(
                        child: Text(
                          'market_comments'.tr,
                          style: const TextStyle(
                            color: MarketPalette.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: MarketService.watchComments(widget.postId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('market_comment_error'.tr));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final comments = snapshot.data!;
                if (comments.isEmpty) {
                  return Center(child: Text('market_empty_comments'.tr));
                }
                final currentUid = FirebaseAuth.instance.currentUser?.uid;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    final parentId = comment['parentId']?.toString();
                    final commentTime = _commentTime(comment['createdAt']);
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        parentId == null ? 16 : 48,
                        6,
                        16,
                        6,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: MarketPalette.surfaceRaised,
                            child: Text(
                              (comment['authorName'] ?? '?')
                                  .toString()
                                  .characters
                                  .first
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: MarketPalette.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (comment['authorName'] ?? '')
                                            .toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: MarketPalette.text,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      commentTime,
                                      style: const TextStyle(
                                        color: MarketPalette.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  (comment['body'] ?? '').toString(),
                                  style: const TextStyle(
                                    color: MarketPalette.text,
                                    fontSize: 14,
                                    height: 1.35,
                                  ),
                                ),
                                if (parentId == null)
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _replyTo = comment['id'].toString();
                                    }),
                                    style: TextButton.styleFrom(
                                      foregroundColor: MarketPalette.textMuted,
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      textStyle: const TextStyle(fontSize: 12),
                                    ),
                                    child: Text('market_reply'.tr),
                                  ),
                              ],
                            ),
                          ),
                          if (comment['authorUid'] == currentUid)
                            IconButton(
                              tooltip: 'market_delete_comment'.tr,
                              onPressed: () async {
                                try {
                                  await MarketService.deleteComment(
                                    widget.postId,
                                    comment['id'].toString(),
                                  );
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$error')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.delete_outline, size: 18),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_replyTo != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _replyTo = null),
                  icon: const Icon(Icons.close, size: 16),
                  label: Text('market_replying'.tr),
                ),
              ),
            ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _quickReactions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) => InkWell(
                onTap: () => _insertReaction(_quickReactions[index]),
                borderRadius: BorderRadius.circular(20),
                child: Center(
                  child: Text(
                    _quickReactions[index],
                    style: const TextStyle(fontSize: 25),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            maxLength,
                            required isFocused,
                          }) => const SizedBox.shrink(),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'market_write_comment'.tr,
                        isDense: true,
                        filled: true,
                        fillColor: MarketPalette.surfaceRaised,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: MarketPalette.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: MarketPalette.border,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    tooltip: 'market_send_comment'.tr,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
