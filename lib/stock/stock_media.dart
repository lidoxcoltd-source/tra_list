import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing_lib/common.dart';
import 'package:zxing_lib/zxing.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'stock_models.dart';
import 'stock_service.dart';
import 'stock_ui.dart';
import 'live_scanner_stub.dart'
    if (dart.library.js_interop) 'live_scanner_web.dart'
    as live_scanner;

const _maxImageBytes = 5 * 1024 * 1024;

class ScannerLoadingFallback extends StatefulWidget {
  const ScannerLoadingFallback({
    super.key,
    required this.onPhoto,
    required this.onUpload,
    required this.onRetry,
    this.compact = false,
  });

  final VoidCallback onPhoto;
  final VoidCallback onUpload;
  final VoidCallback onRetry;
  final bool compact;

  @override
  State<ScannerLoadingFallback> createState() => _ScannerLoadingFallbackState();
}

class _ScannerLoadingFallbackState extends State<ScannerLoadingFallback> {
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 12), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_slow) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final actions = [
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text('stk_scan_take_photo'.tr),
        onPressed: widget.onPhoto,
      ),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
        icon: const Icon(Icons.image_outlined),
        label: Text('stk_scan_upload'.tr),
        onPressed: widget.onUpload,
      ),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        icon: const Icon(Icons.refresh),
        label: Text('stk_cam_retry'.tr),
        onPressed: widget.onRetry,
      ),
    ];
    return Container(
      color: Colors.black87,
      padding: EdgeInsets.all(widget.compact ? 8 : 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'stk_cam_slow'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          if (widget.compact)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: actions,
            ),
        ],
      ),
    );
  }
}

bool get cameraScanSupported =>
    kIsWeb ||
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

bool get _cameraPhotoSupported =>
    !kIsWeb &&
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
    }.contains(defaultTargetPlatform);

/// Scans a barcode / QR code. Where the camera is unavailable (Windows) it
/// asks for the code to be typed or scanned with a USB scanner instead.
Future<String?> scanCode(BuildContext context) async {
  if (!cameraScanSupported) return _typeCodeDialog(context);
  if (kIsWeb) return live_scanner.scanLiveCamera(context);
  return Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const _ScannerPage()));
}

/// Decodes a barcode / QR code from a picture. Returns null when none found.
Future<String?> decodeCodeFromImage(Uint8List bytes) async {
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  decoded = img.bakeOrientation(decoded);
  const maxSide = 1600;
  if (decoded.width > maxSide || decoded.height > maxSide) {
    decoded = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxSide)
        : img.copyResize(decoded, height: maxSide);
  }
  const hints = DecodeHint(tryHarder: true, alsoInverted: true);
  for (final angle in const [0, 90, 270]) {
    final frame = angle == 0 ? decoded : img.copyRotate(decoded, angle: angle);
    final rgba = frame.convert(numChannels: 4);
    final pixels = rgba.getBytes(order: img.ChannelOrder.rgba);
    final ints = Int32List(frame.width * frame.height);
    for (var i = 0; i < ints.length; i++) {
      final o = i * 4;
      ints[i] =
          (0xFF << 24) |
          (pixels[o] << 16) |
          (pixels[o + 1] << 8) |
          pixels[o + 2];
    }
    try {
      final bitmap = BinaryBitmap(
        HybridBinarizer(RGBLuminanceSource(frame.width, frame.height, ints)),
      );
      final text = MultiFormatReader().decode(bitmap, hints).text.trim();
      if (text.isNotEmpty) return text;
    } catch (_) {}
    await Future<void>.delayed(Duration.zero);
  }
  return null;
}

/// Takes / picks a photo of a barcode or QR code and reads it.
Future<String?> scanFromImage(BuildContext context, ImageSource source) async {
  try {
    final file = await ImagePicker().pickImage(source: source);
    if (file == null) return null;
    final code = await decodeCodeFromImage(await file.readAsBytes());
    if (code == null) {
      stockToast('stk_error'.tr, 'stk_scan_image_none'.tr, error: true);
    }
    return code;
  } catch (e) {
    stockToast('stk_error'.tr, stockErrorText(e), error: true);
    return null;
  }
}

