import 'package:cloud_firestore/cloud_firestore.dart';

/// Quantities are stored with at most 3 decimals so that 1.5 kg / 2.75 L work
/// and floating point noise never accumulates in the ledger.
double roundQty(num value) => (value * 1000).round() / 1000;

double roundMoney(num value) => (value * 100).round() / 100;

String formatQty(num value) {
  final v = roundQty(value);
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

String formatMoney(num value) => value
    .round()
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

const stockUnits = <String>[
  'piece',
  'packet',
  'box',
  'bag',
  'kg',
  'gram',
  'litre',
  'ml',
  'bottle',
  'metre',
];

/// Whether a unit normally allows fractions (1.5 kg, 2.75 L).
bool unitAllowsDecimals(String unit) =>
    const {'kg', 'gram', 'litre', 'ml', 'metre'}.contains(unit);

enum StockState { ok, low, out }

StockState stockStateFor(double quantity, double threshold) {
  if (quantity <= 0) return StockState.out;
  if (quantity <= threshold) return StockState.low;
  return StockState.ok;
}

/// Weighted-average cost after receiving [inQty] at [inCost].
double weightedAverageCost({
  required double oldQty,
  required double oldCost,
  required double inQty,
  required double inCost,
}) {
  if (inQty <= 0) return oldCost;
  if (oldQty <= 0) return roundMoney(inCost);
  final total = oldQty + inQty;
  return roundMoney((oldQty * oldCost + inQty * inCost) / total);
}

enum MovementType {
  openingStock('opening_stock', 1),
  purchase('purchase', 1),
  sale('sale', -1),
  saleReversal('sale_reversal', 1),
  customerReturn('customer_return', 1),
  supplierReturn('supplier_return', -1),
  damaged('damaged', -1),
  expired('expired', -1),
  lost('lost', -1),
  internalUse('internal_use', -1),
  adjustmentIn('adjustment_in', 1),
  adjustmentOut('adjustment_out', -1),
  correction('correction', 0);

  const MovementType(this.code, this.sign);
  final String code;

  /// +1 adds stock, -1 removes stock, 0 = signed (corrections).
  final int sign;

  String get labelKey => 'stk_mv_$code';

  static MovementType fromCode(String? code) => MovementType.values.firstWhere(
    (t) => t.code == code,
    orElse: () => MovementType.correction,
  );

  /// Types a user may pick in the manual adjustment form.
  static const manual = <MovementType>[
    adjustmentIn,
    adjustmentOut,
    damaged,
    expired,
    lost,
    internalUse,
    customerReturn,
    supplierReturn,
    correction,
  ];
}

class StockException implements Exception {
  StockException(this.messageKey, [this.args = const {}]);
  final String messageKey;
  final Map<String, String> args;

  @override
  String toString() => messageKey;
}

class Product {
  Product({
    this.id,
    required this.name,
    required this.sku,
    this.barcode = '',
    this.category = '',
    this.description = '',
    this.unit = 'piece',
    this.costPrice = 0,
    this.sellPrice = 0,
    this.quantity = 0,
    this.lowStockThreshold = 0,
    this.tracked = true,
    this.allowNegative = false,
    this.supplier = '',
    this.imageUrl = '',
    this.active = true,
    this.stockState = StockState.out,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String name;
  final String sku;
  final String barcode;
  final String category;
  final String description;
  final String unit;

  /// Weighted-average purchase cost per unit.
  final double costPrice;
  final double sellPrice;
  final double quantity;
  final double lowStockThreshold;

  /// Services / non-stock items are untracked and never change inventory.
  final bool tracked;
  final bool allowNegative;
  final String supplier;
  final String imageUrl;
  final bool active;
  final StockState stockState;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get stockCostValue => tracked ? quantity * costPrice : 0;
  double get stockSellValue => tracked ? quantity * sellPrice : 0;
  bool get isLow => tracked && stockState == StockState.low;
  bool get isOut => tracked && stockState == StockState.out;

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final qty = (d['quantity'] as num?)?.toDouble() ?? 0;
    final threshold = (d['lowStockThreshold'] as num?)?.toDouble() ?? 0;
    return Product(
      id: doc.id,
      name: d['name']?.toString() ?? '',
      sku: d['sku']?.toString() ?? '',
      barcode: d['barcode']?.toString() ?? '',
      category: d['category']?.toString() ?? '',
      description: d['description']?.toString() ?? '',
      unit: d['unit']?.toString() ?? 'piece',
      costPrice: (d['costPrice'] as num?)?.toDouble() ?? 0,
      sellPrice: (d['sellPrice'] as num?)?.toDouble() ?? 0,
      quantity: qty,
      lowStockThreshold: threshold,
      tracked: d['tracked'] != false,
      allowNegative: d['allowNegative'] == true,
      supplier: d['supplier']?.toString() ?? '',
      imageUrl: d['imageUrl']?.toString() ?? '',
      stockState: stockStateFor(qty, threshold),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Editable details. Quantity and cost are intentionally excluded: they only
  /// change through stock movements.
  Map<String, dynamic> detailsMap() => {
    'name': name.trim(),
    'sku': sku.trim(),
    'skuKey': skuKey(sku),
    'barcodeKey': skuKey(barcode),
    'barcode': barcode.trim(),
    'category': category.trim(),
    'description': description.trim(),
    'unit': unit,
    'sellPrice': roundMoney(sellPrice),
    'lowStockThreshold': roundQty(lowStockThreshold),
    'tracked': tracked,
    'allowNegative': allowNegative,
    'supplier': supplier.trim(),
    'imageUrl': imageUrl,
    'active': active,
  };

  static String skuKey(String sku) =>
      sku.trim().toLowerCase().replaceAll('/', '-');

  /// Lower-case letters and digits only, for duplicate-name detection.
  static String nameKey(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u00C0-\uFFFF]'), '');
}

/// Existing products whose name looks the same as [name] (equal, or one name
/// contained in the other when it is at least 4 characters long).
List<Product> findSimilarNames(
  Iterable<Product> products,
  String name, {
  String? excludeId,
}) {
  final k = Product.nameKey(name);
  if (k.isEmpty) return const [];
  return products.where((p) {
    if (p.id == excludeId || !p.active) return false;
    final o = Product.nameKey(p.name);
    if (o.isEmpty) return false;
    if (o == k) return true;
    final shorter = o.length < k.length ? o : k;
    final longer = o.length < k.length ? k : o;
    return shorter.length >= 4 && longer.contains(shorter);
  }).toList();
}

class StockMovement {
  StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantityChange,
    required this.previousQuantity,
    required this.resultingQuantity,
    this.unitCost,
    this.reason = '',
    this.note = '',
    this.refType = '',
    this.refId = '',
    this.userId = '',
    this.userName = '',
    this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final MovementType type;
  final double quantityChange;
  final double previousQuantity;
  final double resultingQuantity;
  final double? unitCost;
  final String reason;
  final String note;
  final String refType;
  final String refId;
  final String userId;
  final String userName;
  final DateTime? createdAt;

  factory StockMovement.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return StockMovement(
      id: doc.id,
      productId: d['productId']?.toString() ?? '',
      productName: d['productName']?.toString() ?? '',
      type: MovementType.fromCode(d['type']?.toString()),
      quantityChange: (d['quantityChange'] as num?)?.toDouble() ?? 0,
      previousQuantity: (d['previousQuantity'] as num?)?.toDouble() ?? 0,
      resultingQuantity: (d['resultingQuantity'] as num?)?.toDouble() ?? 0,
      unitCost: (d['unitCost'] as num?)?.toDouble(),
      reason: d['reason']?.toString() ?? '',
      note: d['note']?.toString() ?? '',
      refType: d['refType']?.toString() ?? '',
      refId: d['refId']?.toString() ?? '',
      userId: d['userId']?.toString() ?? '',
      userName: d['userName']?.toString() ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class PurchaseLine {
  PurchaseLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
  });

  final String productId;
  final String productName;
  final double quantity;
  final double unitCost;

  double get total => roundMoney(quantity * unitCost);

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'quantity': roundQty(quantity),
    'unitCost': roundMoney(unitCost),
    'total': total,
  };
}

class Purchase {
  Purchase({
    required this.id,
    required this.supplier,
    required this.reference,
    required this.date,
    required this.lines,
    required this.total,
    this.note = '',
    this.createdBy = '',
  });

  final String id;
  final String supplier;
  final String reference;
  final DateTime date;
  final List<Map<String, dynamic>> lines;
  final double total;
  final String note;
  final String createdBy;

  factory Purchase.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Purchase(
      id: doc.id,
      supplier: d['supplier']?.toString() ?? '',
      reference: d['reference']?.toString() ?? '',
      date: (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lines: (d['lines'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      total: (d['total'] as num?)?.toDouble() ?? 0,
      note: d['note']?.toString() ?? '',
      createdBy: d['createdBy']?.toString() ?? '',
    );
  }
}

/// A line of a sale that should consume stock.
class SaleLine {
  const SaleLine({required this.productId, required this.quantity});
  final String productId;
  final double quantity;
}
