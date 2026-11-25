import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gal/gal.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/mobile_money_account.dart';
import 'package:tra_list/services/notification_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/pdf/pdf_saver.dart' as pdf_saver;
import 'package:tra_list/theme/app_theme.dart';
import 'stock_media.dart';
import 'stock_models.dart';
import 'scan_frame.dart';
import 'pos_list_document.dart';
import 'stock_service.dart';
import 'stock_ui.dart';
import 'bar_orders_page.dart';
import 'pos_receipt_pdf.dart';
import 'thermal_receipt_printer.dart';

class _CartLine {
  _CartLine(this.product, this.qty);
  Product product;
  double qty;
  double get amount => roundMoney(qty * product.sellPrice);
}

enum _ScanProductAction { add, next, finish, cancel }

enum _PosReceiptAction { print, save, share, done, cancel }

/// Quick sale screen: scan products, build a cart, complete the sale.
/// Completing creates the invoice and deducts stock in one transaction.
class PosPage extends StatefulWidget {
  const PosPage({super.key, this.initialProduct, this.initialProductCode});
  final Product? initialProduct;
  final String? initialProductCode;

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final _service = StockService.current();
  final _codeCtl = TextEditingController();
  final _productSearchCtl = TextEditingController();
  final _codeFocus = FocusNode();
  final _customer = TextEditingController();
  final _table = TextEditingController();
  final _cart = <_CartLine>[];
  List<Product> _products = [];
  bool _loaded = false;
  String? _loadError;
  bool _initialProductAdded = false;
  bool _initialProductLoading = false;
  bool _cameraOn = false;
  bool _saving = false;
  bool _listBusy = false;
  bool _loadingMobileMoneyAccounts = false;
  bool _mobileMoneyDialogOpening = false;
  bool _barOrderMode = false;
  StreamSubscription<List<Product>>? _productsSubscription;
  String _payment = 'cash';
  String _catalogQuery = '';
  String _productSearchQuery = '';
  String _catalogCategory = '';
  String _mobileProductCategory = '';
  int _mobileDestination = 0;
  bool _showCheckoutDetails = false;
  bool _scanConfirmationOpen = false;
  bool _scanBatchActive = false;
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
    final initialProduct = widget.initialProduct;
    if (initialProduct != null &&
        initialProduct.active &&
        _withinStock(initialProduct, 1)) {
      _cart.add(_CartLine(initialProduct, 1));
      _initialProductAdded = true;
      _mobileDestination = 3;
    } else if (widget.initialProductCode?.trim().isNotEmpty == true) {
      _initialProductLoading = true;
      _mobileDestination = 3;
    }
    _productsSubscription = _service.watchProducts().listen(
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
          'POS access state: business=${BusinessAccessService.businessUid.value}, '
          'ready=${BusinessAccessService.isReady.value}, '
          'membership=${BusinessAccessService.hasMembership.value}, '
          'legacyMembership=${BusinessAccessService.isLegacyMembership.value}, '
          'active=${BusinessAccessService.isActive.value}, '
          'barMode=${BusinessAccessService.barModeEnabled.value}, '
          'barRole=${BusinessAccessService.barRole.value}, '
          'canUseBarPos=${BusinessAccessService.canUseBarPos}, '
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
          _initialProductLoading = false;
        });
      },
    );
    final initialProductCode = widget.initialProductCode?.trim();
    if (initialProductCode != null && initialProductCode.isNotEmpty) {
      unawaited(_resolveInitialProductCode(initialProductCode));
    }
  }

  void _addInitialProduct(List<Product> products) {
    if (_initialProductAdded) return;
    if (widget.initialProduct == null) return;
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

  Future<void> _resolveInitialProductCode(String code) async {
    try {
      final product = await _service.findProductByCode(code);
      if (!mounted || _initialProductAdded) return;
      if (product == null || !product.active) {
        setState(() => _initialProductLoading = false);
        stockToast(
          'stk_error'.tr,
          fmtText('stk_scan_not_found', {'code': code}),
          error: true,
        );
        return;
      }
      _addResolvedInitialProduct(product);
    } on FirebaseException catch (error) {
      if (!mounted || _initialProductAdded) return;
      setState(() => _initialProductLoading = false);
      stockToast('stk_error'.tr, stockErrorText(error), error: true);
    }
  }

  void _addResolvedInitialProduct(Product product) {
    if (_initialProductAdded) return;
    _initialProductAdded = true;
    final added = _add(product, 1);
    setState(() => _initialProductLoading = false);
    if (added) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    }
  }

  @override
  void dispose() {
    _productsSubscription?.cancel();
    _scanner?.dispose();
    _codeCtl.dispose();
    _productSearchCtl.dispose();
    _codeFocus.dispose();
    _customer.dispose();
    _table.dispose();
    super.dispose();
  }

  double get _total => _cart.fold(0, (s, l) => s + l.amount);

  Future<void> _showMobileMoneyDialog({bool viewOnly = false}) async {
    if (_mobileMoneyDialogOpening) return;
    _mobileMoneyDialogOpening = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _loadingMobileMoneyAccounts = true);
      if (!mounted || (!viewOnly && _payment != 'mobile')) return;
      final accountsFuture = _loadMobileMoneyAccounts();
      final continueToReceipt = await showDialog<bool>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (context) => _MobileMoneyPaymentDialog(
          accountsFuture: accountsFuture,
          amount: _total,
          canComplete:
              !viewOnly &&
              _cart.isNotEmpty &&
              !_saving &&
              !_listBusy &&
              !BusinessAccessService.isBarBartender,
          viewOnly: viewOnly,
        ),
      );
      if (continueToReceipt == true && mounted) await _complete();
    } on FirebaseException catch (error) {
      if (!mounted) return;
      stockToast('stk_error'.tr, stockErrorText(error), error: true);
    } on StateError catch (error) {
      if (!mounted) return;
      stockToast('stk_error'.tr, error.toString(), error: true);
    } finally {
      _mobileMoneyDialogOpening = false;
      if (mounted) setState(() => _loadingMobileMoneyAccounts = false);
    }
  }

  Future<List<MobileMoneyAccount>> _loadMobileMoneyAccounts() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(BusinessAccessService.businessId)
        .collection('profile')
        .doc('company')
        .get();
    final accounts = MobileMoneyAccount.fromList(
      snapshot.data()?['mobileMoneyAccounts'],
    );
    if (accounts.isNotEmpty) return accounts;
    if (!BusinessAccessService.isOwner.value) return accounts;
    return ProfileService.loadLegacyMobileMoneyAccounts();
  }

  void _selectPayment(String payment) {
    setState(() => _payment = payment);
    if (payment == 'mobile') unawaited(_showMobileMoneyDialog());
  }

  Future<void> _toggleCamera() async {
    if (kIsWeb) {
      final code = await scanCode(context, allowProductSearch: true);
      if (code != null && mounted) await _onCode(code);
      return;
    }
    setState(() {
      _cameraOn = !_cameraOn;
      if (_cameraOn) {
        _scanner = MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          detectionTimeoutMs: 600,
          formats: const [BarcodeFormat.all],
        );
      } else {
        _scanner?.dispose();
        _scanner = null;
      }
    });
  }

  Future<void> _togglePosTorch() async {
    final scanner = _scanner;
    if (scanner == null) return;
    try {
      await scanner.toggleTorch();
    } on MobileScannerException catch (error) {
      if (!mounted) return;
      stockToast('stk_error'.tr, stockErrorText(error), error: true);
    }
  }

  Widget _scannerPreview({required double height}) {
    final scanner = _scanner;
    if (scanner == null) return SizedBox(height: height);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: scanner,
              placeholderBuilder: (context) => ScannerLoadingFallback(
                compact: true,
                onPhoto: () => _scanPhoto(ImageSource.camera),
                onUpload: () => _scanPhoto(ImageSource.gallery),
                onRetry: _retryPosCamera,
              ),
              onDetect: (capture) {
                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue;
                  if (value != null && value.isNotEmpty) {
                    _onCode(value);
                    return;
                  }
                }
              },
            ),
            IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: ScanFrame(
                    width: constraints.maxWidth * .62,
                    height: constraints.maxHeight * .72,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: ValueListenableBuilder<MobileScannerState>(
                valueListenable: scanner,
                builder: (context, state, _) {
                  final torchAvailable =
                      state.torchState != TorchState.unavailable;
                  final torchOn = state.torchState == TorchState.on;
                  return Material(
                    color: Colors.black.withValues(alpha: .58),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'stk_torch'.tr,
                      onPressed: torchAvailable ? _togglePosTorch : null,
                      icon: Icon(
                        torchOn
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        color: torchOn ? const Color(0xFFFFC629) : Colors.white,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
    if (code.isEmpty || _scanConfirmationOpen) return;
    final now = DateTime.now();
    // The camera sees the same label many times per second.
    if (code == _lastCode &&
        now.difference(_lastScanAt).inMilliseconds < 1500) {
      return;
    }
    _lastCode = code;
    _lastScanAt = now;
    _scanConfirmationOpen = true;
    try {
      final product = await _findProductByCode(code);
      if (!mounted) return;
      if (product == null) {
        HapticFeedback.heavyImpact();
        stockToast(
          'stk_error'.tr,
          fmtText('stk_scan_not_found', {'code': code}),
          error: true,
        );
        return;
      }

      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
      final confirmed = await _confirmScannedProduct(product);
      if (!mounted || confirmed != _ScanProductAction.add) return;
      _add(product, 1);
    } finally {
      _scanConfirmationOpen = false;
      _lastScanAt = DateTime.now();
    }
  }

  Future<Product?> _findProductByCode(String code) async {
    var product = findProductByCode(
      _products.where((item) => item.active),
      code,
    );
    product ??= _products
        .where(
          (item) =>
              item.active &&
              item.name.trim().toLowerCase() == code.toLowerCase(),
        )
        .firstOrNull;
    product ??= await _service.findProductByCode(code);
    return product?.active == true ? product : null;
  }

  Future<void> _startBatchScan() async {
    if (_scanBatchActive) return;
    setState(() => _scanBatchActive = true);
    try {
      while (mounted) {
        final code = await scanCode(context, allowProductSearch: true);
        if (!mounted || code == null) break;
        if (code.trim().isEmpty) continue;

        final product = await _findProductByCode(code.trim());
        if (!mounted) break;
        if (product == null) {
          HapticFeedback.heavyImpact();
          stockToast(
            'stk_error'.tr,
            fmtText('stk_scan_not_found', {'code': code.trim()}),
            error: true,
          );
          continue;
        }

        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
        final action = await _confirmScannedProduct(product, batch: true);
        if (!mounted || action == null || action == _ScanProductAction.cancel) {
          break;
        }
        _add(product, 1);
        if (action == _ScanProductAction.finish) {
          setState(() => _mobileDestination = 3);
          break;
        }
      }
    } catch (error) {
      if (mounted) {
        stockToast('stk_error'.tr, stockErrorText(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _scanBatchActive = false);
    }
  }

  Future<_ScanProductAction?> _confirmScannedProduct(
    Product product, {
    bool batch = false,
  }) {
    return showDialog<_ScanProductAction>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E9B70).withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Color(0xFF1E9B70),
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'pos_scan_found_title'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kStockNavy,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ProductImage(url: product.imageUrl, size: 68, radius: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (product.sku.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            product.sku,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.blueGrey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TZS ${formatMoney(product.sellPrice)} / ${unitLabel(product.unit)}',
                      style: const TextStyle(
                        color: kStockNavy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (product.tracked) ...[
                      const SizedBox(height: 5),
                      Text(
                        '${'stk_in_stock'.tr}: ${formatQty(product.availableQuantity)} ${unitLabel(product.unit)}',
                        style: TextStyle(
                          color: Colors.blueGrey.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                batch ? 'pos_scan_batch_prompt'.tr : 'pos_scan_confirm_add'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey.shade700),
              ),
              const SizedBox(height: 18),
              if (batch)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          _ScanProductAction.next,
                        ),
                        icon: const Icon(Icons.skip_next_rounded, size: 19),
                        label: Text('pos_scan_next'.tr),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kStockNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          _ScanProductAction.finish,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text('stk_ok'.tr),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          _ScanProductAction.cancel,
                        ),
                        child: Text('stk_cancel'.tr),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kStockNavy,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          _ScanProductAction.add,
                        ),
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: Text('pos_add_to_cart'.tr),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
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
    if (BusinessAccessService.isBarBartender) {
      stockToast('stk_error'.tr, 'stk_err_permission'.tr, error: true);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    var saleStage = 'kuandaa taarifa za mauzo';
    try {
      final number = _invoiceNumber();
      final now = DateTime.now();
      final date = '${now.day}/${now.month}/${now.year}';
      final receiptTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
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
      final cashierName = (user.displayName ?? '').trim().isNotEmpty
          ? user.displayName!.trim()
          : (user.email ?? 'Mhudumu');
      final data = {
        'businessId': BusinessAccessService.businessId,
        'cashierUid': user.uid,
        'cashierName': cashierName,
        'receiptTime': receiptTime,
        'client': {'name': _customer.text.trim()},
        'invoice': {
          'number': number,
          'issueDate': date,
          'dueDate': date,
          'paymentMethod': _payment,
        },
        'items': items,
        'total': _total,
      };
      final receipt = <String, dynamic>{
        ...data,
        'company': {
          'name': BusinessAccessService.businessName.value,
          'shopNickname': BusinessAccessService.shopNickname.value,
        },
        'id': _saleRef.id,
        'receiptId': _saleRef.id,
      };
      final action = await _showDone(number, _total, receipt);
      if (!mounted) return;
      if (action == null || action == _PosReceiptAction.cancel) {
        return;
      }

      saleStage = 'kuandika invoice na kutoa bidhaa stoo';
      final saleResult = await _service.finalizePosSale(
        saleId: _saleRef.id,
        saleData: {...data, 'salePayment': _payment},
        lines: [
          for (final l in _cart)
            SaleLine(productId: l.product.id!, quantity: l.qty),
        ],
      );
      saleStage = 'kutuma taarifa ya mauzo';
      unawaited(
        NotificationService.notifyOwner(
          action: 'invoice',
          summary: 'POS sale $number (TSH ${_total.toStringAsFixed(0)})',
          amount: _total,
        ),
      );
      if (!mounted) return;
      receipt['company'] = saleResult.company;
      switch (action) {
        case _PosReceiptAction.print:
          try {
            final bytes = await buildPosReceiptPdf(receipt);
            if (!mounted) return;
            final printed = await printThermalReceipt(context, bytes);
            if (printed && mounted) {
              stockToast('pos_thermal_printer'.tr, 'pos_thermal_printed'.tr);
            }
          } catch (error) {
            if (mounted) {
              stockToast('stk_error'.tr, stockErrorText(error), error: true);
            }
          }
          break;
        case _PosReceiptAction.save:
        case _PosReceiptAction.share:
          try {
            final pages = await _buildReceiptImages(receipt);
            final baseName =
                'Receipt_${number.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
            final names = [
              for (var i = 0; i < pages.length; i++)
                '$baseName${pages.length == 1 ? '' : '_${i + 1}'}.png',
            ];
            if (action == _PosReceiptAction.share && !kIsWeb) {
              await SharePlus.instance.share(
                ShareParams(
                  files: [
                    for (var i = 0; i < pages.length; i++)
                      XFile.fromData(
                        pages[i],
                        mimeType: 'image/png',
                        name: names[i],
                      ),
                  ],
                  fileNameOverrides: names,
                  title: number,
                  subject: number,
                ),
              );
            } else {
              for (var i = 0; i < pages.length; i++) {
                if (kIsWeb) {
                  await pdf_saver.downloadBytes(
                    pages[i],
                    names[i],
                    'image/png',
                  );
                } else {
                  await Gal.putImageBytes(
                    pages[i],
                    album: 'Mjasi POS',
                    name: names[i].replaceAll(RegExp(r'\.png$'), ''),
                  );
                }
              }
              if (mounted) {
                stockToast('stk_saved'.tr, 'pos_receipt_saved'.tr);
              }
            }
          } catch (error) {
            if (mounted) {
              stockToast('stk_error'.tr, stockErrorText(error), error: true);
            }
          }
          break;
        case _PosReceiptAction.done:
          stockToast('pos_sale_done'.tr, 'pos_sale_completed_help'.tr);
          break;
        case _PosReceiptAction.cancel:
          break;
      }
      if (mounted) _reset();
    } catch (e) {
      if (!mounted) return;
      debugPrint('POS sale failed during: $saleStage: $e');
      if (e is FirebaseException) {
        debugPrint('POS sale Firestore error code: ${e.code}');
      }
      stockToast(
        'stk_error'.tr,
        e is FirebaseException && e.code == 'permission-denied'
            ? 'Ruhusa imekataliwa wakati wa kurekodi mauzo. Hakikisha bartender ana Bar Mode na bidhaa zina shopNickname sahihi.'
            : stockErrorText(e),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitBarOrder() async {
    if (_saving || _listBusy || _cart.isEmpty) return;
    try {
      await BusinessAccessService.refreshBarModeSetting();
    } catch (error, stackTrace) {
      debugPrint('Could not refresh Bar Mode before order submission: $error');
      debugPrintStack(stackTrace: stackTrace);
      stockToast(
        'stk_error'.tr,
        'Imeshindikana kuthibitisha mipangilio ya Bar Mode. Hakikisha kifaa kiko mtandaoni kisha jaribu tena.',
        error: true,
      );
      return;
    }
    debugPrint(
      'Bar-order access: business=${BusinessAccessService.businessUid.value}, '
      'user=${FirebaseAuth.instance.currentUser?.uid}, '
      'ready=${BusinessAccessService.isReady.value}, '
      'membership=${BusinessAccessService.hasMembership.value}, '
      'active=${BusinessAccessService.isActive.value}, '
      'owner=${BusinessAccessService.isOwner.value}, '
      'barMode=${BusinessAccessService.barModeEnabled.value}, '
      'barRole=${BusinessAccessService.barRole.value}, '
      'bartender=${BusinessAccessService.isBarBartender}',
    );
    if (!BusinessAccessService.isBarBartender) {
      stockToast(
        'stk_error'.tr,
        BusinessAccessService.barModeEnabled.value
            ? 'Akaunti hii haijawekwa kama bartender hai kwenye biashara iliyochaguliwa.'
            : 'Bar Mode haijawashwa kwenye biashara iliyochaguliwa.',
        error: true,
      );
      return;
    }
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
      debugPrint('POS bar-order submission failed: $e');
      if (e is FirebaseException) {
        debugPrint('Bar-order Firestore error code: ${e.code}');
      } else if (e is FirebaseFunctionsException) {
        debugPrint('Bar-order function error code: ${e.code}');
      }
      stockToast(
        'stk_error'.tr,
        e is FirebaseFunctionsException && e.code == 'permission-denied'
            ? e.message ?? 'Huna ruhusa ya kutuma oda kwenye biashara hii.'
            : e is FirebaseException && e.code == 'permission-denied'
            ? 'Oda imekataliwa na ruhusa za biashara. Hakikisha umeingia kwenye biashara sahihi na umewekwa kama bartender hai.'
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
      _showCheckoutDetails = false;
      _mobileDestination = 0;
    });
  }

  Future<List<Uint8List>> _buildReceiptImages(
    Map<String, dynamic> receipt,
  ) async {
    final pdf = await buildPosReceiptPdf(receipt);
    final images = <Uint8List>[];
    await for (final page in Printing.raster(pdf, dpi: 144)) {
      images.add(await page.toPng());
    }
    if (images.isEmpty) {
      throw StateError('No receipt image was generated.');
    }
    return images;
  }

  Future<void> _openReceiptImages(
    BuildContext dialogContext,
    Map<String, dynamic> receipt,
  ) async {
    try {
      final images = await _buildReceiptImages(receipt);
      if (!mounted || !dialogContext.mounted) return;
      await showDialog<void>(
        context: dialogContext,
        builder: (viewerContext) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 560,
            height: MediaQuery.sizeOf(viewerContext).height * 0.88,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'stk_cancel'.tr,
                    onPressed: () => Navigator.pop(viewerContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    itemCount: images.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.all(12),
                      child: InteractiveViewer(
                        child: Image.memory(
                          images[index],
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ),
                  ),
                ),
                if (images.length > 1)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'pos_receipt_page_count'.trParams({
                        'count': images.length.toString(),
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        stockToast('stk_error'.tr, stockErrorText(error), error: true);
      }
    }
  }

  Future<_PosReceiptAction?> _showDone(
    String number,
    double total,
    Map<String, dynamic> receipt,
  ) {
    final pdfBytes = buildPosReceiptPdf(receipt);
    return showDialog<_PosReceiptAction>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: const Color(0xFFF3F7FB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(dialogContext).height * 0.88,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF123B70), Color(0xFF0D2748)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6CE3B0).withValues(alpha: .16),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF6CE3B0),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'pos_sale_review'.tr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$number  ·  TZS ${formatMoney(total)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFC9D8E9),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'stk_cancel'.tr,
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          _PosReceiptAction.cancel,
                        ),
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFDCE6F0)),
                    ),
                    child: FutureBuilder<Uint8List>(
                      future: pdfBytes,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(stockErrorText(snapshot.error!)),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return PdfPreview(
                          build: (_) async => snapshot.data!,
                          pdfFileName: 'Receipt_$number.pdf',
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          allowSharing: false,
                          maxPageWidth: 420,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!kIsWeb)
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC629),
                        foregroundColor: kStockNavy,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () =>
                          Navigator.pop(dialogContext, _PosReceiptAction.print),
                      icon: const Icon(Icons.print_rounded, size: 25),
                      label: Text(
                        'pos_print_thermal'.tr,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          _openReceiptImages(dialogContext, receipt),
                      icon: const Icon(Icons.image_outlined),
                      label: Text('pos_open_receipt_image'.tr),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pop(dialogContext, _PosReceiptAction.save),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text('pos_save_receipt'.tr),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pop(dialogContext, _PosReceiptAction.share),
                      icon: const Icon(Icons.share_outlined),
                      label: Text('pos_share_receipt'.tr),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                      ),
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        _PosReceiptAction.cancel,
                      ),
                      child: Text('stk_cancel'.tr),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kStockBlue,
                      ),
                      onPressed: () =>
                          Navigator.pop(dialogContext, _PosReceiptAction.done),
                      child: Text('pos_done'.tr),
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

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final wide = MediaQuery.of(context).size.width >= 900;
      final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
      final cartPane = _cartPane(showCatalogWhenEmpty: false);
      return StockScaffold(
        title: BusinessAccessService.isBarBartender
            ? 'bar_bartender_title'.tr
            : 'pos_title'.tr,
        maxWidth: 1440,
        centerTitle: !wide,
        leading: IconButton(
          tooltip: 'pos_home'.tr,
          onPressed: stockGoHome,
          icon: Icon(Icons.arrow_back_rounded, size: wide ? 23 : 21),
        ),
        actions: [
          if (!wide && !keyboardOpen)
            IconButton(
              tooltip: 'stk_scan'.tr,
              onPressed: cameraScanSupported
                  ? _toggleCamera
                  : _codeFocus.requestFocus,
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          if (BusinessAccessService.barModeEnabled.value)
            if (wide)
              IconButton(
                tooltip: 'bar_orders'.tr,
                onPressed: () => Get.to(() => const BarOrdersPage()),
                icon: const Icon(Icons.room_service_outlined),
              ),
          if (wide && !BusinessAccessService.isBarBartender)
            IconButton(
              tooltip: 'pos_list_history'.tr,
              onPressed: _showListHistory,
              icon: const Icon(Icons.history),
            ),
          if (wide && _cart.isNotEmpty)
            IconButton(
              tooltip: 'pos_clear'.tr,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _saving || _listBusy ? null : _reset,
            ),
        ],
        bottomNavigationBar: wide || keyboardOpen
            ? null
            : NavigationBar(
                height: 76,
                selectedIndex: _mobileDestination,
                onDestinationSelected: (index) {
                  if (index == 4) {
                    _showMoreMenu();
                    setState(() => _mobileDestination = 0);
                    return;
                  }
                  if (index == 2) {
                    if (!_scanBatchActive) _startBatchScan();
                    return;
                  }
                  setState(() {
                    _mobileDestination = index;
                  });
                },
                backgroundColor: Colors.white,
                indicatorColor: const Color(0xFFE5F0FF),
                destinations: [
                  NavigationDestination(
                    icon: Icon(Icons.point_of_sale_outlined),
                    selectedIcon: Icon(Icons.point_of_sale_rounded),
                    label: 'POS',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon: Icon(Icons.inventory_2_rounded),
                    label: 'Products',
                  ),
                  NavigationDestination(
                    icon: _scanNavIcon(),
                    selectedIcon: _scanNavIcon(),
                    label: 'pos_scan_batch'.tr,
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: _cart.isNotEmpty,
                      label: Text('${_cart.length}'),
                      child: Icon(Icons.shopping_cart_outlined),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: _cart.isNotEmpty,
                      label: Text('${_cart.length}'),
                      child: Icon(Icons.shopping_cart_rounded),
                    ),
                    label: 'Cart',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.more_horiz_rounded),
                    label: 'More',
                  ),
                ],
              ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_loadError!, textAlign: TextAlign.center),
                ),
              )
            : wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _catalogPane(compact: keyboardOpen)),
                  SizedBox(width: 430, child: cartPane),
                ],
              )
            : _mobileDestination == 0
            ? _mobilePosPane(compact: keyboardOpen)
            : _mobileDestination == 1
            ? _mobileProductsPane()
            : _mobileDestination == 3
            ? cartPane
            : _mobilePosPane(compact: keyboardOpen),
      );
    });
  }

  Widget _scanNavIcon() => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: const Color(0xFFFFC629),
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFFFC629).withValues(alpha: .3),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: const Icon(
      Icons.qr_code_scanner_rounded,
      color: kStockNavy,
      size: 22,
    ),
  );

  Future<void> _showMoreMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!BusinessAccessService.isBarBartender)
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text('pos_list_history'.tr),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showListHistory();
                },
              ),
            if (BusinessAccessService.barModeEnabled.value)
              ListTile(
                leading: const Icon(Icons.room_service_outlined),
                title: Text('bar_orders'.tr),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Get.to(() => const BarOrdersPage());
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('stk_scan_upload'.tr),
              onTap: () {
                Navigator.pop(sheetContext);
                _scanPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobilePosPane({bool compact = false}) {
    final previewCount = _cart.length > 5 ? 5 : _cart.length;
    final searchText = _catalogQuery.trim().toLowerCase();
    final searchResults = searchText.isEmpty
        ? <Product>[]
        : _products
              .where(
                (product) =>
                    product.active &&
                    (product.name.toLowerCase().contains(searchText) ||
                        product.sku.toLowerCase().contains(searchText) ||
                        product.barcode.toLowerCase().contains(searchText)),
              )
              .toList();

    Widget compactMessage(IconData icon, String message) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: Colors.blueGrey),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.15),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Offstage(
          offstage: compact,
          child: _PosMySalesSummary(service: _service),
        ),
        _scanPane(compact: compact),
        Padding(
          padding: EdgeInsets.fromLTRB(16, compact ? 0 : 2, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: kStockBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      searchText.isEmpty
                          ? 'pos_current_sale'.tr
                          : 'stk_products'.tr,
                      style: const TextStyle(
                        color: MjasiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      searchText.isEmpty
                          ? '${_cart.length} ${'pos_items'.tr}'
                          : '${searchResults.length} ${'pos_items'.tr}',
                      style: const TextStyle(
                        color: MjasiColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: searchText.isNotEmpty
              ? searchResults.isEmpty
                    ? compactMessage(
                        Icons.inventory_2_outlined,
                        'stk_no_products'.tr,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        itemCount: searchResults.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final product = searchResults[index];
                          return Card(
                            margin: EdgeInsets.zero,
                            color: Colors.white,
                            child: ListTile(
                              dense: true,
                              onTap: () => _add(product, 1),
                              leading: ProductImage(
                                url: product.imageUrl,
                                size: 40,
                                radius: 8,
                              ),
                              title: Text(
                                product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'TZS ${formatMoney(product.sellPrice)} / ${unitLabel(product.unit)}',
                              ),
                              trailing: IconButton.filledTonal(
                                tooltip: 'pos_add_to_cart'.tr,
                                onPressed: () => _add(product, 1),
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ),
                          );
                        },
                      )
              : _cart.isEmpty
              ? compactMessage(Icons.point_of_sale_outlined, 'pos_empty'.tr)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: previewCount,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final line = _cart[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      color: Colors.white,
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFEAF2FF),
                          foregroundColor: kStockNavy,
                          child: Text(formatQty(line.qty)),
                        ),
                        title: Text(
                          line.product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'TZS ${formatMoney(line.product.sellPrice)} / ${unitLabel(line.product.unit)}',
                        ),
                        trailing: Text(
                          'TZS ${formatMoney(line.amount)}',
                          style: const TextStyle(
                            color: kStockNavy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5E9F2))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'pos_list_total'.tr,
                      style: const TextStyle(
                        color: MjasiColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'TZS ${formatMoney(_total)}',
                      style: const TextStyle(
                        color: kStockNavy,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _cart.isEmpty
                    ? null
                    : () => setState(() => _mobileDestination = 3),
                icon: const Icon(Icons.shopping_cart_checkout_rounded),
                label: Text('pos_review_cart'.tr),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mobileProductsPane() {
    final categories =
        _products
            .where(
              (product) => product.active && product.category.trim().isNotEmpty,
            )
            .map((product) => product.category.trim())
            .toSet()
            .toList()
          ..sort();
    final query = _productSearchQuery.trim().toLowerCase();
    final products = _products.where((product) {
      if (!product.active) return false;
      if (_mobileProductCategory == '__others__') {
        if (product.category.trim().isNotEmpty &&
            product.category.trim().toLowerCase() != 'others') {
          return false;
        }
      } else if (_mobileProductCategory.isNotEmpty &&
          product.category != _mobileProductCategory) {
        return false;
      }
      return query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.sku.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);
    }).toList();
    IconData categoryIcon(String category) {
      final value = category.toLowerCase();
      if (value.contains('drink') ||
          value.contains('bever') ||
          value.contains('kinyw')) {
        return Icons.local_drink_outlined;
      }
      if (value.contains('snack') || value.contains('vitafun')) {
        return Icons.cookie_outlined;
      }
      if (value.contains('grocer') || value.contains('grocery')) {
        return Icons.shopping_basket_outlined;
      }
      return Icons.category_outlined;
    }

    Widget categoryItem(String label, IconData icon, String category) {
      final selected = _mobileProductCategory == category;
      return InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => setState(() => _mobileProductCategory = category),
        child: SizedBox(
          width: 58,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? kStockBlue : Colors.white,
                  border: Border.all(
                    color: selected ? kStockBlue : const Color(0xFFE1E8F0),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: selected ? Colors.white : kStockNavy,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? kStockBlue : const Color(0xFF65758B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            controller: _productSearchCtl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'pos_search_products'.tr,
              prefixIcon: IconButton(
                tooltip: 'pos_search_products'.tr,
                onPressed: _submitProductSearch,
                icon: const Icon(Icons.search_rounded, size: 20),
              ),
              suffixIcon: _productSearchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'pos_clear_search'.tr,
                      onPressed: () {
                        _productSearchCtl.clear();
                        setState(() => _productSearchQuery = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFDDE5EF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFDDE5EF)),
              ),
            ),
            onChanged: (value) => setState(() => _productSearchQuery = value),
            onSubmitted: (_) => _submitProductSearch(),
          ),
        ),
        SizedBox(
          height: 74,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            scrollDirection: Axis.horizontal,
            children: [
              categoryItem('All', Icons.apps_rounded, ''),
              for (final category in categories)
                categoryItem(category, categoryIcon(category), category),
              categoryItem('Others', Icons.more_horiz_rounded, '__others__'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'stk_products'.tr,
                  style: const TextStyle(
                    color: MjasiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '${products.length} ${'pos_items'.tr}',
                style: const TextStyle(
                  color: MjasiColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? StockMessage(
                  icon: Icons.inventory_2_outlined,
                  text: 'stk_no_products'.tr,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 5),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _add(product, 1),
                        child: Container(
                          height: 82,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE3EAF2)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              ProductImage(
                                url: product.imageUrl,
                                size: 48,
                                radius: 9,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: MjasiColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'TZS ${formatMoney(product.sellPrice)} / ${unitLabel(product.unit)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: MjasiColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${formatQty(product.quantity)} ${unitLabel(product.unit)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: MjasiColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                        StockStateChip(product: product),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: kStockBlue,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(30, 30),
                                  maximumSize: const Size(30, 30),
                                ),
                                onPressed: () => _add(product, 1),
                                icon: const Icon(Icons.add_rounded, size: 19),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () => setState(() => _mobileDestination = 3),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFDCE5EF)),
                borderRadius: BorderRadius.circular(13),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A123B70),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    color: kStockBlue,
                    size: 21,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Cart (${_cart.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MjasiColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    'TZS ${formatMoney(_total)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: kStockNavy,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Icon(Icons.chevron_right_rounded, color: kStockBlue),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _submitProductSearch() {
    setState(() => _productSearchQuery = _productSearchCtl.text.trim());
    FocusScope.of(context).unfocus();
  }

  Widget _scanPane({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 16,
        compact ? 6 : 14,
        compact ? 10 : 16,
        compact ? 4 : 8,
      ),
      child: StockCard(
        padding: EdgeInsets.all(compact ? 8 : 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.point_of_sale_rounded,
                        color: Color(0xFF123B70),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'stk_scan'.tr,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF102D52),
                            ),
                          ),
                          Text(
                            'pos_code_hint'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!BusinessAccessService.isBarBartender)
                      IconButton(
                        tooltip: 'pos_list_history'.tr,
                        onPressed: _showListHistory,
                        icon: const Icon(Icons.history_rounded),
                      ),
                  ],
                ),
              ),
            if (!compact && !kIsWeb && _cameraOn && _scanner != null)
              _scannerPreview(height: 164),
            if (!compact && BusinessAccessService.isBarBartender) ...[
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtl,
                    focusNode: _codeFocus,
                    autofocus: !cameraScanSupported,
                    textInputAction: TextInputAction.search,
                    decoration:
                        stockInput(
                          'pos_code_hint'.tr,
                          icon: Icons.search_rounded,
                        ).copyWith(
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: 'stk_products'.tr,
                            onPressed: _browse,
                            icon: const Icon(Icons.inventory_2_outlined),
                          ),
                        ),
                    onSubmitted: (value) {
                      final query = value.trim().toLowerCase();
                      final exactCode = _products.any(
                        (product) =>
                            product.active &&
                            (product.sku.trim().toLowerCase() == query ||
                                product.barcode.trim().toLowerCase() == query),
                      );
                      final hasMatches = _products.any(
                        (product) =>
                            product.active &&
                            (product.name.toLowerCase().contains(query) ||
                                product.sku.toLowerCase().contains(query) ||
                                product.barcode.toLowerCase().contains(query)),
                      );
                      if (exactCode || !hasMatches) {
                        _onCode(value);
                        _codeCtl.clear();
                        setState(() => _catalogQuery = '');
                        _codeFocus.requestFocus();
                      } else {
                        FocusScope.of(context).unfocus();
                      }
                    },
                    onChanged: (value) => setState(() => _catalogQuery = value),
                  ),
                ),
                if (!compact && cameraScanSupported)
                  IconButton.filledTonal(
                    tooltip: 'stk_scan'.tr,
                    onPressed: _toggleCamera,
                    icon: Icon(
                      _cameraOn
                          ? Icons.stop_circle_outlined
                          : Icons.qr_code_scanner_rounded,
                    ),
                  ),
                if (!compact)
                  IconButton(
                    tooltip: 'stk_scan_upload'.tr,
                    onPressed: () => _scanPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.image_outlined),
                  ),
              ],
            ),
            if (!compact && !cameraScanSupported) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _codeFocus.requestFocus,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text('stk_scan'.tr),
              ),
            ],
            if (!compact && !kIsWeb && _cameraOn && _scanner != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _scanner!.switchCamera(),
                  icon: const Icon(Icons.cameraswitch_outlined, size: 17),
                  label: Text('stk_camera_switch'.tr),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _catalogPane({bool compact = false}) {
    final categories =
        _products
            .where(
              (product) =>
                  product.active &&
                  product.category.trim().isNotEmpty &&
                  product.category.trim().toLowerCase() != 'others',
            )
            .map((product) => product.category.trim())
            .toSet()
            .toList()
          ..sort();
    final query = _catalogQuery.trim().toLowerCase();
    final products = _products.where((product) {
      if (!product.active) return false;
      if (_catalogCategory.isNotEmpty && product.category != _catalogCategory) {
        return false;
      }
      return query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.sku.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Offstage(
          offstage: compact,
          child: _PosMySalesSummary(service: _service),
        ),
        _scanPane(compact: compact),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            children: [
              ChoiceChip(
                label: Text('transactions_all_categories'.tr),
                selected: _catalogCategory.isEmpty,
                onSelected: (_) => setState(() => _catalogCategory = ''),
                selectedColor: const Color(0xFFDCEBFF),
                side: const BorderSide(color: Color(0xFFD4DFEE)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.only(left: 7),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: _catalogCategory == category,
                    onSelected: (_) =>
                        setState(() => _catalogCategory = category),
                    selectedColor: const Color(0xFFDCEBFF),
                    side: const BorderSide(color: Color(0xFFD4DFEE)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
          child: StockSectionHeading(
            title: 'stk_products'.tr,
            subtitle: '${products.length} ${'pos_items'.tr}',
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? StockMessage(
                  icon: Icons.inventory_2_outlined,
                  text: 'stk_no_products'.tr,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.maxWidth / 185)
                        .floor()
                        .clamp(2, 4)
                        .toInt();
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.96,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _add(product, 1),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0B143454),
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: MjasiColors.border),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: ProductImage(
                                      url: product.imageUrl,
                                      size: 84,
                                      radius: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: MjasiColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'TZS ${formatMoney(product.sellPrice)}',
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: MjasiColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: StockStateChip(product: product),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _cartPane({bool showCatalogWhenEmpty = true}) {
    final availableProducts = _products
        .where((product) => product.active)
        .toList();
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD5E4FA)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7E7FF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    color: Color(0xFF123B70),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '${'pos_cart'.tr} (${_cart.length})',
                  style: const TextStyle(
                    color: MjasiColors.primaryNavy,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (_cart.isNotEmpty)
                  TextButton(
                    onPressed: _saving || _listBusy ? null : _reset,
                    child: Text('pos_clear'.tr),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _cart.isEmpty
                ? _initialProductLoading
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              Text('stk_loading_scanned_product'.tr),
                            ],
                          ),
                        )
                      : (!showCatalogWhenEmpty || availableProducts.isEmpty)
                      ? StockMessage(
                          icon: Icons.shopping_cart_outlined,
                          text: 'pos_empty'.tr,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          itemCount: availableProducts.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                                child: Text(
                                  'stk_products'.tr,
                                  style: const TextStyle(
                                    color: kStockNavy,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              );
                            }
                            final product = availableProducts[index - 1];
                            return StockCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  ProductImage(
                                    url: product.imageUrl,
                                    size: 44,
                                    radius: 10,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          'TZS ${formatMoney(product.sellPrice)} / ${unitLabel(product.unit)}',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton.filledTonal(
                                    onPressed: () => _add(product, 1),
                                    icon: const Icon(Icons.add),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _lineTile(_cart[i]),
                  ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight.isFinite
                  ? constraints.maxHeight * (keyboardOpen ? .68 : .58)
                  : MediaQuery.sizeOf(context).height *
                        (keyboardOpen ? .68 : .42),
            ),
            child: SingleChildScrollView(child: _checkoutBar()),
          ),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        child: Row(
          children: [
            ProductImage(url: p.imageUrl, size: 54, radius: 13),
            const SizedBox(width: 13),
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
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              decoration: BoxDecoration(
                color: kStockBg,
                border: Border.all(color: MjasiColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 34,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: 'Decrease quantity'.tr,
                    icon: const Icon(Icons.remove_rounded, size: 18),
                    onPressed: () => _setQty(l, l.qty - 1),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _editQty(l),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 7,
                      ),
                      child: Text(
                        formatQty(l.qty),
                        style: const TextStyle(
                          color: kStockNavy,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 34,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: 'Increase quantity'.tr,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    onPressed: () => _add(p, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkoutBar() {
    final barModeEnabled = BusinessAccessService.barModeEnabled.value;
    final isBarBartender = BusinessAccessService.isBarBartender;
    final isBarWaiter = BusinessAccessService.isBarWaiter;
    final isOrderMode = barModeEnabled && isBarBartender;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E9F2))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (barModeEnabled && !isBarBartender && !isBarWaiter)
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
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(
                  () => _showCheckoutDetails = !_showCheckoutDetails,
                ),
                icon: Icon(
                  _showCheckoutDetails
                      ? Icons.expand_less_rounded
                      : Icons.person_add_alt_1_outlined,
                  size: 18,
                ),
                label: Text(
                  _customer.text.trim().isEmpty
                      ? 'pos_customer'.tr
                      : _customer.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (_showCheckoutDetails)
              TextField(
                controller: _customer,
                maxLength: 120,
                decoration: stockInput(
                  'pos_customer'.tr,
                  icon: Icons.person_outline,
                ).copyWith(isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            if (isOrderMode)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _loadingMobileMoneyAccounts
                      ? null
                      : () => _showMobileMoneyDialog(viewOnly: true),
                  icon: _loadingMobileMoneyAccounts
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: Text('pos_mobile_pay_number'.tr),
                ),
              ),
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
                  onSelectionChanged: (s) => _selectPayment(s.first),
                ),
              ),
              if (_payment == 'mobile')
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _loadingMobileMoneyAccounts
                        ? null
                        : _showMobileMoneyDialog,
                    icon: _loadingMobileMoneyAccounts
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.qr_code_2_rounded, size: 18),
                    label: Text('pos_mobile_pay_number'.tr),
                  ),
                ),
              if (!isBarBartender)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _cart.isEmpty || _listBusy
                        ? null
                        : _generateList,
                    icon: _listBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(
                      _listBusy ? 'pos_list_saving'.tr : 'pos_generate_list'.tr,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final total = Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F6FC),
                    border: Border.all(color: const Color(0xFFE0E8F1)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        color: kStockBlue,
                        size: 19,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_cart.length} ${'pos_items'.tr}',
                              style: const TextStyle(
                                color: MjasiColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'TZS ${formatMoney(_total)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: kStockNavy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
                final canComplete = !_saving && !_listBusy && _cart.isNotEmpty;
                final completeButton = SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kStockOk),
                    onPressed: !canComplete
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
                );
                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      total,
                      const SizedBox(height: 7),
                      Row(children: [Expanded(child: completeButton)]),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: total),
                    completeButton,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMoneyPaymentDialog extends StatefulWidget {
  const _MobileMoneyPaymentDialog({
    required this.accountsFuture,
    required this.amount,
    required this.canComplete,
    required this.viewOnly,
  });

  final Future<List<MobileMoneyAccount>> accountsFuture;
  final double amount;
  final bool canComplete;
  final bool viewOnly;

  @override
  State<_MobileMoneyPaymentDialog> createState() =>
      _MobileMoneyPaymentDialogState();
}

class _MobileMoneyPaymentDialogState extends State<_MobileMoneyPaymentDialog> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final availableHeight =
        size.height - MediaQuery.viewInsetsOf(context).bottom;
    final dialogHeight = (availableHeight - 32).clamp(160.0, 620.0).toDouble();
    final qrSize = (availableHeight * .15).clamp(72.0, 120.0).toDouble();
    const radius = BorderRadius.all(Radius.circular(26));

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      backgroundColor: Colors.transparent,
      child: Material(
        color: const Color(0xFF101A2B),
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0xFF25D6C3).withValues(alpha: .24),
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: Colors.white24),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 440,
          height: dialogHeight,
          child: FutureBuilder<List<MobileMoneyAccount>>(
            future: widget.accountsFuture,
            builder: (context, snapshot) {
              final accounts = snapshot.data ?? const <MobileMoneyAccount>[];
              final selectedIndex = _selectedIndex < accounts.length
                  ? _selectedIndex
                  : 0;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 12, 0),
                    child: _header(),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: snapshot.hasError
                          ? _status(
                              Text(
                                stockErrorText(snapshot.error!),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            )
                          : snapshot.connectionState != ConnectionState.done
                          ? _status(
                              const CircularProgressIndicator(
                                color: Color(0xFF65E6D7),
                              ),
                            )
                          : accounts.isEmpty
                          ? _status(
                              Text(
                                'pos_mobile_no_accounts'.tr,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            )
                          : _paymentContent(accounts, selectedIndex, qrSize),
                    ),
                  ),
                  if (!widget.viewOnly)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                      child: SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF55E2D3),
                            foregroundColor: const Color(0xFF102033),
                            disabledBackgroundColor: Colors.white12,
                            disabledForegroundColor: Colors.white38,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed:
                              widget.canComplete &&
                                  snapshot.connectionState ==
                                      ConnectionState.done &&
                                  !snapshot.hasError &&
                                  accounts.isNotEmpty
                              ? () => Navigator.pop(context, true)
                              : null,
                          icon: const Icon(Icons.verified_rounded),
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'pos_mobile_confirm_received'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'pos_mobile_continue_to_receipt'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          iconAlignment: IconAlignment.start,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF45DDCF).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF45DDCF).withValues(alpha: .35),
            ),
          ),
          child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF65E6D7)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'pos_mobile_dialog_title'.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          tooltip: 'stk_close'.tr,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _status(Widget child) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 116),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );
  }

  Color _contrastColor(Color background) => background.computeLuminance() > .2
      ? const Color(0xFF102033)
      : Colors.white;

  Widget _networkChoiceChip(
    MobileMoneyAccount account,
    int index,
    int selectedIndex,
  ) {
    final providerColor = Color(account.networkColorValue);
    final isSelected = selectedIndex == index;
    final foregroundColor = isSelected
        ? _contrastColor(providerColor)
        : Colors.white70;

    return ChoiceChip(
      label: Text(
        account.network,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      selected: isSelected,
      showCheckmark: false,
      avatar: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: isSelected ? foregroundColor : providerColor,
          shape: BoxShape.circle,
        ),
      ),
      backgroundColor: const Color(0xFF1D2B3E),
      selectedColor: providerColor,
      labelStyle: TextStyle(
        color: foregroundColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: providerColor.withValues(alpha: isSelected ? 1 : .55),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (selected) {
        if (selected) setState(() => _selectedIndex = index);
      },
    );
  }

  Widget _paymentContent(
    List<MobileMoneyAccount> accounts,
    int selectedIndex,
    double qrSize,
  ) {
    final account = accounts[selectedIndex];
    final providerColor = Color(account.networkColorValue);
    final foregroundColor = _contrastColor(providerColor);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = (screenWidth - 64).clamp(0.0, 408.0).toDouble();
    final fittedQrSize = qrSize.clamp(0.0, contentWidth * .32).toDouble();

    final networkSelector = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'pos_mobile_choose_network'.tr,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var index = 0; index < accounts.length; index++)
              _networkChoiceChip(accounts[index], index, selectedIndex),
          ],
        ),
      ],
    );

    final amountCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: providerColor.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: providerColor.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: providerColor.withValues(alpha: .22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.payments_outlined,
              color: Color(0xFFFFD166),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'pos_mobile_amount_due'.tr,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'TZS ${formatMoney(widget.amount)}',
                    style: const TextStyle(
                      color: Color(0xFFFFD166),
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final qrCard = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: providerColor.withValues(alpha: .3), blurRadius: 16),
        ],
      ),
      child: QrImageView(
        data: account.qrData,
        size: fittedQrSize,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
      ),
    );

    final payeeDetails = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'pos_mobile_payee_name'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: foregroundColor.withValues(alpha: .8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          account.payeeName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: foregroundColor,
            fontSize: 24,
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'pos_mobile_pay_number'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: foregroundColor.withValues(alpha: .78),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  account.payNumber,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 24,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .4,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'pos_mobile_copy_number'.tr,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: account.payNumber));
                if (!mounted) return;
                stockToast(
                  'pos_mobile_pay_number'.tr,
                  'pos_mobile_number_copied'.tr,
                );
              },
              icon: Icon(Icons.copy_rounded, color: foregroundColor, size: 19),
            ),
          ],
        ),
      ],
    );

    final paymentDetails = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: providerColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: foregroundColor.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          qrCard,
          const SizedBox(width: 10),
          Expanded(child: payeeDetails),
        ],
      ),
    );

    final verificationHint = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF25334A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF8BF3E6),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'pos_mobile_payment_hint'.tr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        networkSelector,
        const SizedBox(height: 10),
        amountCard,
        const SizedBox(height: 10),
        paymentDetails,
        const SizedBox(height: 10),
        verificationHint,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Compact inline sales summary for the POS tab (current user only).
