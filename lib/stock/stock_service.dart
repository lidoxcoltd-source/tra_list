import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/notification_service.dart';
import 'stock_models.dart';

/// A product whose stock level crossed into low / out of stock.
class StockAlert {
  StockAlert(this.productName, this.state, this.quantity, this.unit);
  final String productName;
  final StockState state;
  final double quantity;
  final String unit;
}

class _Req {
  _Req({
    required this.productId,
    required this.type,
    this.quantity = 0,
    this.targetQuantity,
    this.unitCost,
    this.reason = '',
    this.note = '',
    this.refType = '',
    this.refId = '',
    this.movementId,
  });

  final String productId;
  final MovementType type;
  final double quantity;
  final double? targetQuantity;
  final double? unitCost;
  final String reason;
  final String note;
  final String refType;
  final String refId;

  /// Deterministic id => the same operation can never be applied twice.
  final String? movementId;
}

/// Single trusted entry point for every inventory change.
///
/// Product quantity is a denormalised running total of the immutable
/// `stockMovements` ledger. Both are written in the same Firestore
/// transaction, so they cannot drift apart.
class StockService {
  StockService({
    FirebaseFirestore? db,
    required this.businessId,
    required this.uid,
    this.userName = '',
    bool Function(String action)? can,
    this.notify = true,
  }) : _db = db ?? FirebaseFirestore.instance,
       _can = can ?? ((a) => BusinessAccessService.can('stock', a));

