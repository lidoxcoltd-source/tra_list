import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/stock/product_label_print_service.dart';
import 'package:tra_list/stock/stock_models.dart';

void main() {
  final product = Product(name: 'Tea', sku: 'TEA-001', sellPrice: 2500);

  test('builds a printable Code 128 PDF for the SKU', () async {
    final bytes = await ProductLabelPrintService.buildLabelsPdf(
      product: product,
      format: ProductCodeFormat.code128,
      copies: 1,
    );

    expect(bytes.take(4), [37, 80, 68, 70]);
  });

  test('paginates a full sheet of QR labels', () async {
    final bytes = await ProductLabelPrintService.buildLabelsPdf(
      product: product,
      format: ProductCodeFormat.qr,
      copies: 100,
    );

    expect(bytes.take(4), [37, 80, 68, 70]);
  });

  test('rejects Code 128 values that contain non-ASCII characters', () async {
    await expectLater(
      ProductLabelPrintService.buildLabelsPdf(
        product: Product(name: 'Chai', sku: 'CHAI-ö'),
        format: ProductCodeFormat.code128,
        copies: 1,
      ),
      throwsFormatException,
    );
  });
}