// ---------------------------------------------------------------------------

enum _PosSalesSort { mostSold, leastSold, name }

enum _CustomSalesPeriod { day, range }

class _PosMySalesSummary extends StatefulWidget {
  const _PosMySalesSummary({required this.service});
  final StockService service;

  @override
  State<_PosMySalesSummary> createState() => _PosMySalesSummaryState();
}

class _PosMySalesSummaryState extends State<_PosMySalesSummary> {
  // 0 = Today, 7 = last 7 days, 30 = last 30 days
  int? _days = 0;
  _PosSalesSort _sort = _PosSalesSort.mostSold;
  DateTime? _customStart;
  DateTime? _customEnd;
  late Stream<List<ProductSaleRecord>> _sales;

  @override
  void initState() {
    super.initState();
    _resetStream();
  }

  DateTime get _since {
    final now = DateTime.now();
    final days = _days;
    if (days == null) return _customStart!;
    if (days == 0) {
      return DateTime(now.year, now.month, now.day);
    }
    return now.subtract(Duration(days: days));
  }

  DateTime? get _untilExclusive {
    final end = _days == null ? _customEnd : null;
    if (end == null) return null;
    return DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
  }

  String get _periodKey {
    if (_days != null) return 'days-$_days';
    return 'custom-${_customStart?.millisecondsSinceEpoch}-'
        '${_customEnd?.millisecondsSinceEpoch}';
  }

