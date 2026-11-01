import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:tra_list/invoice/invoice_share_service.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class SharedDocumentPage extends StatefulWidget {
  const SharedDocumentPage({super.key, required this.token});

  final String token;

  @override
  State<SharedDocumentPage> createState() => _SharedDocumentPageState();
}

class _SharedDocumentPageState extends State<SharedDocumentPage> {
  late final Future<Map<String, dynamic>?> _document = _loadDocument();

  Future<Map<String, dynamic>?> _loadDocument() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('sharedDocuments')
        .doc(widget.token)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null || data['active'] != true) return null;
    return data;
  }

  Future<void> _download({
    required Map<String, dynamic> document,
    required String kind,
    required String downloadUrl,
  }) async {
    try {
      if (downloadUrl.isNotEmpty) {
        final opened = await launchUrl(
          Uri.parse(downloadUrl),
          mode: LaunchMode.externalApplication,
        );
        if (opened || !mounted) return;
      }

      final bytes = await InvoiceShareService.generatePdfBytes(document, kind);
      final opened = await Printing.sharePdf(
        bytes: bytes,
        filename: InvoiceShareService.fileName(kind, document),
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not download the document PDF.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not prepare the PDF: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _document,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _MessageState(
                title: 'Document unavailable',
                message:
                    'We could not load this document. Please contact the sender for a new link.',
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(
                  color: MjasiColors.primaryBlue,
                ),
              );
            }
            final share = snapshot.data;
            if (share == null) {
              return const _MessageState(
                title: 'This link is no longer available',
                message:
                    'The sender may have revoked access. Please contact them for an updated document.',
              );
            }
            final document =
                (share['document'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            final company =
                (document['company'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            final client =
                (document['client'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            final invoice =
                (document['invoice'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            final terms =
                (document['documentTerms'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            final items = (document['items'] as List?) ?? const [];
            final kind = (share['kind'] ?? 'invoice').toString().replaceAll(
              '_',
              ' ',
            );
            final number = (invoice['number'] ?? '').toString();

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SharedDocumentPreview(
                      document: document,
                      company: company,
                      client: client,
                      invoice: invoice,
                      terms: terms,
                      items: items,
                      kind: kind,
                      number: number,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _download(
                        document: document,
                        kind: (share['kind'] ?? 'invoice').toString(),
                        downloadUrl: (share['downloadUrl'] ?? '').toString(),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download PDF'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        backgroundColor: MjasiColors.primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(MjasiRadius.md),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This document was shared with you securely by the business shown above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MjasiColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static String _formatDate(dynamic value) {
    if (value is Timestamp)
      return DateFormat('d MMM yyyy').format(value.toDate());
    if (value is DateTime) return DateFormat('d MMM yyyy').format(value);
    if (value is String) {
      final date = DateTime.tryParse(value);
      if (date != null) return DateFormat('d MMM yyyy').format(date);
      return value;
    }
    return value.toString();
  }

  static String _money(num value) => value
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

class _SharedDocumentPreview extends StatelessWidget {
  const _SharedDocumentPreview({
    required this.document,
    required this.company,
    required this.client,
    required this.invoice,
    required this.terms,
    required this.items,
    required this.kind,
    required this.number,
  });

  final Map<String, dynamic> document;
  final Map<String, dynamic> company;
  final Map<String, dynamic> client;
  final Map<String, dynamic> invoice;
  final Map<String, dynamic> terms;
  final List items;
  final String kind;
  final String number;

  @override
  Widget build(BuildContext context) {
    final savedDesign =
        (document['documentDesign'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final style = (savedDesign['style'] ?? 'classic').toString();
    final brand = _designColor(savedDesign['brand'], MjasiColors.primaryBlue);
    final accent = _designColor(savedDesign['accent'], brand);
    final footer = _designColor(savedDesign['footer'], MjasiColors.textPrimary);
    final tint = Color.lerp(brand, Colors.white, .92)!;
    final isMinimal = style == 'minimal' || style == 'corner';
    final headerColor = style == 'elegant'
        ? Color.lerp(brand, Colors.black, .35)!
        : brand;
    final textOnBrand = headerColor.computeLuminance() < .42
        ? Colors.white
        : Colors.black87;
    final companyName = (company['name'] ?? 'Business document').toString();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: style == 'ledger' || style == 'tinted' ? tint : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brand.withValues(alpha: .24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160D2B52),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _styleAccent(style, brand, accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _companyLogo(company),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            kind.toUpperCase(),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: brand,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          if (number.isNotEmpty)
                            Text(
                              '#$number',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                color: footer.withValues(alpha: .72),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            companyName,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: footer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          for (final detail in [
                            company['address'],
                            company['email'],
                            company['phone'],
                            if ((company['taxId'] ?? '').toString().isNotEmpty)
                              'Tax ID: ${company['taxId']}',
                          ])
                            if ((detail ?? '').toString().trim().isNotEmpty)
                              Text(
                                detail.toString(),
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  color: footer.withValues(alpha: .68),
                                  fontSize: 12,
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: style == 'elegant' ? tint : Colors.transparent,
                    border: Border(
                      top: BorderSide(color: brand.withValues(alpha: .22)),
                      bottom: BorderSide(color: brand.withValues(alpha: .22)),
                    ),
                  ),
                  child: Wrap(
                    spacing: 26,
                    runSpacing: 12,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      _DocumentMeta(
                        label: 'BILL TO',
                        value: (client['name'] ?? '').toString().isEmpty
                            ? 'Customer'
                            : client['name'].toString(),
                        color: footer,
                      ),
                      if (invoice['issueDate'] != null)
                        _DocumentMeta(
                          label: 'DATE',
                          value: _SharedDocumentPageState._formatDate(
                            invoice['issueDate'],
                          ),
                          color: footer,
                        ),
                      if (invoice['dueDate'] != null)
                        _DocumentMeta(
                          label: 'DUE DATE',
                          value: _SharedDocumentPageState._formatDate(
                            invoice['dueDate'],
                          ),
                          color: footer,
                        ),
                      if ((invoice['paymentMethod'] ?? '')
                          .toString()
                          .isNotEmpty)
                        _DocumentMeta(
                          label: 'PAYMENT',
                          value: invoice['paymentMethod'].toString(),
                          color: footer,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _itemsTable(
                  brand: brand,
                  headerColor: headerColor,
                  textOnBrand: textOnBrand,
                  footer: footer,
                  isMinimal: isMinimal,
                  style: style,
                  compact: MediaQuery.sizeOf(context).width < 540,
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      children: [
                        if (document['subtotal'] is num)
                          _TotalLine(
                            label: 'Subtotal',
                            value: document['subtotal'] as num,
                            color: footer,
                          ),
                        if (document['tax'] is num)
                          _TotalLine(
                            label: 'Tax',
                            value: document['tax'] as num,
                            color: footer,
                          ),
                        if (document['advancePaid'] is num)
                          _TotalLine(
                            label: 'Advance paid',
                            value: document['advancePaid'] as num,
                            color: footer,
                          ),
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isMinimal ? Colors.transparent : headerColor,
                            border: isMinimal
                                ? Border(
                                    top: BorderSide(color: brand, width: 1.5),
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(
                              style == 'classic' ? 8 : 3,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'TOTAL',
                                  style: TextStyle(
                                    color: isMinimal ? footer : textOnBrand,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                'TSH ${_SharedDocumentPageState._money((document['total'] as num?) ?? 0)}',
                                style: TextStyle(
                                  color: isMinimal ? brand : textOnBrand,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (terms.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  for (final entry in const [
                    ('conditions', 'Terms & conditions'),
                    ('note', 'Note'),
                    ('delivery', 'Delivery'),
                  ])
                    if ((terms[entry.$1] ?? '').toString().trim().isNotEmpty)
                      _TermText(
                        title: entry.$2,
                        text: terms[entry.$1].toString(),
                      ),
                ],
                if ((company['website'] ?? '').toString().isNotEmpty ||
                    (company['beneficiary'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Divider(color: brand.withValues(alpha: .25)),
                  Text(
                    [
                      if ((company['website'] ?? '').toString().isNotEmpty)
                        company['website'].toString(),
                      if ((company['beneficiary'] ?? '').toString().isNotEmpty)
                        'Payable to ${company['beneficiary']}',
                    ].join('   •   '),
                    style: TextStyle(color: footer.withValues(alpha: .72)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _styleAccent(String style, Color brand, Color accent) {
    if (style == 'corner') {
      return Row(
        children: [
          Container(width: 8, height: 6, color: brand),
          Expanded(child: Container(height: 6, color: Colors.white)),
          Container(width: 24, height: 6, color: accent),
        ],
      );
    }
    if (style == 'band') {
      return Row(
        children: [
          Expanded(child: Container(height: 8, color: brand)),
          Container(width: 8, height: 8, color: accent),
        ],
      );
    }
    if (style == 'modern') {
      return Container(height: 4, color: brand);
    }
    if (style == 'elegant' || style == 'ledger') {
      return Container(height: 7, color: brand);
    }
    if (const {'dots', 'stripes', 'grid', 'tinted'}.contains(style)) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [brand, accent]),
        ),
      );
    }
    return const SizedBox(height: 4);
  }

  Widget _companyLogo(Map<String, dynamic> company) {
    final logoUrl = (company['logoUrl'] ?? '').toString().trim();
    if (logoUrl.isEmpty) return const SizedBox(width: 4);
    return SizedBox(
      width: 104,
      height: 64,
      child: Image.network(
        logoUrl,
        fit: BoxFit.contain,
        cacheWidth: 312,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            frame == null && !wasSynchronouslyLoaded
            ? const Center(
                child: Icon(
                  Icons.business_rounded,
                  color: MjasiColors.textSecondary,
                  size: 28,
                ),
              )
            : child,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Could not load shared company logo: $error');
          return const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: MjasiColors.textSecondary,
              size: 24,
            ),
          );
        },
      ),
    );
  }

  Widget _itemsTable({
    required Color brand,
    required Color headerColor,
    required Color textOnBrand,
    required Color footer,
    required bool isMinimal,
    required String style,
    required bool compact,
  }) {
    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: isMinimal ? Colors.transparent : headerColor,
        border: isMinimal
            ? Border(bottom: BorderSide(color: brand, width: 1.5))
            : null,
        borderRadius: BorderRadius.circular(
          style == 'classic'
              ? 7
              : style == 'elegant'
              ? 4
              : 0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _tableLabel('ITEM', isMinimal ? footer : textOnBrand),
          ),
          if (!compact) ...[
            SizedBox(
              width: 48,
              child: _tableLabel(
                'QTY',
                isMinimal ? footer : textOnBrand,
                align: TextAlign.center,
              ),
            ),
            SizedBox(
              width: 92,
              child: _tableLabel(
                'PRICE',
                isMinimal ? footer : textOnBrand,
                align: TextAlign.end,
              ),
            ),
          ],
          SizedBox(
            width: compact ? 100 : 104,
            child: _tableLabel(
              'AMOUNT',
              isMinimal ? footer : textOnBrand,
              align: TextAlign.end,
            ),
          ),
        ],
      ),
    );
    return Column(
      children: [
        header,
        for (var index = 0; index < items.length; index++)
          if (items[index] is Map)
            _TableItemRow(
              item: items[index] as Map,
              brand: brand,
              footer: footer,
              compact: compact,
              borderColor: brand.withValues(alpha: .16),
              highlight: style == 'ledger' && index.isEven
                  ? brand.withValues(alpha: .06)
                  : Colors.transparent,
            ),
      ],
    );
  }

  Widget _tableLabel(
    String text,
    Color color, {
    TextAlign align = TextAlign.start,
  }) => Text(
    text,
    textAlign: align,
    style: TextStyle(
      color: color,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: .5,
    ),
  );

  static Color _designColor(Object? value, Color fallback) {
    if (value is! num) return fallback;
    final colorValue = value.toInt();
    return Color(colorValue <= 0xFFFFFF ? colorValue | 0xFF000000 : colorValue);
  }
}

class _DocumentMeta extends StatelessWidget {
  const _DocumentMeta({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 145,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: .62),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: .45,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _TableItemRow extends StatelessWidget {
  const _TableItemRow({
    required this.item,
    required this.brand,
    required this.footer,
    required this.compact,
    required this.borderColor,
    required this.highlight,
  });

  final Map item;
  final Color brand;
  final Color footer;
  final bool compact;
  final Color borderColor;
  final Color highlight;

  @override
  Widget build(BuildContext context) {
    final quantity = (item['qty'] as num?) ?? 1;
    final unit = (item['unit'] as num?) ?? 0;
    final amount = (item['amount'] as num?) ?? quantity * unit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      decoration: BoxDecoration(
        color: highlight,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (item['description'] ?? 'Item').toString(),
                  style: TextStyle(color: footer, fontWeight: FontWeight.w500),
                ),
                if (compact) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${_quantityText(quantity)} × TSH ${_money(unit)}',
                    style: TextStyle(
                      color: footer.withValues(alpha: .72),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!compact) ...[
            SizedBox(
              width: 48,
              child: Text(
                _quantityText(quantity),
                textAlign: TextAlign.center,
                style: TextStyle(color: footer.withValues(alpha: .8)),
              ),
            ),
            SizedBox(
              width: 92,
              child: Text(
                _money(unit),
                textAlign: TextAlign.end,
                style: TextStyle(color: footer.withValues(alpha: .8)),
              ),
            ),
          ],
          SizedBox(
            width: compact ? 100 : 104,
            child: Text(
              'TSH ${_money(amount)}',
              textAlign: TextAlign.end,
              style: TextStyle(color: brand, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  static String _quantityText(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  static String _money(num value) => value
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final num value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: color)),
        ),
        Text(
          'TSH ${_SharedDocumentPageState._money(value)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _TermText extends StatelessWidget {
  const _TermText({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: MjasiColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: const TextStyle(
              color: MjasiColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.description_outlined,
              color: MjasiColors.primaryBlue,
              size: 44,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MjasiColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MjasiColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
