import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

/// Opens a Bluetooth printer picker and sends a rasterized POS receipt.
Future<bool> printThermalReceipt(
  BuildContext context,
  Uint8List receiptPdf,
) async {
  if (kIsWeb) return false;
  return await showDialog<bool>(
        context: context,
        builder: (_) => _ThermalPrinterDialog(receiptPdf: receiptPdf),
      ) ??
      false;
}

class _ThermalPrinterDialog extends StatefulWidget {
  const _ThermalPrinterDialog({required this.receiptPdf});

  final Uint8List receiptPdf;

  @override
  State<_ThermalPrinterDialog> createState() => _ThermalPrinterDialogState();
}

class _ThermalPrinterDialogState extends State<_ThermalPrinterDialog> {
  final _manager = PrinterManager.instance;
  final _devices = <PrinterDevice>[];
  StreamSubscription<PrinterDevice>? _scanSubscription;
  Timer? _scanTimeout;
  bool _scanning = false;
  bool _printing = false;
  bool _ble = false;
  int _paperWidthMm = 80;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _scanTimeout?.cancel();
    unawaited(_scanSubscription?.cancel());
    super.dispose();
  }

  void _scan() {
    _scanTimeout?.cancel();
    unawaited(_scanSubscription?.cancel());
    setState(() {
      _devices.clear();
      _scanning = true;
    });
    try {
      _scanSubscription = _manager
          .discovery(type: PrinterType.bluetooth, isBle: _ble)
          .listen(
            (device) {
              if (!mounted) return;
              if (!_devices.any((item) => item.address == device.address)) {
                setState(() => _devices.add(device));
              }
            },
            onError: (Object error) {
              if (mounted) setState(() => _scanning = false);
            },
            onDone: () {
              if (mounted) setState(() => _scanning = false);
            },
          );
      _scanTimeout = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _scanning = false);
        unawaited(_scanSubscription?.cancel());
      });
    } catch (_) {
      setState(() => _scanning = false);
    }
  }

  Future<void> _print(PrinterDevice device) async {
    final address = device.address;
    if (address == null || address.isEmpty || _printing) return;
    setState(() => _printing = true);
    try {
      final connected = await _manager.connect(
        type: PrinterType.bluetooth,
        model: BluetoothPrinterInput(
          address: address,
          name: device.name,
          isBle: _ble,
          autoConnect: false,
        ),
      );
      if (!connected) throw StateError('Printer connection failed.');

      final raster = await Printing.raster(widget.receiptPdf, dpi: 144).first;
      final png = await raster.toPng();
      final commands = _receiptImageCommands(png, _paperWidthMm);
      final sent = await _manager.send(
        type: PrinterType.bluetooth,
        bytes: commands,
      );
      if (!sent) throw StateError('Printer did not accept the receipt.');
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not print receipt: $error')),
        );
        setState(() => _printing = false);
      }
    } finally {
      try {
        await _manager.disconnect(type: PrinterType.bluetooth);
      } catch (_) {}
    }
  }

  List<int> _receiptImageCommands(Uint8List png, int paperWidthMm) {
    final decoded = img.decodeImage(png);
    if (decoded == null) {
      throw const FormatException('Receipt image is invalid.');
    }
    final width = paperWidthMm == 58 ? 384 : 576;
    final resized = img.copyResize(decoded, width: width);
    final bytesPerRow = width ~/ 8;
    final height = resized.height;
    final bytes = <int>[
      0x1B, 0x40, // Initialize printer.
      0x1D, 0x76, 0x30, 0x00, // GS v 0 raster image.
      bytesPerRow & 0xFF,
      (bytesPerRow >> 8) & 0xFF,
      height & 0xFF,
      (height >> 8) & 0xFF,
    ];
    for (var y = 0; y < height; y++) {
      for (var byteColumn = 0; byteColumn < bytesPerRow; byteColumn++) {
        var packed = 0;
        for (var bit = 0; bit < 8; bit++) {
          final pixel = resized.getPixel(byteColumn * 8 + bit, y);
          final luminance =
              (pixel.r.toDouble() * 0.299 +
              pixel.g.toDouble() * 0.587 +
              pixel.b.toDouble() * 0.114);
          if (pixel.a > 0 && luminance < 170) packed |= 1 << (7 - bit);
        }
        bytes.add(packed);
      }
    }
    bytes.addAll(const [0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x00]);
    return bytes;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('pos_thermal_printer'.tr),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text('pos_printer_paper_size'.tr)),
              DropdownButton<int>(
                value: _paperWidthMm,
                items: const [58, 80]
                    .map(
                      (width) => DropdownMenuItem(
                        value: width,
                        child: Text('$width mm'),
                      ),
                    )
                    .toList(),
                onChanged: _printing
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _paperWidthMm = value);
                        }
                      },
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('pos_printer_ble'.tr),
            value: _ble,
            onChanged: _printing
                ? null
                : (value) {
                    setState(() => _ble = value);
                    _scan();
                  },
          ),
          if (_scanning) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: _devices.isEmpty
                ? Center(
                    child: Text(
                      _scanning
                          ? 'pos_printer_scanning'.tr
                          : 'pos_printer_none_found'.tr,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return ListTile(
                        leading: const Icon(Icons.print_outlined),
                        title: Text(device.name),
                        subtitle: Text(device.address ?? ''),
                        trailing: _printing
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: _printing ? null : () => _print(device),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _printing ? null : _scan,
        child: Text('pos_printer_scan_again'.tr),
      ),
      TextButton(
        onPressed: _printing ? null : () => Navigator.of(context).pop(false),
        child: Text('cancel'.tr),
      ),
    ],
  );
}
