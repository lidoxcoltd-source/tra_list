import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/stock/stock_models.dart';
import 'package:tra_list/stock/stock_service.dart';

StockService svc(
  FakeFirebaseFirestore db, {
  String business = 'biz1',
  bool Function(String)? can,
}) => StockService(
  db: db,
  businessId: business,
  uid: 'u1',
  userName: 'Tester',
  can: can ?? (_) => true,
  canModule: (_, _) => true,
  notify: false,
);

Future<String> addProduct(
  StockService s, {
  String sku = 'A1',
  double qty = 10,
  double cost = 100,
  double threshold = 3,
  String unit = 'piece',
  bool tracked = true,
}) => s.createProduct(
  Product(
    name: 'Item $sku',
    sku: sku,
    unit: unit,
    sellPrice: 150,
    lowStockThreshold: threshold,
    tracked: tracked,
  ),
  openingQuantity: qty,
  openingCost: cost,
);

Future<Map<String, dynamic>> product(
  FakeFirebaseFirestore db,
  String id, [
  String biz = 'biz1',
]) async =>
    (await db.collection('users').doc(biz).collection('products').doc(id).get())
        .data()!;

Future<int> movementCount(
  FakeFirebaseFirestore db, [
  String biz = 'biz1',
]) async =>
    (await db.collection('users').doc(biz).collection('stockMovements').get())
        .size;

