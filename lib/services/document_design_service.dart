import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/profile_service.dart';

/// Layout styles a document can use. Colors are chosen separately.
class DocumentDesignStyle {
  const DocumentDesignStyle(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;
}

class DocumentDesignService {
  DocumentDesignService._();

  static const documentTypes = <String, String>{
    'invoice': 'Invoice',
    'proforma': 'Proforma',
    'quotation': 'Quotation',
    'advance_payment': 'Advance Payment',
    'delivery_note': 'Delivery Note',
  };

  static const styles = <DocumentDesignStyle>[
    DocumentDesignStyle(
      'classic',
      'Classic',
      'Rounded color table header, clean open layout.',
    ),
    DocumentDesignStyle(
      'modern',
      'Modern',
      'Bold underlined header and square table header.',
    ),
    DocumentDesignStyle(
      'minimal',
      'Minimal',
      'No fills. Thin lines and colored text only.',
    ),
    DocumentDesignStyle(
      'elegant',
      'Elegant',
      'Tinted header panel and a deep-tone table header.',
    ),
    DocumentDesignStyle(
      'tinted',
      'Color wash',
      'Soft full-page color background.',
    ),
    DocumentDesignStyle(
      'dots',
      'Dotted',
      'Light color background with a dot texture.',
    ),
    DocumentDesignStyle(
      'stripes',
      'Stripes',
      'Light color background with diagonal stripes.',
    ),
    DocumentDesignStyle(
      'grid',
      'Grid paper',
      'Light color background with a fine grid texture.',
    ),
    DocumentDesignStyle(
      'band',
      'Color band',
      'Bold color strip across the top and a side bar.',
    ),
    DocumentDesignStyle(
      'ledger',
      'Sales book',
      'Boxed table on a light wash, like a printed sales book.',
    ),
    DocumentDesignStyle(
      'corner',
      'Corner accent',
      'Dark side bar, angled color corners and clean lines.',
    ),
  ];

  static const palette = <int>[
    0xFFF15A24,
    0xFF1976D2,
    0xFF2E7D32,
    0xFF6A1B9A,
    0xFF00796B,
    0xFFC62828,
    0xFF0D2B52,
    0xFF37474F,
  ];

  static const defaultBrand = 0xFFF15A24;
  static const defaultAccent = 0xFF1976D2;
  static const defaultFooter = 0xFF424242;

  static bool isKnownStyle(String id) => styles.any((s) => s.id == id);

  /// Resolves the saved design for [documentType]. Missing values fall back
  /// to the business profile colors so existing documents look unchanged.
  static Map<String, dynamic> selectedFor(
    Map<String, dynamic> profile,
    String documentType,
  ) {
    final colors = Map<String, dynamic>.from(profile['colors'] as Map? ?? {});
    final saved = Map<String, dynamic>.from(
      (profile['documentDesigns'] as Map?)?[documentType] as Map? ?? {},
    );
    final style = saved['style']?.toString() ?? '';
    return {
      'style': isKnownStyle(style) ? style : 'classic',
      'brand': _color(saved['brand'], _color(colors['brand'], defaultBrand)),
      'accent': _color(
        saved['accent'],
        _color(colors['accent'], defaultAccent),
      ),
      'footer': _color(
        saved['footer'],
        _color(colors['footer'], defaultFooter),
      ),
    };
  }

  static Future<Map<String, dynamic>> applySelected(
    Map<String, dynamic> data,
    String documentType,
  ) async {
    final suppliedDesign = data['documentDesign'];
    if (suppliedDesign is Map) {
      return {
        ...data,
        'documentDesign': Map<String, dynamic>.from(suppliedDesign),
      };
    }
    var profile = Map<String, dynamic>.from(data['company'] as Map? ?? {});
    if (BusinessAccessService.canReadBusinessProfile()) {
      profile = await ProfileService.loadOrCreate();
    }
    return {...data, 'documentDesign': selectedFor(profile, documentType)};
  }

  static int _color(Object? value, int fallback) =>
      value is int ? value : fallback;
}

/// Pdf-side design: turns the saved choice into decorations and colors.
class DocumentDesign {
  const DocumentDesign({
    required this.style,
    required this.brand,
    required this.accent,
    required this.footer,
  });

  final String style;
  final PdfColor brand;
  final PdfColor accent;
  final PdfColor footer;

  factory DocumentDesign.fromData(
    Map<String, dynamic> data,
    Map<String, dynamic> company,
  ) {
    final saved =
        (data['documentDesign'] as Map?)?.cast<String, dynamic>() ??
        DocumentDesignService.selectedFor(company, '');
    return DocumentDesign(
      style: saved['style']?.toString() ?? 'classic',
      brand: PdfColor.fromInt(saved['brand'] as int),
      accent: PdfColor.fromInt(saved['accent'] as int),
      footer: PdfColor.fromInt(saved['footer'] as int),
    );
  }

  bool get lightTableHeader => style == 'minimal' || style == 'corner';

