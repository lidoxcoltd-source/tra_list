import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/notification_service.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:tra_list/services/pdf/pdf_saver.dart' as pdf_saver;
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'stock_media.dart';
import 'stock_models.dart';
import 'pos_list_document.dart';
import 'stock_service.dart';
import 'stock_ui.dart';
import 'bar_orders_page.dart';

class _CartLine {
  _CartLine(this.product, this.qty);
  Product product;
  double qty;
  double get amount => roundMoney(qty * product.sellPrice);
}

/// Quick sale screen: scan products, build a cart, complete the sale.
/// Completing creates the invoice and deducts stock in one transaction.
class PosPage extends StatefulWidget {
  const PosPage({super.key, this.initialProduct});
  final Product? initialProduct;

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final _service = StockService.current();
  final _codeCtl = TextEditingController();
  final _codeFocus = FocusNode();
  final _customer = TextEditingController();
  final _table = TextEditingController();
  final _cart = <_CartLine>[];
  List<Product> _products = [];
  bool _loaded = false;
  String? _loadError;
  bool _initialProductAdded = false;
  bool _cameraOn = false;
  bool _saving = false;
  bool _listBusy = false;
  bool _barOrderMode = false;
  String _payment = 'cash';
  String _lastCode = '';
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);
  MobileScannerController? _scanner;
  // One id per sale attempt: a retry after a timeout reuses the same
  // invoice document, so stock cannot be deducted twice.
  late DocumentReference<Map<String, dynamic>> _saleRef = _newRef();
  late DocumentReference<Map<String, dynamic>> _listRef = _newListRef();

  DocumentReference<Map<String, dynamic>> _newRef() => FirebaseFirestore
      .instance
      .collection('users')
      .doc(BusinessAccessService.businessId)
      .collection('invoices')
      .doc();

  DocumentReference<Map<String, dynamic>> _newListRef() => FirebaseFirestore
      .instance
      .collection('users')
      .doc(BusinessAccessService.businessId)
      .collection('posLists')
      .doc();

  @override
  void initState() {
    super.initState();
    _service.watchProducts().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _products = list;
          _loaded = true;
          _loadError = null;
          for (final l in _cart) {
            final fresh = list.where((p) => p.id == l.product.id).firstOrNull;
            if (fresh != null) l.product = fresh;
          }
        });
        _addInitialProduct(list);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Could not load POS products: $error');
        debugPrint(
          'POS access state: ready=${BusinessAccessService.isReady.value}, '
          'active=${BusinessAccessService.isActive.value}, '
          'barMode=${BusinessAccessService.barModeEnabled.value}, '
          'barWaiter=${BusinessAccessService.isBarWaiter}, '
          'bartender=${BusinessAccessService.isBarBartender}, '
          'invoiceCreate=${BusinessAccessService.can('invoices', 'create')}, '
          'stockView=${BusinessAccessService.can('stock', 'view')}, '
          'stockCreate=${BusinessAccessService.can('stock', 'create')}, '
          'stockEdit=${BusinessAccessService.can('stock', 'edit')}',
        );
        debugPrintStack(stackTrace: stackTrace);
        if (!mounted) return;
        setState(() {
          _loaded = true;
          _loadError =
              error is FirebaseException && error.code == 'permission-denied'
              ? 'stk_err_permission'.tr
              : stockErrorText(error);
        });
      },
    );
  }

  void _addInitialProduct(List<Product> products) {
    if (_initialProductAdded || widget.initialProduct == null) return;
    _initialProductAdded = true;
    final initial = products
        .where((p) => p.id == widget.initialProduct!.id)
        .firstOrNull;
    if (initial == null || !initial.active) {
      stockToast('stk_error'.tr, 'stk_err_product_missing'.tr, error: true);
      return;
    }
    _add(initial, 1);
  }

  @override
  void dispose() {
    _scanner?.dispose();
    _codeCtl.dispose();
    _codeFocus.dispose();
    _customer.dispose();
    _table.dispose();
    super.dispose();
  }

  double get _total => _cart.fold(0, (s, l) => s + l.amount);

  Future<void> _toggleCamera() async {
    if (kIsWeb) {
      final code = await scanCode(context);
      if (code != null && mounted) await _onCode(code);
      return;
    }
    setState(() {
      _cameraOn = !_cameraOn;
      if (_cameraOn) {
        _scanner = MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          detectionTimeoutMs: 600,
        );
      } else {
        _scanner?.dispose();
        _scanner = null;
      }
    });
  }

  /// Reads a code from a photo (camera or file); used when live scanning
  /// is refused or unavailable.
  Future<void> _scanPhoto(ImageSource source) async {
    final code = await scanFromImage(context, source);
    if (code != null && mounted) _onCode(code);
  }

  Future<void> _retryPosCamera() async {
    final scanner = _scanner;
    if (scanner == null) return;
    try {
      await scanner.stop();
      await scanner.start();
    } catch (e) {
      stockToast('stk_error'.tr, stockErrorText(e), error: true);
    }
  }

  Future<void> _onCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    final now = DateTime.now();
    // The camera sees the same label many times per second.
    if (code == _lastCode &&
        now.difference(_lastScanAt).inMilliseconds < 1500) {
      return;
    }
    _lastCode = code;
    _lastScanAt = now;
    var p = findProductByCode(_products.where((p) => p.active), code);
    p ??= await _service.findProductByCode(code);
    if (!mounted) return;
    if (p != null && !p.active) p = null;
    if (p == null) {
      HapticFeedback.heavyImpact();
      stockToast(
        'stk_error'.tr,
        fmtText('stk_scan_not_found', {'code': code}),
        error: true,
      );
      return;
    }
    if (_add(p, 1)) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    }
  }

  /// Adds [qty] of [p]; false when refused (e.g. not enough stock).
  bool _add(Product p, double qty) {
    final existing = _cart.where((l) => l.product.id == p.id).firstOrNull;
    final next = roundQty((existing?.qty ?? 0) + qty);
    if (!_withinStock(p, next)) return false;
    setState(() {
      if (existing == null) {
        _cart.add(_CartLine(p, next));
      } else {
        existing.qty = next;
      }
    });
    return true;
  }

  bool _withinStock(Product p, double qty) {
    final reservationLimitsSale =
        p.tracked &&
        (p.reservedQuantity > 0
            ? qty > p.availableQuantity
            : !p.allowNegative && qty > p.quantity);
    if (reservationLimitsSale) {
      HapticFeedback.heavyImpact();
      stockToast(
        'stk_error'.tr,
        fmtText('stk_err_insufficient', {
          'name': p.name,
          'available': formatQty(p.availableQuantity),
          'unit': unitLabel(p.unit),
        }),
        error: true,
      );
      return false;
    }
    return true;
  }

  void _setQty(_CartLine l, double qty) {
    if (qty <= 0) {
      setState(() => _cart.remove(l));
      return;
    }
    final q = roundQty(qty);
    if (!_withinStock(l.product, q)) return;
    setState(() => l.qty = q);
  }

  Future<void> _editQty(_CartLine l) async {
    final c = TextEditingController(text: formatQty(l.qty));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.product.name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: stockInput('stk_quantity'.tr),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('stk_cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.trim())),
            child: Text('stk_ok'.tr),
          ),
        ],
      ),
    );
    c.dispose();
    if (v != null) _setQty(l, v);
  }

  Future<void> _browse() async {
    final p = await pickProduct(context, _products);
    if (p != null) _add(p, 1);
  }

  String _invoiceNumber() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'POS-${n.year % 100}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  Future<void> _complete() async {
    if (_saving || _listBusy || _cart.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final company = await ProfileService.loadOrCreate();
      final number = _invoiceNumber();
      final now = DateTime.now();
      final date = '${now.day}/${now.month}/${now.year}';
      final items = [
        for (final l in _cart)
          {
            'description': l.product.name,
            'qty': l.qty == l.qty.roundToDouble() ? l.qty.toInt() : l.qty,
            'unit': l.product.sellPrice,
            'amount': l.amount,
            'productId': l.product.id,
          },
      ];
      final data = {
        'company': company,
        'client': {'name': _customer.text.trim()},
        'invoice': {
          'number': number,
          'issueDate': date,
          'dueDate': date,
          'paymentMethod': company['paymentMethod'],
        },
        'items': items,
        'total': _total,
      };
      await _service.finalizeSale(
        saleRef: _saleRef,
        saleData: {
          ...data,
          'kind': 'invoice',
          'id': _saleRef.id,
          'uid': user.uid,
          'cashierUid': user.uid,
          'cashierName': (user.displayName ?? '').trim().isNotEmpty
              ? user.displayName!.trim()
              : (user.email ?? ''),
          'source': 'pos',
          'salePayment': _payment,
          'createdAt': FieldValue.serverTimestamp(),
        },
        lines: [
          for (final l in _cart)
            SaleLine(productId: l.product.id!, quantity: l.qty),
        ],
      );
      await NotificationService.notifyOwner(
        action: 'invoice',
        summary: 'POS sale $number (TSH ${_total.toStringAsFixed(0)})',
        amount: _total,
      );
      if (!mounted) return;
      final total = _total;
      final receipt = Map<String, dynamic>.from(data);
      _reset();
      await _showDone(number, total, receipt);
    } catch (e) {
      if (!mounted) return;
      stockToast(
        'stk_error'.tr,
        e is FirebaseException && e.code == 'permission-denied'
            ? 'stk_err_permission'.tr
            : stockErrorText(e),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitBarOrder() async {
    if (_saving || _listBusy || _cart.isEmpty) return;
    if (_table.text.trim().isEmpty) {
      stockToast('stk_error'.tr, 'bar_table_required'.tr, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.createBarOrder(
        tableNumber: _table.text,
        customerName: _customer.text,
        lines: [
          for (final line in _cart)
            SaleLine(productId: line.product.id!, quantity: line.qty),
        ],
      );
      if (!mounted) return;
      _reset();
      stockToast('bar_order_sent'.tr, 'bar_order_sent_help'.tr);
    } catch (e) {
      if (!mounted) return;
      stockToast(
        'stk_error'.tr,
        e is FirebaseException && e.code == 'permission-denied'
            ? 'stk_err_permission'.tr
            : stockErrorText(e),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _listDateText(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _generateList() async {
    if (_listBusy || _cart.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      stockToast('stk_error'.tr, 'stk_err_permission'.tr, error: true);
      return;
    }

    setState(() => _listBusy = true);
    try {
      final now = DateTime.now();
      final data = <String, dynamic>{
        'listNumber': 'LIST-${_listRef.id.substring(0, 8).toUpperCase()}',
        'businessId': BusinessAccessService.businessId,
        'createdBy': user.uid,
        'createdByName': (user.displayName ?? '').trim(),
        'customerName': _customer.text.trim(),
        'dateText': _listDateText(now),
        'createdAt': FieldValue.serverTimestamp(),
        'items': [
          for (final line in _cart)
            {
              'productId': line.product.id,
              'name': line.product.name,
              'quantity': line.qty,
              'unit': line.product.unit,
              'unitPrice': line.product.sellPrice,
              'amount': line.amount,
            },
        ],
        'total': _total,
      };
      await _listRef.set(data);
      final previewData = {...data, 'createdAt': Timestamp.fromDate(now)};
      _listRef = _newListRef();
      if (!mounted) return;
      stockToast('pos_list_saved'.tr, 'pos_list_saved_message'.tr);
      await _showListPreview(previewData);
    } catch (e) {
      stockToast(
        'stk_error'.tr,
        e is FirebaseException && e.code == 'permission-denied'
            ? 'stk_err_permission'.tr
            : stockErrorText(e),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _listBusy = false);
    }
  }

  Future<void> _showListPreview(Map<String, dynamic> data) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.88,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined, color: kStockNavy),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'pos_list_preview'.tr,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'stk_cancel'.tr,
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: _listReceipt(data),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _shareListAsPhoto(data),
                        icon: const Icon(Icons.share_outlined),
                        label: Text('pos_share_photo'.tr),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kStockNavy,
                        ),
                        onPressed: () => _printList(data),
                        icon: const Icon(Icons.print_outlined),
                        label: Text('pos_print'.tr),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _listReceipt(Map<String, dynamic> data) {
    final items = (data['items'] as List? ?? const []).whereType<Map>().map(
      (item) => Map<String, dynamic>.from(item),
    );
    final customer = data['customerName']?.toString().trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E9F2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'pos_list_title'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: kStockNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data['listNumber']?.toString() ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
          Text(
            data['dateText']?.toString() ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
          if (customer.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${'pos_list_customer'.tr}: $customer'),
          ],
          const Divider(height: 24),
          for (final item in items) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'TZS ${formatMoney((item['amount'] as num?) ?? 0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${formatQty((item['quantity'] as num?) ?? 0)} '
              '${unitLabel(item['unit']?.toString() ?? '')} × '
              'TZS ${formatMoney((item['unitPrice'] as num?) ?? 0)}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const SizedBox(height: 10),
          ],
          const Divider(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'stk_total'.tr,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                'TZS ${formatMoney((data['total'] as num?) ?? 0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: kStockNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'pos_list_not_sale'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _shareListAsPhoto(Map<String, dynamic> data) async {
    try {
      final pdf = await PosListDocument.generateBytes(_localizedListData(data));
      final number = data['listNumber']?.toString() ?? 'list';
      final files = <XFile>[];
      final names = <String>[];
      var pageNumber = 0;
      await for (final page in Printing.raster(pdf, dpi: 144)) {
        pageNumber++;
        final name = '${number}_$pageNumber.png';
        final png = await page.toPng();
        names.add(name);
        if (kIsWeb) {
          await pdf_saver.downloadBytes(png, name, 'image/png');
        } else {
          files.add(XFile.fromData(png, mimeType: 'image/png'));
        }
      }
      if (pageNumber == 0) {
        throw StateError('No list image was generated.');
      }
      if (kIsWeb) {
        stockToast('pos_share_photo'.tr, 'pos_photo_downloaded'.tr);
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: files, fileNameOverrides: names, subject: number),
      );
    } catch (e) {
      stockToast('stk_error'.tr, stockErrorText(e), error: true);
    }
  }

  Future<void> _printList(Map<String, dynamic> data) async {
    try {
      final pdf = await PosListDocument.generateBytes(_localizedListData(data));
      await Printing.layoutPdf(onLayout: (_) async => pdf);
    } catch (e) {
      stockToast('stk_error'.tr, stockErrorText(e), error: true);
    }
  }

  Map<String, dynamic> _localizedListData(Map<String, dynamic> data) => {
    ...data,
    'documentTitle': 'pos_list_title'.tr,
    'customerLabel': 'pos_list_customer'.tr,
    'totalLabel': 'pos_list_total'.tr,
    'footerNote': 'pos_list_not_sale'.tr,
  };

  Future<void> _showListHistory() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Future<void>.value();
    final lists = FirebaseFirestore.instance
        .collection('users')
        .doc(BusinessAccessService.businessId)
        .collection('posLists');
    final Stream<QuerySnapshot<Map<String, dynamic>>> stream =
        BusinessAccessService.isOwner.value
        ? lists.orderBy('createdAt', descending: true).limit(50).snapshots()
        : lists.where('createdBy', isEqualTo: user.uid).limit(50).snapshots();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kStockBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 10, 10),
              child: Row(
                children: [
                  const Icon(Icons.history, color: kStockNavy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'pos_list_history'.tr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          '${'stk_error'.tr}: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs.toList()
                    ..sort((a, b) {
                      final aDate = a.data()['createdAt'];
                      final bDate = b.data()['createdAt'];
                      final aTime = aDate is Timestamp
                          ? aDate.millisecondsSinceEpoch
                          : 0;
                      final bTime = bDate is Timestamp
                          ? bDate.millisecondsSinceEpoch
                          : 0;
                      return bTime.compareTo(aTime);
                    });
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        'pos_no_lists'.tr,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final items = data['items'] as List? ?? const [];
                      return StockCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: kStockLight,
                            child: Icon(
                              Icons.receipt_long_outlined,
                              color: kStockNavy,
                            ),
                          ),
                          title: Text(
                            data['listNumber']?.toString() ?? 'pos_list'.tr,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${items.length} ${'pos_items'.tr} · '
                            '${data['dateText']?.toString() ?? ''}',
                          ),
                          trailing: Text(
                            'TZS ${formatMoney((data['total'] as num?) ?? 0)}',
                            style: const TextStyle(
                              color: kStockNavy,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _showListPreview({...data, 'id': doc.id});
                              }
                            });
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _reset() {
    setState(() {
      _cart.clear();
      _customer.clear();
      _table.clear();
      _payment = 'cash';
      _saleRef = _newRef();
    });
  }

  Future<void> _showDone(
    String number,
    double total,
    Map<String, dynamic> receipt,
  ) {
    var busyAction = '';

    Future<void> saveOrShare(
      BuildContext dialogContext,
      StateSetter setDialogState, {
      required bool share,
    }) async {
      setDialogState(() => busyAction = share ? 'share' : 'save');
      try {
        final bytes = await InvoicePdf.generateBytes(receipt);
        final fileName =
            'Receipt_${number.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.pdf';
        if (share) {
          await SharePlus.instance.share(
            ShareParams(
              files: [
                XFile.fromData(
                  bytes,
                  mimeType: 'application/pdf',
                  name: fileName,
                ),
              ],
              fileNameOverrides: [fileName],
              title: number,
              subject: number,
            ),
          );
        } else {
          await pdf_saver.savePdf(bytes, fileName);
          if (dialogContext.mounted) {
            stockToast('stk_saved'.tr, 'pos_receipt_saved'.tr);
          }
        }
      } catch (error) {
        if (dialogContext.mounted) {
          stockToast('stk_error'.tr, stockErrorText(error), error: true);
        }
      } finally {
        if (dialogContext.mounted) {
          setDialogState(() => busyAction = '');
        }
      }
    }

    return showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: kStockOk, size: 48),
          title: Text('pos_sale_done'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$number\nTZS ${formatMoney(total)}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busyAction.isEmpty
                        ? () => saveOrShare(ctx, setDialogState, share: false)
                        : null,
                    icon: busyAction == 'save'
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text('pos_save_receipt'.tr),
                  ),
                  OutlinedButton.icon(
                    onPressed: busyAction.isEmpty
                        ? () => saveOrShare(ctx, setDialogState, share: true)
                        : null,
                    icon: busyAction == 'share'
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share_outlined),
                    label: Text('pos_share_receipt'.tr),
                  ),
                ],
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            OutlinedButton.icon(
              onPressed: busyAction.isEmpty
                  ? () async {
                      try {
                        await InvoicePdf.generate(receipt);
                      } catch (error) {
                        stockToast(
                          'stk_error'.tr,
                          stockErrorText(error),
                          error: true,
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.receipt_long),
              label: Text('pos_receipt'.tr),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kStockBlue),
              onPressed: busyAction.isEmpty ? () => Navigator.pop(ctx) : null,
              child: Text('pos_new_sale'.tr),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final wide = MediaQuery.of(context).size.width >= 900;
      final scanPane = _scanPane();
      final cartPane = _cartPane();
      return StockScaffold(
        title: BusinessAccessService.isBarBartender
            ? 'bar_bartender_title'.tr
            : 'pos_title'.tr,
        maxWidth: 1200,
        actions: [
          if (BusinessAccessService.barModeEnabled.value)
            IconButton(
              tooltip: 'bar_orders'.tr,
              onPressed: () => Get.to(() => const BarOrdersPage()),
              icon: const Icon(Icons.room_service_outlined),
            ),
          if (!BusinessAccessService.isBarBartender)
            IconButton(
              tooltip: 'pos_list_history'.tr,
              onPressed: _showListHistory,
              icon: const Icon(Icons.history),
            ),
          if (_cart.isNotEmpty)
            IconButton(
              tooltip: 'pos_clear'.tr,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _saving || _listBusy ? null : _reset,
            ),
        ],
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 420, child: scanPane),
                  Expanded(child: cartPane),
                ],
              )
            : Column(
                children: [
                  scanPane,
                  Expanded(child: cartPane),
                ],
              ),
      );
    });
  }

  Widget _scanPane() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: StockCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (BusinessAccessService.isBarBartender) ...[
              Text(
                'bar_bartender_help'.tr,
                style: const TextStyle(
                  color: kStockNavy,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (!kIsWeb && _cameraOn && _scanner != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: MobileScanner(
                    controller: _scanner!,
                    placeholderBuilder: (context) => ScannerLoadingFallback(
                      compact: true,
                      onPhoto: () => _scanPhoto(ImageSource.camera),
                      onUpload: () => _scanPhoto(ImageSource.gallery),
                      onRetry: _retryPosCamera,
                    ),
                    onDetect: (capture) {
                      for (final b in capture.barcodes) {
                        final v = b.rawValue;
                        if (v != null && v.isNotEmpty) {
                          _onCode(v);
                          return;
                        }
                      }
                    },
                    errorBuilder: (context, error) => Container(
                      color: Colors.black87,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'stk_camera_error'.tr,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: Text('stk_scan_take_photo'.tr),
                            onPressed: () => _scanPhoto(ImageSource.camera),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!kIsWeb && _cameraOn && _scanner != null)
              const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtl,
                    focusNode: _codeFocus,
                    autofocus: !cameraScanSupported,
                    textInputAction: TextInputAction.done,
                    decoration: stockInput(
                      'pos_code_hint'.tr,
                      icon: Icons.qr_code_2,
                    ),
                    // USB / Bluetooth scanners type the code then press Enter.
                    onSubmitted: (v) {
                      _onCode(v);
                      _codeCtl.clear();
                      _codeFocus.requestFocus();
                    },
                  ),
                ),
                if (cameraScanSupported) ...[
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: _cameraOn ? kStockBad : kStockNavy,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                    ),
                    tooltip: _cameraOn ? 'pos_camera_off'.tr : 'stk_scan'.tr,
                    onPressed: _toggleCamera,
                    icon: Icon(
                      _cameraOn ? Icons.videocam_off : Icons.qr_code_scanner,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _scanAction(
                  tooltip: 'stk_scan_take_photo'.tr,
                  icon: Icons.photo_camera_outlined,
                  onPressed: () => _scanPhoto(ImageSource.camera),
                ),
                _scanAction(
                  tooltip: 'stk_scan_upload'.tr,
                  icon: Icons.image_outlined,
                  onPressed: () => _scanPhoto(ImageSource.gallery),
                ),
                if (!kIsWeb && _cameraOn && _scanner != null)
                  _scanAction(
                    tooltip: 'stk_camera_switch'.tr,
                    icon: Icons.cameraswitch_outlined,
                    onPressed: () => _scanner!.switchCamera(),
                  ),
                _scanAction(
                  tooltip: 'stk_products'.tr,
                  icon: Icons.search_rounded,
                  onPressed: _browse,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton.outlined(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: kStockNavy,
        side: const BorderSide(color: MjasiColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }

  Widget _cartPane() {
    return Column(
      children: [
        Expanded(
          child: _cart.isEmpty
              ? StockMessage(
                  icon: Icons.shopping_cart_outlined,
                  text: 'pos_empty'.tr,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  itemCount: _cart.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _lineTile(_cart[i]),
                ),
        ),
        _checkoutBar(),
      ],
    );
  }

  Widget _lineTile(_CartLine l) {
    final p = l.product;
    return Dismissible(
      key: ValueKey(p.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: kStockBad,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => setState(() => _cart.remove(l)),
      child: StockCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ProductImage(url: p.imageUrl, size: 48, radius: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${formatMoney(p.sellPrice)} / ${unitLabel(p.unit)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  Text(
                    'TZS ${formatMoney(l.amount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: kStockNavy,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => _setQty(l, l.qty - 1),
            ),
            InkWell(
              onTap: () => _editQty(l),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  formatQty(l.qty),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _add(p, 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkoutBar() {
    final barModeEnabled = BusinessAccessService.barModeEnabled.value;
    final isBarBartender = BusinessAccessService.isBarBartender;
    final isOrderMode = _barOrderMode && barModeEnabled && !isBarBartender;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E9F2))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (barModeEnabled && !isBarBartender)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.point_of_sale_outlined),
                    label: Text('bar_direct_sale'.tr),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.room_service_outlined),
                    label: Text('bar_send_order'.tr),
                  ),
                ],
                selected: {_barOrderMode},
                onSelectionChanged: _saving || _listBusy
                    ? null
                    : (selection) =>
                          setState(() => _barOrderMode = selection.first),
              ),
            if (isOrderMode) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _table,
                maxLength: 80,
                decoration: stockInput(
                  'bar_table'.tr,
                  icon: Icons.table_restaurant_outlined,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customer,
                    maxLength: 120,
                    decoration: stockInput(
                      'pos_customer'.tr,
                      icon: Icons.person_outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!isOrderMode) ...[
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'cash', label: Text('pos_cash'.tr)),
                    ButtonSegment(
                      value: 'mobile',
                      label: Text('pos_mobile'.tr),
                    ),
                    ButtonSegment(value: 'card', label: Text('pos_card'.tr)),
                  ],
                  selected: {_payment},
                  onSelectionChanged: (s) => setState(() => _payment = s.first),
                ),
              ),
              const SizedBox(height: 10),
              if (!isBarBartender)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _cart.isEmpty || _listBusy
                        ? null
                        : _generateList,
                    icon: _listBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.receipt_long_outlined),
                    label: Text(
                      _listBusy ? 'pos_list_saving'.tr : 'pos_generate_list'.tr,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_cart.length} ${'pos_items'.tr}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'TZS ${formatMoney(_total)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: kStockNavy,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kStockOk),
                    onPressed: _saving || _listBusy || _cart.isEmpty
                        ? null
                        : (isOrderMode ? _submitBarOrder : _complete),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      isOrderMode ? 'bar_send_order'.tr : 'pos_complete'.tr,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
