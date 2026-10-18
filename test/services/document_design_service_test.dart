import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tra_list/services/document_design_service.dart';

void main() {
  test('falls back to classic with profile colors', () {
    final design = DocumentDesignService.selectedFor({
      'colors': {'brand': 0xFF112233},
    }, 'invoice');
    expect(design['style'], 'classic');
    expect(design['brand'], 0xFF112233);
    expect(design['accent'], DocumentDesignService.defaultAccent);
  });

  test('uses the saved design for the matching document only', () {
    final profile = {
      'documentDesigns': {
        'proforma': {'style': 'modern', 'brand': 0xFF2E7D32},
      },
    };
    expect(
      DocumentDesignService.selectedFor(profile, 'proforma')['style'],
      'modern',
    );
    expect(
      DocumentDesignService.selectedFor(profile, 'invoice')['style'],
      'classic',
    );
  });

  test('every style renders into a pdf page', () async {
    for (final style in DocumentDesignService.styles) {
      final design = DocumentDesign.fromData({
        'documentDesign': {
          'style': style.id,
          'brand': 0xFF1976D2,
          'accent': 0xFFF15A24,
          'footer': 0xFF424242,
        },
      }, {});
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageTheme: design.pageTheme(),
          build: (_) => pw.Column(
            children: [
              design.wrapHeader(pw.Text('Header')),
              pw.Container(
                decoration: design.tableHeaderDecoration(),
                child: pw.Text('Row'),
              ),
              pw.Container(
                decoration: design.rowDecoration(),
                child: pw.Text('Item'),
              ),
            ],
          ),
        ),
      );
      expect((await pdf.save()).isNotEmpty, isTrue, reason: style.id);
    }
  });

  test('ignores unknown styles', () {
    final design = DocumentDesignService.selectedFor({
      'documentDesigns': {
        'invoice': {'style': 'nope'},
      },
    }, 'invoice');
    expect(design['style'], 'classic');
  });
}