  factory StockService.current() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    final name = (user.displayName ?? '').trim();
    return StockService(
      businessId: BusinessAccessService.businessId,
      uid: user.uid,
      userName: name.isNotEmpty ? name : (user.email ?? ''),
    );
  }

  final FirebaseFirestore _db;
  final String businessId;
  final String uid;
  final String userName;
  final bool Function(String action) _can;
  final bool notify;

  DocumentReference<Map<String, dynamic>> get _business =>
      _db.collection('users').doc(businessId);
  CollectionReference<Map<String, dynamic>> get products =>
      _business.collection('products');
  CollectionReference<Map<String, dynamic>> get movements =>
      _business.collection('stockMovements');
  CollectionReference<Map<String, dynamic>> get purchases =>
      _business.collection('purchases');
  CollectionReference<Map<String, dynamic>> get _codes =>
      _business.collection('productCodes');
  CollectionReference<Map<String, dynamic>> get _barcodes =>
      _business.collection('productBarcodes');

  /// Reads (never writes) the unique-code indexes and throws when the SKU or
  /// barcode already belongs to another product. SKUs and barcodes share one
  /// namespace, because a scan matches either.
  Future<void> _checkCodes(
    Transaction tx, {
    required String skuKey,
    required String barKey,
    String? ownId,
  }) async {
    Future<bool> taken(
      CollectionReference<Map<String, dynamic>> c,
      String k,
    ) async {
      final s = await tx.get(c.doc(k));
      return s.exists && s.data()?['productId'] != ownId;
    }

    if (await taken(_codes, skuKey) || await taken(_barcodes, skuKey)) {
      throw StockException('stk_err_sku_exists');
    }
    if (barKey.isNotEmpty &&
        (await taken(_barcodes, barKey) || await taken(_codes, barKey))) {
      throw StockException('stk_err_barcode_exists');
    }
  }

  void _writeCodes(
    Transaction tx,
    String productId, {
    required String skuKey,
    required String barKey,
    String oldSkuKey = '',
    String oldBarKey = '',
  }) {
    final data = {'productId': productId, 'businessId': businessId};
    if (oldSkuKey.isNotEmpty && oldSkuKey != skuKey) {
      tx.delete(_codes.doc(oldSkuKey));
    }
    if (oldBarKey.isNotEmpty && oldBarKey != barKey) {
      tx.delete(_barcodes.doc(oldBarKey));
    }
    tx.set(_codes.doc(skuKey), data);
    if (barKey.isNotEmpty) tx.set(_barcodes.doc(barKey), data);
  }

  void _require(String action) {
    if (!_can(action)) throw StockException('stk_err_permission');
  }

  // ---------------------------------------------------------------- reads

  Stream<List<Product>> watchProducts() => products
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map(Product.fromDoc).toList());

  /// Resolves a scanned SKU or barcode using the per-business indexes. The
  /// barcode index can contain more than one code for the same product.
  Future<Product?> findProductByCode(String code) async {
    final key = Product.skuKey(code);
    if (key.isEmpty) return null;
    final barcode = await _barcodes.doc(key).get();
    final sku = barcode.exists ? null : await _codes.doc(key).get();
    final productId =
        barcode.data()?['productId']?.toString() ??
        sku?.data()?['productId']?.toString();
    if (productId == null || productId.isEmpty) return null;
    final snap = await products.doc(productId).get();
    if (!snap.exists) return null;
    return Product.fromDoc(snap);
  }

  /// Adds another physical barcode to an existing product without creating a
  /// second product record.
  Future<void> addBarcodeAlias({
    required String productId,
    required String barcode,
  }) async {
    if (!_can('edit') && !_can('create')) {
      throw StockException('stk_err_permission');
    }
    final key = Product.skuKey(barcode);
    if (key.isEmpty) throw StockException('stk_err_barcode_required');

    await _db.runTransaction((tx) async {
      final productRef = products.doc(productId);
      final product = await tx.get(productRef);
      if (!product.exists) throw StockException('stk_err_product_missing');

      final barcodeRef = _barcodes.doc(key);
      final skuRef = _codes.doc(key);
      final barcodeSnap = await tx.get(barcodeRef);
      final skuSnap = await tx.get(skuRef);
      final barcodeOwner = barcodeSnap.data()?['productId']?.toString();
      final skuOwner = skuSnap.data()?['productId']?.toString();
      if ((barcodeOwner != null && barcodeOwner != productId) ||
          (skuOwner != null && skuOwner != productId)) {
        throw StockException('stk_err_barcode_exists');
      }
      if (barcodeOwner != productId) {
        tx.set(barcodeRef, {
          'productId': productId,
          'businessId': businessId,
          'barcode': barcode.trim(),
          'isAlias': true,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': uid,
        });
      }
    });
  }

  Stream<List<StockMovement>> watchMovements({int limit = 200}) => movements
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(StockMovement.fromDoc).toList());

  Stream<List<StockMovement>> watchProductMovements(
    String productId, {
    int limit = 100,
  }) => movements
      .where('productId', isEqualTo: productId)
      .limit(limit)
      .snapshots()
      .map((s) {
        final list = s.docs.map(StockMovement.fromDoc).toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
              a.createdAt ?? DateTime.now(),
            ),
          );
        return list;
      });

  Stream<List<Purchase>> watchPurchases({int limit = 100}) => purchases
      .orderBy('date', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(Purchase.fromDoc).toList());

  // ------------------------------------------------------------- products

  /// Creates a product. [openingQuantity] is recorded as an opening-stock
  /// movement so the ledger explains every unit.
  Future<String> createProduct(
    Product product, {
    double openingQuantity = 0,
    double openingCost = 0,
  }) async {
    _require('create');
    _validateProduct(product);
    if (openingQuantity < 0) throw StockException('stk_err_qty');
    if (openingQuantity > 0 && !product.tracked) {
      throw StockException('stk_err_not_tracked');
    }
    final ref = products.doc();
    final skuKey = Product.skuKey(product.sku);
    final barKey = Product.skuKey(product.barcode);
    final qty = product.tracked ? roundQty(openingQuantity) : 0.0;
    final cost = qty > 0 ? roundMoney(openingCost) : 0.0;
    final state = stockStateFor(qty, product.lowStockThreshold);

    await _db.runTransaction((tx) async {
      await _checkCodes(tx, skuKey: skuKey, barKey: barKey);
      tx.set(ref, {
        ...product.detailsMap(),
        'businessId': businessId,
        'quantity': qty,
        'costPrice': cost,
        'stockState': state.name,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _writeCodes(tx, ref.id, skuKey: skuKey, barKey: barKey);
      if (qty > 0) {
        tx.set(
          movements.doc('opening_${ref.id}'),
          _movementData(
            productId: ref.id,
            productName: product.name.trim(),
            type: MovementType.openingStock,
            change: qty,
            previous: 0,
            resulting: qty,
            unitCost: cost,
            reason: '',
            note: '',
            refType: 'product',
            refId: ref.id,
          ),
        );
      }
    });
    return ref.id;
  }

  /// Updates descriptive details only. Quantity/cost cannot be changed here.
  Future<void> updateProduct(String id, Product product) async {
    _require('edit');
    _validateProduct(product);
    final ref = products.doc(id);
    final newKey = Product.skuKey(product.sku);
    final newBar = Product.skuKey(product.barcode);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StockException('stk_err_product_missing');
      final oldKey = snap.data()!['skuKey']?.toString() ?? '';
      final oldBar = snap.data()!['barcodeKey']?.toString() ?? '';
      await _checkCodes(tx, skuKey: newKey, barKey: newBar, ownId: id);
      _writeCodes(
        tx,
        id,
        skuKey: newKey,
        barKey: newBar,
        oldSkuKey: oldKey,
        oldBarKey: oldBar,
      );
      final qty = (snap.data()!['quantity'] as num?)?.toDouble() ?? 0;
      tx.update(ref, {
        ...product.detailsMap(),
        'stockState': stockStateFor(qty, product.lowStockThreshold).name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> setActive(String id, bool active) async {
    _require('edit');
    await products.doc(id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Folds a duplicate product into [targetId]: its stock moves across (with
  /// ledger entries on both products, cost averaged in) and the duplicate is
  /// archived, never deleted, so past invoices and history stay valid.
  Future<void> mergeProducts({
    required String sourceId,
    required String targetId,
  }) async {
    _require('edit');
    if (sourceId == targetId) throw StockException('stk_err_merge_same');
    final alerts = await _db.runTransaction<List<StockAlert>>((tx) async {
      final src = await tx.get(products.doc(sourceId));
      final dst = await tx.get(products.doc(targetId));
      if (!src.exists || !dst.exists) {
        throw StockException('stk_err_product_missing');
      }
      final s = src.data()!;
      final d = dst.data()!;
      if (s['active'] == false || d['active'] == false) {
        throw StockException('stk_err_merge_inactive');
      }
      if (s['tracked'] == false || d['tracked'] == false) {
        throw StockException('stk_err_not_tracked', {
          'name': (s['tracked'] == false ? s : d)['name']?.toString() ?? '',
        });
      }
      final qty = (s['quantity'] as num?)?.toDouble() ?? 0;
      if (qty < 0) throw StockException('stk_err_qty');
      final cost = (s['costPrice'] as num?)?.toDouble() ?? 0;
      final reqs = qty > 0
          ? [
              _Req(
                productId: sourceId,
                type: MovementType.adjustmentOut,
                quantity: qty,
                reason: 'merge',
                note: d['name']?.toString() ?? '',
                refType: 'merge',
                refId: targetId,
              ),
              _Req(
                productId: targetId,
                type: MovementType.adjustmentIn,
                quantity: qty,
                unitCost: cost,
                reason: 'merge',
                note: s['name']?.toString() ?? '',
                refType: 'merge',
                refId: sourceId,
              ),
            ]
          : <_Req>[];
      final prepared = reqs.isEmpty ? null : await _applyReads(tx, reqs);
      final result = prepared == null
          ? <StockAlert>[]
          : await _applyWrites(tx, prepared);
      tx.update(products.doc(sourceId), {
        'active': false,
        'mergedInto': targetId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return result;
    });
    await _notifyAlerts(alerts);
  }

  void _validateProduct(Product p) {
    if (p.name.trim().isEmpty) throw StockException('stk_err_name');
    if (p.sku.trim().isEmpty) throw StockException('stk_err_sku');
    if (p.sellPrice < 0 || p.lowStockThreshold < 0) {
      throw StockException('stk_err_qty');
    }
  }

  // ------------------------------------------------------------ movements

  /// Records one manual movement (damage, expiry, correction, ...).
  Future<List<StockAlert>> adjustStock({
    required String productId,
    required MovementType type,
    required double quantity,
    required String reason,
    String note = '',
    double? unitCost,
    String? operationId,
  }) async {
    _require('edit');
    if (!MovementType.manual.contains(type)) {
      throw StockException('stk_err_type');
    }
    if (reason.trim().isEmpty) throw StockException('stk_err_reason');
    if (type == MovementType.correction) {
      if (quantity < 0) throw StockException('stk_err_qty');
    } else if (quantity <= 0) {
      throw StockException('stk_err_qty');
    }
    final req = _Req(
      productId: productId,
      type: type,
      quantity: type == MovementType.correction ? 0 : quantity,
      targetQuantity: type == MovementType.correction ? quantity : null,
      unitCost: unitCost,
      reason: reason.trim(),
      note: note.trim(),
      refType: 'adjustment',
      refId: operationId ?? '',
      movementId: operationId == null ? null : 'adj_$operationId',
    );
    final alerts = await _db.runTransaction((tx) => _apply(tx, [req]));
    await _notifyAlerts(alerts);
    return alerts;
  }

  /// Confirms a purchase receipt: increases stock exactly once. The purchase
  /// id doubles as the idempotency key, so retries and double taps are safe.
  Future<void> receiveStock({
    required String purchaseId,
    required String supplier,
    required String reference,
    required DateTime date,
    required List<PurchaseLine> lines,
    String note = '',
    bool recordExpense = false,
    String shopNickname = '',
  }) async {
    _require('create');
    if (lines.isEmpty) throw StockException('stk_err_no_lines');
    for (final l in lines) {
      if (l.quantity <= 0) throw StockException('stk_err_qty');
      if (l.unitCost < 0) throw StockException('stk_err_cost');
    }
    final purchaseRef = purchases.doc(purchaseId);
    final total = roundMoney(lines.fold<double>(0, (s, l) => s + l.total));
    final expenseRef = _business
        .collection('transactions')
        .doc('purchase_$purchaseId');

    final alerts = await _db.runTransaction<List<StockAlert>>((tx) async {
      if ((await tx.get(purchaseRef)).exists) return const [];
      final reqs = [
        for (var i = 0; i < lines.length; i++)
          _Req(
            productId: lines[i].productId,
            type: MovementType.purchase,
            quantity: lines[i].quantity,
            unitCost: lines[i].unitCost,
            reason: supplier.trim(),
            note: note.trim(),
            refType: 'purchase',
            refId: purchaseId,
            movementId: 'purchase_${purchaseId}_$i',
          ),
      ];
      final result = _applyReads(tx, reqs);
      final alerts = await _applyWrites(tx, await result);
      tx.set(purchaseRef, {
        'businessId': businessId,
        'supplier': supplier.trim(),
        'reference': reference.trim(),
        'date': Timestamp.fromDate(date),
        'lines': lines.map((l) => l.toMap()).toList(),
        'total': total,
        'note': note.trim(),
        'status': 'received',
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (recordExpense && total > 0) {
        tx.set(expenseRef, {
          'type': 'expense',
          'description': 'Stock purchase ${reference.trim()}'.trim(),
          'amount': total,
          'date': Timestamp.fromDate(date),
          'category': 'Stock purchase',
          'uid': uid,
          'shopNickname': shopNickname,
          'purchaseId': purchaseId,
        });
      }
      return alerts;
    });
    await _notifyAlerts(alerts);
  }

  // ---------------------------------------------------------------- sales

  /// Creates the sale document AND deducts stock in one transaction. If any
  /// product lacks stock nothing is written. Calling it again for the same
  /// [saleRef] is a no-op.
  Future<List<StockAlert>> finalizeSale({
    required DocumentReference<Map<String, dynamic>> saleRef,
    required Map<String, dynamic> saleData,
    required List<SaleLine> lines,
  }) async {
    final merged = <String, double>{};
    for (final l in lines) {
      if (l.quantity <= 0) throw StockException('stk_err_qty');
      merged[l.productId] = roundQty((merged[l.productId] ?? 0) + l.quantity);
    }
    final alerts = await _db.runTransaction<List<StockAlert>>((tx) async {
      if ((await tx.get(saleRef)).exists) return const [];
      final reqs = [
        for (final e in merged.entries)
          _Req(
            productId: e.key,
            type: MovementType.sale,
            quantity: e.value,
            refType: 'sale',
            refId: saleRef.id,
            movementId: 'sale_${saleRef.id}_${e.key}',
          ),
      ];
      final alerts = await _applyWrites(tx, await _applyReads(tx, reqs));
      tx.set(saleRef, {
        ...saleData,
        'stockLines': [
          for (final e in merged.entries) {'productId': e.key, 'qty': e.value},
        ],
      });
      return alerts;
    });
    await _notifyAlerts(alerts);
    return alerts;
  }

  /// Puts the stock of a cancelled / deleted sale back exactly once. Each
  /// reversal is linked to the original sale movement.
  Future<void> reverseSale(String saleId, List<SaleLine> lines) async {
    final ids = lines.map((l) => l.productId).toSet();
    if (ids.isEmpty) return;
    final alerts = await _db.runTransaction<List<StockAlert>>((tx) async {
      final reqs = <_Req>[];
      for (final pid in ids) {
        final original = await tx.get(movements.doc('sale_${saleId}_$pid'));
        if (!original.exists) continue;
        final reversalId = 'reversal_${saleId}_$pid';
        if ((await tx.get(movements.doc(reversalId))).exists) continue;
        final d = original.data()!;
        reqs.add(
          _Req(
            productId: pid,
            type: MovementType.saleReversal,
            quantity: ((d['quantityChange'] as num?)?.toDouble() ?? 0).abs(),
            unitCost: (d['unitCost'] as num?)?.toDouble(),
            refType: 'sale',
            refId: saleId,
            movementId: reversalId,
          ),
        );
      }
      if (reqs.isEmpty) return const [];
      return _applyWrites(tx, await _applyReads(tx, reqs));
    });
    await _notifyAlerts(alerts);
  }

  /// Reverses stock for an invoice document, if it consumed any.
  static Future<void> reverseSaleForDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final raw = doc.data()?['stockLines'];
    if (raw is! List || raw.isEmpty) return;
    final lines = raw
        .whereType<Map>()
        .map(
          (m) => SaleLine(
            productId: m['productId'].toString(),
            quantity: (m['qty'] as num).toDouble(),
          ),
        )
        .toList();
    await StockService.current().reverseSale(doc.id, lines);
  }

  // ------------------------------------------------------------- internals

  Future<List<StockAlert>> _apply(Transaction tx, List<_Req> reqs) async {
    final prepared = await _applyReads(tx, reqs);
    return _applyWrites(tx, prepared);
  }

  Future<_Prepared> _applyReads(Transaction tx, List<_Req> reqs) async {
    final prepared = _Prepared();
    final snaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final id in reqs.map((r) => r.productId).toSet()) {
      snaps[id] = await tx.get(products.doc(id));
    }
    final done = <String>{};
    for (final r in reqs) {
      if (r.movementId != null &&
          (await tx.get(movements.doc(r.movementId!))).exists) {
        done.add(r.movementId!);
      }
    }

    final running = <String, Map<String, dynamic>>{};
    for (final r in reqs) {
      if (r.movementId != null && done.contains(r.movementId)) continue;
      final snap = snaps[r.productId]!;
      if (!snap.exists) throw StockException('stk_err_product_missing');
      final p = running.putIfAbsent(
        r.productId,
        () => {
          ...snap.data()!,
          'quantity': (snap.data()!['quantity'] as num?)?.toDouble() ?? 0,
          'costPrice': (snap.data()!['costPrice'] as num?)?.toDouble() ?? 0,
        },
      );
      final name = p['name']?.toString() ?? '';
      final tracked = p['tracked'] != false;
      if (!tracked) {
        if (r.type == MovementType.sale ||
            r.type == MovementType.saleReversal) {
          continue;
        }
        throw StockException('stk_err_not_tracked', {'name': name});
      }

      final prev = p['quantity'] as double;
      final delta = r.type.sign == 0
          ? roundQty(r.targetQuantity! - prev)
          : roundQty(r.type.sign * r.quantity.abs());
      final next = roundQty(prev + delta);
      if (delta < 0 && next < 0 && p['allowNegative'] != true) {
        throw StockException('stk_err_insufficient', {
          'name': name,
          'available': formatQty(prev),
          'unit': p['unit']?.toString() ?? '',
        });
      }

      var cost = p['costPrice'] as double;
      double? movementCost = r.unitCost;
      final addsCost =
          r.type == MovementType.purchase ||
          r.type == MovementType.openingStock ||
          (r.type == MovementType.adjustmentIn && r.unitCost != null);
      if (addsCost && delta > 0) {
        cost = weightedAverageCost(
          oldQty: prev < 0 ? 0 : prev,
          oldCost: cost,
          inQty: delta,
          inCost: r.unitCost ?? cost,
        );
      } else if (r.type == MovementType.sale) {
        // Freeze the cost at the time of sale so profit is never recomputed
        // with a later purchase price.
        movementCost = cost;
      } else {
        movementCost ??= cost;
      }

      p['quantity'] = next;
      p['costPrice'] = cost;
      prepared.movements.add(
        _PreparedMovement(
          ref: r.movementId != null
              ? movements.doc(r.movementId!)
              : movements.doc(),
          data: _movementData(
            productId: r.productId,
            productName: name,
            type: r.type,
            change: delta,
            previous: prev,
            resulting: next,
            unitCost: movementCost,
            reason: r.reason,
            note: r.note,
            refType: r.refType,
            refId: r.refId,
          ),
        ),
      );
    }

    for (final e in running.entries) {
      final before = snaps[e.key]!.data()!;
      final threshold = (before['lowStockThreshold'] as num?)?.toDouble() ?? 0;
      final qty = e.value['quantity'] as double;
      prepared.products.add(
        _PreparedProduct(
          ref: products.doc(e.key),
          quantity: qty,
          cost: e.value['costPrice'] as double,
          oldState:
              before['stockState']?.toString() ??
              stockStateFor(
                (before['quantity'] as num?)?.toDouble() ?? 0,
                threshold,
              ).name,
          newState: stockStateFor(qty, threshold),
          name: before['name']?.toString() ?? '',
          unit: before['unit']?.toString() ?? '',
          touched: prepared.movements.any((m) => m.data['productId'] == e.key),
        ),
      );
    }
    return prepared;
  }

  Future<List<StockAlert>> _applyWrites(
    Transaction tx,
    _Prepared prepared,
  ) async {
    final alerts = <StockAlert>[];
    for (final p in prepared.products) {
      if (!p.touched) continue;
      tx.update(p.ref, {
        'quantity': p.quantity,
        'costPrice': p.cost,
        'stockState': p.newState.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Alert only when the state actually worsens (no repeated spam).
      if (p.newState.name != p.oldState && p.newState != StockState.ok) {
        alerts.add(StockAlert(p.name, p.newState, p.quantity, p.unit));
      }
    }
    for (final m in prepared.movements) {
      tx.set(m.ref, m.data);
    }
    return alerts;
  }

  Map<String, dynamic> _movementData({
    required String productId,
    required String productName,
    required MovementType type,
    required double change,
    required double previous,
    required double resulting,
    double? unitCost,
    String reason = '',
    String note = '',
    String refType = '',
    String refId = '',
  }) => {
    'businessId': businessId,
    'productId': productId,
    'productName': productName,
    'type': type.code,
    'quantityChange': change,
    'previousQuantity': previous,
    'resultingQuantity': resulting,
    'unitCost': ?unitCost,
    'reason': reason,
    'note': note,
    'refType': refType,
    'refId': refId,
    'userId': uid,
    'userName': userName,
    'createdAt': FieldValue.serverTimestamp(),
  };

  Future<void> _notifyAlerts(List<StockAlert> alerts) async {
    if (!notify || alerts.isEmpty) return;
    for (final a in alerts) {
      try {
        await NotificationService.stockAlert(
          a.state == StockState.out
              ? '${a.productName}: out of stock'
              : '${a.productName}: low stock (${formatQty(a.quantity)} ${a.unit})',
        );
      } catch (e) {
        debugPrint('Stock alert skipped: $e');
      }
    }
  }
}

class _Prepared {
  final List<_PreparedMovement> movements = [];
  final List<_PreparedProduct> products = [];
}

class _PreparedMovement {
  _PreparedMovement({required this.ref, required this.data});
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;
}

class _PreparedProduct {
  _PreparedProduct({
    required this.ref,
    required this.quantity,
    required this.cost,
    required this.oldState,
    required this.newState,
    required this.name,
    required this.unit,
    required this.touched,
  });
  final DocumentReference<Map<String, dynamic>> ref;
  final double quantity;
  final double cost;
  final String oldState;
  final StockState newState;
  final String name;
  final String unit;
  final bool touched;
}
