import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/notification_service.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:tra_list/services/profile_service.dart';
import 'stock_media.dart';
import 'stock_models.dart';
import 'stock_service.dart';
import 'stock_ui.dart';

class _CartLine {
  _CartLine(this.product, this.qty);
  Product product;
  double qty;
  double get amount => roundMoney(qty * product.sellPrice);
}

/// Quick sale screen: scan products, build a cart, complete the sale.
/// Completing creates the invoice and deducts stock in one transaction.
class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final _service = StockService.current();
  final _codeCtl = TextEditingController();
  final _codeFocus = FocusNode();
  final _customer = TextEditingController();
  final _cart = <_CartLine>[];
  List<Product> _products = [];
  bool _loaded = false;
  bool _cameraOn = false;
  bool _saving = false;
  String _payment = 'cash';
  String _lastCode = '';
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);
  MobileScannerController? _scanner;
  // One id per sale attempt: a retry after a timeout reuses the same
  // invoice document, so stock cannot be deducted twice.
  late DocumentReference<Map<String, dynamic>> _saleRef = _newRef();

  DocumentReference<Map<String, dynamic>> _newRef() => FirebaseFirestore
      .instance
      .collection('users')
      .doc(BusinessAccessService.businessId)
      .collection('invoices')
      .doc();

  @override
  void initState() {
    super.initState();
    _service.watchProducts().listen((list) {
      if (!mounted) return;
      setState(() {
        _products = list;
        _loaded = true;
        for (final l in _cart) {
          final fresh = list.where((p) => p.id == l.product.id).firstOrNull;
          if (fresh != null) l.product = fresh;
        }
      });
    });
  }

  @override
  void dispose() {
    _scanner?.dispose();
    _codeCtl.dispose();
    _codeFocus.dispose();
    _customer.dispose();
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
    if (p.tracked && !p.allowNegative && qty > p.quantity) {
      HapticFeedback.heavyImpact();
      stockToast(
        'stk_error'.tr,
        fmtText('stk_err_insufficient', {
          'name': p.name,
          'available': formatQty(p.quantity),
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
    if (_saving || _cart.isEmpty) return;
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

  void _reset() {
    setState(() {
      _cart.clear();
      _customer.clear();
      _payment = 'cash';
      _saleRef = _newRef();
    });
  }

  Future<void> _showDone(
    String number,
    double total,
    Map<String, dynamic> receipt,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: kStockOk, size: 48),
        title: Text('pos_sale_done'.tr),
        content: Text(
          '$number\nTZS ${formatMoney(total)}',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.receipt_long),
            label: Text('pos_receipt'.tr),
            onPressed: () async {
              try {
                await InvoicePdf.generate(receipt);
              } catch (e) {
                stockToast('stk_error'.tr, '$e', error: true);
              }
            },
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kStockBlue),
            onPressed: () => Navigator.pop(ctx),
            child: Text('pos_new_sale'.tr),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final scanPane = _scanPane();
    final cartPane = _cartPane();
    return StockScaffold(
      title: 'pos_title'.tr,
      maxWidth: 1200,
      actions: [
        if (_cart.isNotEmpty)
          IconButton(
            tooltip: 'pos_clear'.tr,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _saving ? null : _reset,
          ),
      ],
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
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
  }

  Widget _scanPane() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          const SizedBox(height: 8),
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
              const SizedBox(width: 8),
              if (cameraScanSupported)
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: _cameraOn ? kStockBad : kStockNavy,
                  ),
                  tooltip: _cameraOn ? 'pos_camera_off'.tr : 'stk_scan'.tr,
                  onPressed: _toggleCamera,
                  icon: Icon(
                    _cameraOn ? Icons.videocam_off : Icons.qr_code_scanner,
                  ),
                ),
              IconButton.outlined(
                tooltip: 'stk_scan_take_photo'.tr,
                onPressed: () => _scanPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
              ),
              IconButton.outlined(
                tooltip: 'stk_scan_upload'.tr,
                onPressed: () => _scanPhoto(ImageSource.gallery),
                icon: const Icon(Icons.image_outlined),
              ),
              if (!kIsWeb && _cameraOn && _scanner != null)
                IconButton.outlined(
                  tooltip: 'stk_camera_switch'.tr,
                  onPressed: () => _scanner!.switchCamera(),
                  icon: const Icon(Icons.cameraswitch_outlined),
                ),
              IconButton.outlined(
                tooltip: 'stk_products'.tr,
                onPressed: _browse,
                icon: const Icon(Icons.search_rounded),
              ),
            ],
          ),
        ],
      ),
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customer,
                    decoration: stockInput(
                      'pos_customer'.tr,
                      icon: Icons.person_outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'cash', label: Text('pos_cash'.tr)),
                  ButtonSegment(value: 'mobile', label: Text('pos_mobile'.tr)),
                  ButtonSegment(value: 'card', label: Text('pos_card'.tr)),
                ],
                selected: {_payment},
                onSelectionChanged: (s) => setState(() => _payment = s.first),
              ),
            ),
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
                    onPressed: _saving || _cart.isEmpty ? null : _complete,
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
                    label: Text('pos_complete'.tr),
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