Future<String?> _typeCodeDialog(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('stk_scan'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'stk_scan_manual_hint'.tr,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            decoration: stockInput(
              'stk_barcode'.tr,
              icon: Icons.qr_code_scanner,
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.image_outlined),
              label: Text('stk_scan_upload'.tr),
              onPressed: () async {
                final code = await scanFromImage(ctx, ImageSource.gallery);
                if (code != null && ctx.mounted) Navigator.pop(ctx, code);
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('stk_cancel'.tr),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: Text('stk_ok'.tr),
        ),
      ],
    ),
  ).whenComplete(c.dispose);
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  Future<void> _retryCamera() async {
    try {
      await _controller.stop();
      await _controller.start();
    } on MobileScannerException catch (e) {
      if (!mounted) return;
      final reason = e.errorCode == MobileScannerErrorCode.permissionDenied
          ? 'denied'
          : e.errorCode == MobileScannerErrorCode.unsupported
          ? 'notfound'
          : 'other';
      setState(() {});
      stockToast('stk_error'.tr, 'stk_cam_$reason'.tr, error: true);
    }
  }

  Widget _fallbackPanel(String reason) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white70,
            size: 56,
          ),
          const SizedBox(height: 12),
          Text(
            'stk_cam_$reason'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text('stk_scan_take_photo'.tr),
            onPressed: () => _fromImage(ImageSource.camera),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.image_outlined),
            label: Text('stk_scan_upload'.tr),
            onPressed: () => _fromImage(ImageSource.gallery),
          ),
          if (reason != 'insecure' && reason != 'notfound') ...[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              icon: const Icon(Icons.refresh),
              label: Text('stk_cam_retry'.tr),
              onPressed: _retryCamera,
            ),
          ],
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(String code) {
    if (_done || code.trim().isEmpty) return;
    _done = true;
    Navigator.of(context).pop(code.trim());
  }

  Future<void> _fromImage(ImageSource source) async {
    final code = await scanFromImage(context, source);
    if (code != null && mounted) _finish(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('stk_scan'.tr),
        backgroundColor: kStockNavy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'stk_torch'.tr,
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'stk_camera_switch'.tr,
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
          IconButton(
            tooltip: 'stk_scan_upload'.tr,
            icon: const Icon(Icons.image_outlined),
            onPressed: () => _fromImage(ImageSource.gallery),
          ),
          IconButton(
            tooltip: 'stk_scan_type'.tr,
            icon: const Icon(Icons.keyboard_outlined),
            onPressed: () async {
              final code = await _typeCodeDialog(context);
              if (code != null && mounted) _finish(code);
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            placeholderBuilder: (context) => ScannerLoadingFallback(
              onPhoto: () => _fromImage(ImageSource.camera),
              onUpload: () => _fromImage(ImageSource.gallery),
              onRetry: _retryCamera,
            ),
            onDetect: (capture) {
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) {
                  _finish(v);
                  return;
                }
              }
            },
            errorBuilder: (context, error) =>
                _fallbackPanel(switch (error.errorCode) {
                  MobileScannerErrorCode.permissionDenied => 'denied',
                  MobileScannerErrorCode.unsupported => 'notfound',
                  _ => 'other',
                }),
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Column(
              children: [
                Text(
                  'stk_scan_hint'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text('stk_scan_take_photo'.tr),
                      onPressed: () => _fromImage(ImageSource.camera),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.image_outlined),
                      label: Text('stk_scan_upload'.tr),
                      onPressed: () => _fromImage(ImageSource.gallery),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Finds the product whose SKU or barcode equals [code] (case-insensitive).
Product? findProductByCode(Iterable<Product> products, String code) {
  final c = code.trim().toLowerCase();
  if (c.isEmpty) return null;
  for (final p in products) {
    if (p.sku.trim().toLowerCase() == c ||
        p.barcode.trim().toLowerCase() == c) {
      return p;
    }
  }
  return null;
}

/// Scans a code and resolves it to a product, with a toast when unknown.
Future<Product?> scanForProduct(
  BuildContext context,
  List<Product> products, {
  bool trackedOnly = false,
}) async {
  final code = await scanCode(context);
  if (code == null || code.isEmpty) return null;
  final candidates = products.where(
    (p) => p.active && (!trackedOnly || p.tracked),
  );
  var p = findProductByCode(candidates, code);
  p ??= await StockService.current().findProductByCode(code);
  if (p != null && (!p.active || (trackedOnly && !p.tracked))) {
    p = null;
  }
  if (p != null) return p;

  if (!context.mounted) return null;
  final linkCode = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('stk_scan_not_found_title'.tr),
      content: Text(fmtText('stk_scan_link_prompt', {'code': code})),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('stk_cancel'.tr),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('stk_link_code'.tr),
        ),
      ],
    ),
  );
  if (linkCode == true && context.mounted) {
    final target = await pickProduct(
      context,
      products,
      trackedOnly: trackedOnly,
    );
    if (target != null && target.id != null) {
      try {
        await StockService.current().addBarcodeAlias(
          productId: target.id!,
          barcode: code,
        );
        stockToast(
          'stk_saved'.tr,
          fmtText('stk_code_linked', {'code': code, 'name': target.name}),
        );
        return target;
      } catch (e) {
        stockToast('stk_error'.tr, stockErrorText(e), error: true);
        return null;
      }
    }
  }
  if (linkCode != true && context.mounted) {
    stockToast(
      'stk_error'.tr,
      fmtText('stk_scan_not_found', {'code': code}),
      error: true,
    );
  }
  return null;
}

/// Lets the user pick a photo and uploads it. Returns the download URL, or
/// null if cancelled.
Future<String?> pickAndUploadProductImage(BuildContext context) async {
  ImageSource? source = ImageSource.gallery;
  if (_cameraPhotoSupported) {
    source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('stk_photo_camera'.tr),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('stk_photo_gallery'.tr),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
  if (source == null) return null;
  final XFile? file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1000,
    maxHeight: 1000,
    imageQuality: 80,
  );
  if (file == null) return null;
  final Uint8List bytes = await file.readAsBytes();
  if (bytes.length > _maxImageBytes) {
    throw StockException('stk_err_image_size');
  }
  final mime = file.mimeType ?? 'image/jpeg';
  if (!mime.startsWith('image/')) throw StockException('stk_err_image_type');
  final ext = mime.split('/').last.replaceAll('jpeg', 'jpg');
  final ref = FirebaseStorage.instance.ref(
    'users/${BusinessAccessService.businessId}/products/'
    '${DateTime.now().millisecondsSinceEpoch}.$ext',
  );
  await ref.putData(bytes, SettableMetadata(contentType: mime));
  return ref.getDownloadURL();
}

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.url,
    this.size = 56,
    this.radius = 10,
  });

  final String url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kStockLight,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        color: kStockBlue,
        size: size * 0.45,
      ),
    );
    if (url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}