  String get _customPeriodLabel {
    final start = _customStart;
    final end = _customEnd;
    if (_days != null || start == null || end == null) {
      return 'stk_custom_period'.tr;
    }
    if (start.isAtSameMomentAs(end)) return _formatDate(start);
    return '${_formatDate(start)} - ${_formatDate(end)}';
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  void _resetStream() {
    _sales = widget.service.watchMyProductSalesSince(
      _since,
      untilExclusive: _untilExclusive,
    );
  }

  String get _sortLabel => switch (_sort) {
    _PosSalesSort.mostSold => 'stk_sort_most_sold'.tr,
    _PosSalesSort.leastSold => 'stk_sort_least_sold'.tr,
    _PosSalesSort.name => 'stk_sort_name'.tr,
  };

  void _selectDays(int days) {
    if (_days == days) return;
    setState(() {
      _days = days;
      _customStart = null;
      _customEnd = null;
      _resetStream();
    });
  }

  Future<void> _selectCustomPeriod(_CustomSalesPeriod period) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (period == _CustomSalesPeriod.day) {
      final selected = await showDatePicker(
        context: context,
        initialDate: _customStart ?? todayDate,
        firstDate: DateTime(2000),
        lastDate: todayDate,
        helpText: 'stk_pick_one_day'.tr,
      );
      if (!mounted || selected == null) return;
      final day = DateTime(selected.year, selected.month, selected.day);
      setState(() {
        _days = null;
        _customStart = day;
        _customEnd = day;
        _resetStream();
      });
      return;
    }

    final initialStart =
        _customStart ?? todayDate.subtract(const Duration(days: 6));
    final initialEnd = _customEnd ?? todayDate;
    final selected = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      firstDate: DateTime(2000),
      lastDate: todayDate,
      helpText: 'stk_pick_date_range'.tr,
    );
    if (!mounted || selected == null) return;
    setState(() {
      _days = null;
      _customStart = DateTime(
        selected.start.year,
        selected.start.month,
        selected.start.day,
      );
      _customEnd = DateTime(
        selected.end.year,
        selected.end.month,
        selected.end.day,
      );
      _resetStream();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProductSaleRecord>>(
      key: ValueKey(_periodKey),
      stream: _sales,
      builder: (context, snap) {
        final records = snap.data ?? [];
        final totalRevenue = records.fold<double>(0, (s, r) => s + r.amount);
        final txnCount = records.map((r) => r.invoiceId).toSet().length;

        // Aggregate top products
        final totals = <String, _MySaleTotal>{};
        for (final r in records) {
          final t = totals.putIfAbsent(
            r.productId.isNotEmpty ? r.productId : r.productName,
            () => _MySaleTotal(r.productName),
          );
          t.qty += r.quantity;
          t.revenue += r.amount;
        }
        final topProducts = totals.values.toList()
          ..sort((a, b) {
            switch (_sort) {
              case _PosSalesSort.mostSold:
                return b.qty.compareTo(a.qty);
              case _PosSalesSort.leastSold:
                return a.qty.compareTo(b.qty);
              case _PosSalesSort.name:
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            }
          });

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Material(
            color: kStockNavy,
            elevation: 3,
            shadowColor: const Color(0x14123B70),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () =>
                  Get.to(() => _PosMySalesHistoryPage(service: widget.service)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.trending_up_rounded,
                          color: Color(0xFF78D8B5),
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'stk_sold_summary'.tr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        PopupMenuButton<_PosSalesSort>(
                          tooltip: 'stk_sort_by'.tr,
                          onSelected: (sort) => setState(() => _sort = sort),
                          itemBuilder: (context) => [
                            for (final sort in _PosSalesSort.values)
                              PopupMenuItem(
                                value: sort,
                                child: Row(
                                  children: [
                                    Icon(
                                      sort == _sort
                                          ? Icons.check_rounded
                                          : Icons.sort_rounded,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(switch (sort) {
                                      _PosSalesSort.mostSold =>
                                        'stk_sort_most_sold'.tr,
                                      _PosSalesSort.leastSold =>
                                        'stk_sort_least_sold'.tr,
                                      _PosSalesSort.name => 'stk_sort_name'.tr,
                                    }),
                                  ],
                                ),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.sort_rounded,
                                  color: Colors.white,
                                  size: 17,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _sortLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip('stk_sales_today'.tr, 0),
                        _chip('stk_last_days'.trParams({'days': '7'}), 7),
                        _chip('stk_last_days'.trParams({'days': '30'}), 30),
                        _customChip(),
                      ],
                    ),
                    if (snap.hasError) ...[
                      const SizedBox(height: 8),
                      Text(
                        stockErrorText(snap.error!),
                        style: const TextStyle(
                          color: Color(0xFFFFD1D1),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _stat(
                            'stk_total'.tr,
                            snap.hasData
                                ? 'TZS ${formatMoney(totalRevenue)}'
                                : '…',
                            large: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _stat(
                              'pos_list_history'.tr,
                              snap.hasData ? '$txnCount' : '…',
                              alignEnd: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (topProducts.isNotEmpty) ...[
                      const Divider(
                        color: Colors.white24,
                        height: 14,
                        thickness: .5,
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final p in topProducts.take(3))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${p.name}  TZS ${formatMoney(p.revenue)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'stk_sales_history'.tr,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF78D8B5),
                          size: 16,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, int days) {
    final selected = _days == days;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      backgroundColor: const Color(0xFF294766),
      selectedColor: const Color(0xFF78D8B5),
      side: BorderSide(
        color: selected ? const Color(0xFF78D8B5) : const Color(0xFF536F8C),
      ),
      labelStyle: TextStyle(
        color: selected ? kStockNavy : Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
      onSelected: (_) => _selectDays(days),
    );
  }

  Widget _customChip() {
    final selected = _days == null;
    return PopupMenuButton<_CustomSalesPeriod>(
      tooltip: 'stk_custom_period'.tr,
      onSelected: (period) => unawaited(_selectCustomPeriod(period)),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _CustomSalesPeriod.day,
          child: Text('stk_pick_one_day'.tr),
        ),
        PopupMenuItem(
          value: _CustomSalesPeriod.range,
          child: Text('stk_pick_date_range'.tr),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF78D8B5) : const Color(0xFF294766),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF78D8B5) : const Color(0xFF536F8C),
          ),
        ),
        child: Text(
          _customPeriodLabel,
          style: TextStyle(
            color: selected ? kStockNavy : Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _stat(
    String label,
    String value, {
    bool large = false,
    bool alignEnd = false,
  }) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: large ? 18 : 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _MySaleTotal {
  _MySaleTotal(this.name);
  final String name;
  double qty = 0;
  double revenue = 0;
}

enum _MySalesHistorySort { newest, oldest, highest, lowest }

class _PosMySalesHistoryPage extends StatefulWidget {
  const _PosMySalesHistoryPage({required this.service});

  final StockService service;

  @override
  State<_PosMySalesHistoryPage> createState() => _PosMySalesHistoryPageState();
}

class _PosMySalesHistoryPageState extends State<_PosMySalesHistoryPage> {
  late final Stream<List<ProductSaleRecord>> _sales;
  _MySalesHistorySort _sort = _MySalesHistorySort.newest;

  @override
  void initState() {
    super.initState();
    _sales = widget.service.watchMyProductSalesHistory();
  }

  String _sortLabel(_MySalesHistorySort sort) => switch (sort) {
    _MySalesHistorySort.newest => 'pos_my_sales_sort_newest'.tr,
    _MySalesHistorySort.oldest => 'pos_my_sales_sort_oldest'.tr,
    _MySalesHistorySort.highest => 'pos_my_sales_sort_highest'.tr,
    _MySalesHistorySort.lowest => 'pos_my_sales_sort_lowest'.tr,
  };

  Future<void> _openSortOptions() async {
    final selectedSort = await showModalBottomSheet<_MySalesHistorySort>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8E0EA),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'stk_sort_by'.tr,
                  style: const TextStyle(
                    color: kStockNavy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final sort in _MySalesHistorySort.values)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: sort == _sort
                      ? const Color(0xFFEAF7F1)
                      : Colors.transparent,
                  leading: Icon(
                    sort == _sort ? Icons.check_circle_rounded : Icons.sort,
                    color: sort == _sort ? kStockOk : Colors.blueGrey,
                  ),
                  title: Text(
                    _sortLabel(sort),
                    style: TextStyle(
                      color: kStockNavy,
                      fontWeight: sort == _sort
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, sort),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selectedSort == null) return;
    setState(() => _sort = selectedSort);
  }

  String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kStockBg,
      appBar: AppBar(
        title: Text('stk_sales_history'.tr),
        backgroundColor: kStockNavy,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<ProductSaleRecord>>(
        stream: _sales,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  stockErrorText(snapshot.error!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kStockBad),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = snapshot.data!;
          final byInvoice = <String, _MySalesHistoryInvoice>{};
          for (final record in records) {
            final invoice = byInvoice.putIfAbsent(
              record.invoiceId,
              () => _MySalesHistoryInvoice(record),
            );
            invoice.items.add(record);
          }
          final invoices = byInvoice.values.toList()
            ..sort((a, b) {
              final aDate =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              switch (_sort) {
                case _MySalesHistorySort.newest:
                  return bDate.compareTo(aDate);
                case _MySalesHistorySort.oldest:
                  return aDate.compareTo(bDate);
                case _MySalesHistorySort.highest:
                  return b.total.compareTo(a.total);
                case _MySalesHistorySort.lowest:
                  return a.total.compareTo(b.total);
              }
            });
          final totalRevenue = records.fold<double>(
            0,
            (total, record) => total + record.amount,
          );
          final averageSale = invoices.isEmpty
              ? 0.0
              : totalRevenue / invoices.length;
          var bestSale = 0.0;
          for (final invoice in invoices) {
            if (invoice.total > bestSale) bestSale = invoice.total;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _summaryCard(totalRevenue, invoices.length),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      'pos_my_sales_average_sale'.tr,
                      averageSale,
                      Icons.show_chart_rounded,
                      const Color(0xFF3878C7),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _metricCard(
                      'pos_my_sales_best_sale'.tr,
                      bestSale,
                      Icons.stars_rounded,
                      const Color(0xFFDA9A22),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _encouragementCard(),
              const SizedBox(height: 20),
              Text(
                'pos_my_sales_activity'.tr,
                style: const TextStyle(
                  color: kStockNavy,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (invoices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'pos_my_sales_empty'.tr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.blueGrey),
                  ),
                )
              else
                for (final invoice in invoices) _invoiceCard(invoice),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCard(double totalRevenue, int transactionCount) {
    final borderRadius = BorderRadius.circular(22);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10294A), Color(0xFF1766A7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x24123B70),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned(
              top: -50,
              right: -28,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .055),
                ),
              ),
            ),
            Positioned(
              bottom: -76,
              right: 56,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .04),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Color(0xFF9FE9D3),
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'pos_my_sales_all_time'.tr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.stars_rounded,
                        color: Color(0xFF9FE9D3),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'stk_total_sales'.tr,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'TZS ${formatMoney(totalRevenue)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(height: 1, color: Colors.white24),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.receipt_long_rounded,
                        color: Color(0xFF9FE9D3),
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'stk_sales_total_count'.trParams({
                            'count': '$transactionCount',
                          }),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'stk_sort_by'.tr,
                        child: OutlinedButton.icon(
                          onPressed: _openSortOptions,
                          icon: const Icon(Icons.sort_rounded, size: 16),
                          label: Text('pos_my_sales_sort_button'.tr),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(String title, double amount, IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6ECF3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C123B70),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: accent, size: 19),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.blueGrey,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'TZS ${formatMoney(amount)}',
              style: const TextStyle(
                color: kStockNavy,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _encouragementCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4EEE2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.celebration_rounded,
            color: Color(0xFF25805F),
            size: 23,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'pos_my_sales_encouragement'.tr,
              style: const TextStyle(
                color: Color(0xFF245A49),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _invoiceCard(_MySalesHistoryInvoice invoice) {
    final customerName = invoice.customerName.trim();
    final date = invoice.createdAt;
    final productNames = invoice.items
        .map((item) => item.productName)
        .toSet()
        .join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6ECF3)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7F1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFF25805F),
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.invoiceNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kStockNavy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (date != null)
                  Text(
                    'stk_sale_placed_at'.trParams({
                      'date': _formatDateTime(date),
                    }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 11,
                    ),
                  ),
                if (customerName.isNotEmpty)
                  Text(
                    'stk_sale_customer'.trParams({'name': customerName}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 11,
                    ),
                  ),
                Text(
                  '${invoice.items.length} ${'pos_items'.tr} · $productNames',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                'TZS ${formatMoney(invoice.total)}',
                style: const TextStyle(
                  color: kStockOk,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MySalesHistoryInvoice {
  _MySalesHistoryInvoice(ProductSaleRecord first)
    : invoiceNumber = first.invoiceNumber,
      customerName = first.customerName,
      createdAt = first.createdAt;

  final String invoiceNumber;
  final String customerName;
  final DateTime? createdAt;
  final List<ProductSaleRecord> items = [];

  double get total =>
      items.fold<double>(0, (total, item) => total + item.amount);
}
