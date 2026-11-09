import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:tra_list/business_intelligence/ai_saved_invoice_pdf.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestFirebaseCoreHostApi.setUp(MockFirebaseApp());
    await Firebase.initializeApp();
  });

  test('stock-linked invoice detection handles legacy and current records', () {
    expect(
      invoiceHasStockLinks({
        'items': [
          {'description': 'Service'},
        ],
      }),
      isFalse,
    );
    expect(
      invoiceHasStockLinks({
        'stockLines': [
          {'productId': 'a', 'qty': 1},
        ],
      }),
      isTrue,
    );
    expect(
      invoiceHasStockLinks({
        'items': [
          {'productId': 'a'},
        ],
      }),
      isTrue,
    );
  });

  test(
    'saved invoice data renders a PDF without modifying the saved record',
    () async {
      final saved = <String, dynamic>{
        'company': {'name': 'Duka'},
        'client': {'name': 'Asha'},
        'invoice': {
          'number': 'INV-1',
          'name': 'Ofisi',
          'issueDate': '8/11/2026',
          'dueDate': '8/11/2026',
        },
        'items': [
          {'description': 'Mchele', 'qty': 2, 'unit': 5000, 'amount': 10000},
        ],
        'total': 10000,
        'documentTerms': <String, dynamic>{},
        'documentDesign': {
          'brand': 0xFF1976D2,
          'accent': 0xFFFFA000,
          'footer': 0xFF424242,
        },
      };
      final data = savedInvoicePdfData(saved);
      expect((data['invoice'] as Map)['number'], 'INV-1 - Ofisi');
      expect((saved['invoice'] as Map)['number'], 'INV-1');
      final bytes = await InvoicePdf.generateBytes(data);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    },
  );
}
