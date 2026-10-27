import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'explore_page.dart';
import 'market_models.dart';
import 'market_palette.dart';

final _hashtagPattern = RegExp(r'#([\p{L}\p{N}_]{2,40})', unicode: true);

void openMarketHashtag(String tag) {
  Get.to(() => MarketHashtagPage(hashtag: normalizeHashtag(tag)));
}

class MarketHashtagPage extends StatelessWidget {
  const MarketHashtagPage({super.key, required this.hashtag});

  final String hashtag;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text('#$hashtag'),
        ),
        body: MarketExplorePage(
          initialTab: MarketExploreTab.posts,
          showControls: false,
          initialHashtag: hashtag,
        ),
      ),
    );
  }
}

/// Renders [text] with tappable hashtags.
class HashtagText extends StatefulWidget {
  const HashtagText(this.text, {super.key, this.style, this.collapsedLines});

  final String text;
  final TextStyle? style;
  final int? collapsedLines;

  @override
  State<HashtagText> createState() => _HashtagTextState();
}

class _HashtagTextState extends State<HashtagText> {
  final List<TapGestureRecognizer> _recognizers = [];
  bool _expanded = false;

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _hashtagPattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      final tag = match.group(1)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openMarketHashtag(tag);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: match.group(0),
          recognizer: recognizer,
          style: const TextStyle(
            color: MarketPalette.blue,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    final text = TextSpan(
      children: spans,
      style: widget.style ?? DefaultTextStyle.of(context).style,
    );
    final limit = widget.collapsedLines;
    if (limit == null) return Text.rich(text);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: text,
          maxLines: limit,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        if (!overflows && !_expanded) return Text.rich(text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              text,
              maxLines: _expanded ? null : limit,
              overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  (_expanded ? 'market_read_less' : 'market_read_more').tr,
                  style: const TextStyle(
                    color: MarketPalette.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