void main() {
  group('pure helpers', () {
    test('weighted average cost', () {
      expect(
        weightedAverageCost(oldQty: 10, oldCost: 100, inQty: 10, inCost: 200),
        150,
      );
      expect(
        weightedAverageCost(oldQty: 0, oldCost: 100, inQty: 5, inCost: 80),
        80,
      );
    });

    test('stock state transitions', () {
      expect(stockStateFor(10, 3), StockState.ok);
      expect(stockStateFor(3, 3), StockState.low);
      expect(stockStateFor(0, 3), StockState.out);
    });

    test('decimal quantities stay exact', () {
      expect(roundQty(0.1 + 0.2), 0.3);
      expect(roundQty(2.75 - 1.5), 1.25);
    });
  });

  group('products', () {
    late FakeFirebaseFirestore db;
    late StockService s;
    setUp(() {
      db = FakeFirebaseFirestore();
      s = svc(db);
    });

    test('create with opening stock writes ledger entry', () async {
      final id = await addProduct(s, qty: 12, cost: 90);
      final p = await product(db, id);
      expect(p['quantity'], 12);
      expect(p['costPrice'], 90);
      expect(await movementCount(db), 1);
    });

    test('duplicate SKU is rejected, even with different case', () async {
      await addProduct(s, sku: 'ABC');
      expect(
        () => addProduct(s, sku: 'abc'),
        throwsA(
          isA<StockException>().having(
            (e) => e.messageKey,
            'key',
            'stk_err_sku_exists',
          ),
        ),
      );
    });

    test('same SKU is allowed in another business', () async {
      await addProduct(s, sku: 'ABC');
      final other = svc(db, business: 'biz2');
      await addProduct(other, sku: 'ABC');
    });

    test('editing details cannot change quantity', () async {
      final id = await addProduct(s, qty: 5);
      await s.updateProduct(
        id,
        Product(name: 'Renamed', sku: 'A1', sellPrice: 200),
      );
      final p = await product(db, id);
      expect(p['name'], 'Renamed');
      expect(p['quantity'], 5);
    });

    test('renaming SKU frees the old code', () async {
      final id = await addProduct(s, sku: 'OLD');
      await s.updateProduct(id, Product(name: 'x', sku: 'NEW'));
      await addProduct(s, sku: 'OLD');
    });

    test('duplicate barcode is rejected, also against a SKU', () async {
      final id = await s.createProduct(
        Product(name: 'A', sku: 'S1', barcode: '123'),
      );
      Matcher barcodeErr = throwsA(
        isA<StockException>().having(
          (e) => e.messageKey,
          'key',
          'stk_err_barcode_exists',
        ),
      );
      expect(
        () => s.createProduct(Product(name: 'B', sku: 'S2', barcode: ' 123 ')),
        barcodeErr,
      );
      expect(
        () => s.createProduct(Product(name: 'C', sku: 'S3', barcode: 'S1')),
        barcodeErr,
      );
      await s.updateProduct(
        id,
        Product(name: 'A', sku: 'S1', barcode: '123', sellPrice: 5),
      );
      await s.updateProduct(id, Product(name: 'A', sku: 'S1', barcode: '999'));
      await s.createProduct(Product(name: 'B', sku: 'S2', barcode: '123'));
    });

    test('alternate barcode resolves to the existing product', () async {
      final id = await s.createProduct(
        Product(name: 'Water 1L', sku: 'WATER-1L', barcode: '111'),
      );
      await s.addBarcodeAlias(productId: id, barcode: '222');
      await s.addBarcodeAlias(productId: id, barcode: '222');

      expect((await s.findProductByCode('222'))?.id, id);
      expect((await s.findProductByCode('111'))?.id, id);
    });

    test('alternate barcode cannot point at two products', () async {
      final a = await addProduct(s, sku: 'WATER-A');
      final b = await addProduct(s, sku: 'WATER-B');
      await s.addBarcodeAlias(productId: a, barcode: 'EAN-OTHER');
      await expectLater(
        s.addBarcodeAlias(productId: b, barcode: 'ean-other'),
        throwsA(
          isA<StockException>().having(
            (e) => e.messageKey,
            'key',
            'stk_err_barcode_exists',
          ),
        ),
      );
    });

    test('similar names are detected', () {
      final a = Product(id: '1', name: 'Coca-Cola 500ml', sku: 'a');
      final b = Product(id: '2', name: 'Sugar', sku: 'b');
      expect(findSimilarNames([a, b], 'coca cola 500ML'), [a]);
      expect(
        findSimilarNames([a, b], 'Coca-Cola 500ml', excludeId: '1'),
        isEmpty,
      );
      expect(findSimilarNames([a, b], 'Salt'), isEmpty);
    });

    test('merge moves stock, averages cost and archives the source', () async {
      final src = await addProduct(s, sku: 'D1', qty: 4, cost: 200);
      final dst = await addProduct(s, sku: 'D2', qty: 6, cost: 100);
      await s.mergeProducts(sourceId: src, targetId: dst);
      final a = await product(db, src);
      final b = await product(db, dst);
      expect(a['quantity'], 0);
      expect(a['active'], false);
      expect(a['mergedInto'], dst);
      expect(b['quantity'], 10);
      expect(b['costPrice'], 140);
      expect(await movementCount(db), 4);
      expect(
        () => s.mergeProducts(sourceId: src, targetId: dst),
        throwsA(isA<StockException>()),
      );
      expect(
        () => s.mergeProducts(sourceId: dst, targetId: dst),
        throwsA(isA<StockException>()),
      );
    });

    test('permission is enforced in the service', () async {
      final denied = svc(db, can: (_) => false);
      expect(() => addProduct(denied), throwsA(isA<StockException>()));
    });
  });

  group('receiving stock', () {
    late FakeFirebaseFirestore db;
    late StockService s;
    late String id;
    setUp(() async {
      db = FakeFirebaseFirestore();
      s = svc(db);
      id = await addProduct(s, qty: 10, cost: 100);
    });

    Future<void> receive(String purchaseId, {bool expense = false}) =>
        s.receiveStock(
          purchaseId: purchaseId,
          supplier: 'Sup',
          reference: 'INV-1',
          date: DateTime(2026, 1, 1),
          lines: [
            PurchaseLine(
              productId: id,
              productName: 'Item A1',
              quantity: 10,
              unitCost: 200,
            ),
          ],
          recordExpense: expense,
        );

    test('increases stock and updates weighted average cost', () async {
      await receive('p1');
      final p = await product(db, id);
      expect(p['quantity'], 20);
      expect(p['costPrice'], 150);
    });

    test('retrying the same purchase id never double-receives', () async {
      await receive('p1');
      await receive('p1');
      expect((await product(db, id))['quantity'], 20);
    });

    test('expense is recorded once', () async {
      await receive('p1', expense: true);
      await receive('p1', expense: true);
      final tx = await db
          .collection('users')
          .doc('biz1')
          .collection('transactions')
          .get();
      expect(tx.size, 1);
      expect(tx.docs.first['amount'], 2000);
    });

    test('rejects empty and non-positive lines', () async {
      expect(
        () => s.receiveStock(
          purchaseId: 'x',
          supplier: '',
          reference: '',
          date: DateTime.now(),
          lines: [],
        ),
        throwsA(isA<StockException>()),
      );
    });
  });

  group('sales', () {
    late FakeFirebaseFirestore db;
    late StockService s;
    late String a;
    late String b;
    setUp(() async {
      db = FakeFirebaseFirestore();
      s = svc(db);
      a = await addProduct(s, sku: 'A', qty: 10, cost: 100, threshold: 3);
      b = await addProduct(s, sku: 'B', qty: 5, cost: 50, threshold: 1);
    });

    group('bar orders', () {
      late FakeFirebaseFirestore db;
      late StockService s;
      late String productId;

      setUp(() async {
        db = FakeFirebaseFirestore();
        s = svc(db);
        productId = await addProduct(s, qty: 10);
      });

      test(
        'reserves stock, serves once, then settles without another deduction',
        () async {
          final orderId = await s.createBarOrder(
            tableNumber: 'T1',
            customerName: 'Guest',
            lines: [SaleLine(productId: productId, quantity: 2)],
          );
          var productData = await product(db, productId);
          expect(productData['quantity'], 10);
          expect(productData['reservedQuantity'], 2);

          final saleRef = db
              .collection('users')
              .doc('biz1')
              .collection('invoices')
              .doc('direct-sale');
          await expectLater(
            s.finalizeSale(
              saleRef: saleRef,
              saleData: const {},
              lines: [SaleLine(productId: productId, quantity: 9)],
            ),
            throwsA(
              isA<StockException>().having(
                (error) => error.messageKey,
                'messageKey',
                'stk_err_reserved_stock',
              ),
            ),
          );

          await s.serveBarOrder(orderId);
          productData = await product(db, productId);
          expect(productData['quantity'], 8);
          expect(productData['reservedQuantity'], 0);
          await expectLater(
            s.serveBarOrder(orderId),
            throwsA(
              isA<StockException>().having(
                (error) => error.messageKey,
                'messageKey',
                'stk_err_order_not_pending',
              ),
            ),
          );

          final receipt = await s.settleBarOrders(
            orderIds: [orderId],
            invoiceNumber: 'BAR-001',
            paymentMethod: 'cash',
            company: const {},
          );
          expect(receipt['total'], 300);
          expect((await product(db, productId))['quantity'], 8);
          final order = await db
              .collection('users')
              .doc('biz1')
              .collection('barOrders')
              .doc(orderId)
              .get();
          expect(order.data()?['status'], 'paid');
          expect(order.data()?['paidBy'], 'u1');
        },
      );

      test(
        'cancelling releases reserved stock without a sale movement',
        () async {
          final before = await movementCount(db);
          final orderId = await s.createBarOrder(
            tableNumber: 'T2',
            lines: [SaleLine(productId: productId, quantity: 4)],
          );
          expect((await product(db, productId))['reservedQuantity'], 4);

          await s.cancelBarOrder(orderId);
          expect((await product(db, productId))['quantity'], 10);
          expect((await product(db, productId))['reservedQuantity'], 0);
          expect(await movementCount(db), before);
          await expectLater(
            s.cancelBarOrder(orderId),
            throwsA(
              isA<StockException>().having(
                (error) => error.messageKey,
                'messageKey',
                'stk_err_order_not_pending',
              ),
            ),
          );
        },
      );
    });

    DocumentReference<Map<String, dynamic>> sale(String id) =>
        db.collection('users').doc('biz1').collection('invoices').doc(id);

    test('deducts multiple products and links movements to the sale', () async {
      await s.finalizeSale(
        saleRef: sale('s1'),
        saleData: {'total': 1},
        lines: [
          SaleLine(productId: a, quantity: 4),
          SaleLine(productId: b, quantity: 2),
        ],
      );
      expect((await product(db, a))['quantity'], 6);
      expect((await product(db, b))['quantity'], 3);
      final mv = await db
          .collection('users')
          .doc('biz1')
          .collection('stockMovements')
          .where('refId', isEqualTo: 's1')
          .get();
      expect(mv.size, 2);
      expect(mv.docs.first['unitCost'], isNotNull);
      expect((await sale('s1').get()).exists, isTrue);
    });

    test('same sale finalised twice deducts once', () async {
      for (var i = 0; i < 2; i++) {
        await s.finalizeSale(
          saleRef: sale('s1'),
          saleData: {'total': 1},
          lines: [SaleLine(productId: a, quantity: 4)],
        );
      }
      expect((await product(db, a))['quantity'], 6);
    });

    test('repeated product lines are merged', () async {
      await s.finalizeSale(
        saleRef: sale('s1'),
        saleData: {},
        lines: [
          SaleLine(productId: a, quantity: 1),
          SaleLine(productId: a, quantity: 2),
        ],
      );
      expect((await product(db, a))['quantity'], 7);
    });

    test('insufficient stock fails atomically (nothing is written)', () async {
      await expectLater(
        s.finalizeSale(
          saleRef: sale('s1'),
          saleData: {'total': 1},
          lines: [
            SaleLine(productId: b, quantity: 2),
            SaleLine(productId: a, quantity: 11),
          ],
        ),
        throwsA(
          isA<StockException>().having(
            (e) => e.messageKey,
            'key',
            'stk_err_insufficient',
          ),
        ),
      );
      expect((await product(db, a))['quantity'], 10);
      expect((await product(db, b))['quantity'], 5);
      expect((await sale('s1').get()).exists, isFalse);
    });

    // The in-memory fake does not emulate Firestore's optimistic-concurrency
    // retries, so true parallel overselling is prevented by the real
    // transaction (read + write of the same product doc), and only the
    // sequential outcome is asserted here.
    test('a second sale cannot take stock the first already sold', () async {
      await s.finalizeSale(
        saleRef: sale('s1'),
        saleData: {},
        lines: [SaleLine(productId: b, quantity: 4)],
      );
      await expectLater(
        s.finalizeSale(
          saleRef: sale('s2'),
          saleData: {},
          lines: [SaleLine(productId: b, quantity: 4)],
        ),
        throwsA(isA<StockException>()),
      );
      expect((await product(db, b))['quantity'], 1);
    });

    test('untracked (service) items never touch inventory', () async {
      final svcItem = await addProduct(s, sku: 'SRV', qty: 0, tracked: false);
      await s.finalizeSale(
        saleRef: sale('s1'),
        saleData: {},
        lines: [SaleLine(productId: svcItem, quantity: 3)],
      );
      expect((await product(db, svcItem))['quantity'], 0);
    });

    test('negative stock only when explicitly allowed', () async {
      final id = await s.createProduct(
        Product(name: 'Neg', sku: 'NEG', allowNegative: true),
        openingQuantity: 1,
        openingCost: 10,
      );
      await s.finalizeSale(
        saleRef: sale('s1'),
        saleData: {},
        lines: [SaleLine(productId: id, quantity: 3)],
      );
      expect((await product(db, id))['quantity'], -2);
    });

    test('product from another business is rejected', () async {
      final other = svc(db, business: 'biz2');
      final foreign = await addProduct(other, sku: 'F');
      expect(
        () => s.finalizeSale(
          saleRef: sale('s1'),
          saleData: {},
          lines: [SaleLine(productId: foreign, quantity: 1)],
        ),
        throwsA(isA<StockException>()),
      );
    });

    test('cancelling a sale restores stock exactly once', () async {
      await s.finalizeSale(
        saleRef: sale('s1'),
        saleData: {},
        lines: [SaleLine(productId: a, quantity: 4)],
      );
      final lines = [SaleLine(productId: a, quantity: 4)];
      await s.reverseSale('s1', lines);
      await s.reverseSale('s1', lines);
      expect((await product(db, a))['quantity'], 10);
      final reversals = await db
          .collection('users')
          .doc('biz1')
          .collection('stockMovements')
          .where('type', isEqualTo: 'sale_reversal')
          .get();
      expect(reversals.size, 1);
    });

    test('sale cost is frozen at the cost price of that moment', () async {
      await s.finalizeSale(
        saleRef: sale('s1'),
        saleData: {},
        lines: [SaleLine(productId: a, quantity: 1)],
      );
      await s.receiveStock(
        purchaseId: 'p9',
        supplier: '',
        reference: '',
        date: DateTime.now(),
        lines: [
          PurchaseLine(
            productId: a,
            productName: 'A',
            quantity: 10,
            unitCost: 900,
          ),
        ],
      );
      final mv = await db
          .collection('users')
          .doc('biz1')
          .collection('stockMovements')
          .doc('sale_s1_$a')
          .get();
      expect(mv['unitCost'], 100);
    });
  });

  group('manual adjustments', () {
    late FakeFirebaseFirestore db;
    late StockService s;
    late String id;
    setUp(() async {
      db = FakeFirebaseFirestore();
      s = svc(db);
      id = await addProduct(s, qty: 10, threshold: 3);
    });

    test('negative adjustment requires a reason', () async {
      expect(
        () => s.adjustStock(
          productId: id,
          type: MovementType.damaged,
          quantity: 1,
          reason: ' ',
        ),
        throwsA(isA<StockException>()),
      );
    });

    test('damage reduces and records who/why', () async {
      await s.adjustStock(
        productId: id,
        type: MovementType.damaged,
        quantity: 2,
        reason: 'Dropped',
      );
      expect((await product(db, id))['quantity'], 8);
      final mv = await db
          .collection('users')
          .doc('biz1')
          .collection('stockMovements')
          .where('type', isEqualTo: 'damaged')
          .get();
      expect(mv.docs.single['reason'], 'Dropped');
      expect(mv.docs.single['userId'], 'u1');
      expect(mv.docs.single['previousQuantity'], 10);
      expect(mv.docs.single['resultingQuantity'], 8);
    });

    test('cannot remove more than available', () async {
      expect(
        () => s.adjustStock(
          productId: id,
          type: MovementType.lost,
          quantity: 11,
          reason: 'x',
        ),
        throwsA(isA<StockException>()),
      );
    });

    test('correction sets the counted quantity', () async {
      await s.adjustStock(
        productId: id,
        type: MovementType.correction,
        quantity: 7.5,
        reason: 'Recount',
      );
      expect((await product(db, id))['quantity'], 7.5);
    });

    test('supports decimal quantities', () async {
      final kg = await addProduct(s, sku: 'KG', qty: 10, unit: 'kg');
      await s.adjustStock(
        productId: kg,
        type: MovementType.adjustmentOut,
        quantity: 1.5,
        reason: 'Sample',
      );
      expect((await product(db, kg))['quantity'], 8.5);
    });

    test('low and out-of-stock states follow quantity', () async {
      await s.adjustStock(
        productId: id,
        type: MovementType.lost,
        quantity: 7,
        reason: 'x',
      );
      expect((await product(db, id))['stockState'], 'low');
      await s.adjustStock(
        productId: id,
        type: MovementType.lost,
        quantity: 3,
        reason: 'x',
      );
      expect((await product(db, id))['stockState'], 'out');
      await s.adjustStock(
        productId: id,
        type: MovementType.customerReturn,
        quantity: 10,
        reason: 'Returned, resellable',
      );
      expect((await product(db, id))['stockState'], 'ok');
    });

    test('retrying with the same operation id applies once', () async {
      for (var i = 0; i < 2; i++) {
        await s.adjustStock(
          productId: id,
          type: MovementType.lost,
          quantity: 1,
          reason: 'x',
          operationId: 'op1',
        );
      }
      expect((await product(db, id))['quantity'], 9);
    });

    test('untracked products cannot be adjusted', () async {
      final srv = await addProduct(s, sku: 'S2', qty: 0, tracked: false);
      expect(
        () => s.adjustStock(
          productId: srv,
          type: MovementType.adjustmentIn,
          quantity: 1,
          reason: 'x',
        ),
        throwsA(isA<StockException>()),
      );
    });
  });
}