  bool get hasBackground => const {
    'tinted',
    'dots',
    'stripes',
    'grid',
    'band',
    'ledger',
    'corner',
  }.contains(style);

  /// A4 page with an optional colored/textured background behind the content.
  pw.PageTheme pageTheme() => pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.only(top: 36),
    buildBackground: hasBackground
        ? (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.CustomPaint(painter: _paintBackground),
          )
        : null,
  );

  void _paintBackground(PdfGraphics c, PdfPoint size) {
    final w = size.x;
    final h = size.y;
    final washAmount = style == 'tinted' ? 0.9 : 0.95;
    if (style == 'ledger') {
      c
        ..setFillColor(_mix(brand, 0.93))
        ..drawRect(0, 0, w, h)
        ..fillPath()
        ..setFillColor(brand)
        ..drawRect(0, h - 8, w, 8)
        ..fillPath();
    } else if (style == 'corner') {
      c
        ..setFillColor(footer)
        ..drawRect(0, 0, 9, h)
        ..fillPath()
        ..setFillColor(brand)
        // top-right corner with a diagonal cut
        ..moveTo(w, h)
        ..lineTo(w - 26, h)
        ..lineTo(w - 26, h - 120)
        ..lineTo(w, h - 160)
        ..closePath()
        ..fillPath()
        // bottom-left corner with a diagonal cut
        ..moveTo(9, 0)
        ..lineTo(9 + 26, 0)
        ..lineTo(9 + 26, 120)
        ..lineTo(9, 160)
        ..closePath()
        ..fillPath();
    } else if (style != 'band') {
      c
        ..setFillColor(_mix(brand, washAmount))
        ..drawRect(0, 0, w, h)
        ..fillPath();
    }
    switch (style) {
      case 'dots':
        c.setFillColor(_mix(brand, 0.75));
        for (var y = 10.0; y < h; y += 16) {
          for (var x = 10.0; x < w; x += 16) {
            c
              ..drawEllipse(x, y, 1.2, 1.2)
              ..fillPath();
          }
        }
      case 'stripes':
        c
          ..saveContext()
          ..drawRect(0, 0, w, h)
          ..clipPath()
          ..setStrokeColor(_mix(brand, 0.85))
          ..setLineWidth(7);
        for (var x = -h; x < w; x += 24) {
          c
            ..drawLine(x, 0, x + h, h)
            ..strokePath();
        }
        c.restoreContext();
      case 'grid':
        c
          ..setStrokeColor(_mix(brand, 0.8))
          ..setLineWidth(0.4);
        for (var x = 0.0; x < w; x += 18) {
          c
            ..drawLine(x, 0, x, h)
            ..strokePath();
        }
        for (var y = 0.0; y < h; y += 18) {
          c
            ..drawLine(0, y, w, y)
            ..strokePath();
        }
      case 'band':
        c
          ..setFillColor(brand)
          ..drawRect(0, h - 14, w, 14)
          ..fillPath()
          ..setFillColor(accent)
          ..drawRect(0, 0, 8, h - 14)
          ..fillPath();
    }
  }

  PdfColor get _tint => _mix(brand, 0.9);

  pw.BoxDecoration tableHeaderDecoration() {
    switch (style) {
      case 'modern':
        return pw.BoxDecoration(color: brand);
      case 'minimal':
        return pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: brand, width: 1.5)),
        );
      case 'corner':
        return const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey900, width: 0.8),
            bottom: pw.BorderSide(color: PdfColors.grey900, width: 0.8),
          ),
        );
      case 'ledger':
        return pw.BoxDecoration(color: brand);
      case 'elegant':
        return pw.BoxDecoration(
          color: _mix(brand, -0.45),
          borderRadius: pw.BorderRadius.circular(3),
        );
      default:
        return pw.BoxDecoration(
          color: brand,
          borderRadius: pw.BorderRadius.circular(8),
        );
    }
  }

  pw.BoxDecoration? rowDecoration() {
    switch (style) {
      case 'ledger':
        return pw.BoxDecoration(
          border: pw.Border.all(color: _mix(brand, 0.45), width: 0.6),
        );
      case 'modern':
        return const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.6),
          ),
        );
      case 'elegant':
        return pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: _mix(brand, 0.7), width: 0.6),
          ),
        );
      default:
        return null;
    }
  }

  pw.Widget wrapHeader(pw.Widget header) {
    switch (style) {
      case 'modern':
        return pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: brand, width: 3)),
          ),
          child: header,
        );
      case 'minimal':
        return pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
            ),
          ),
          child: header,
        );
      case 'ledger':
        return pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: brand, width: 2)),
          ),
          child: header,
        );
      case 'elegant':
        return pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: _tint,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: header,
        );
      default:
        return header;
    }
  }

  /// Positive [amount] blends toward white, negative toward black.
  static PdfColor _mix(PdfColor color, double amount) {
    double blend(double c) =>
        (amount >= 0 ? c + (1 - c) * amount : c * (1 + amount)).clamp(0, 1);
    return PdfColor(blend(color.red), blend(color.green), blend(color.blue));
  }
}
