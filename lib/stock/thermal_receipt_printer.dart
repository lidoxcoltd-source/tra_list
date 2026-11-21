import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _savedPrinterKey = 'pos_thermal_printer_saved';
const _paperWidthKey = 'pos_thermal_printer_paper_width_mm';

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
  bool _loadingSettings = true;
  bool _savingPrinter = false;
  bool _feedingPaper = false;
  bool _printed = false;
  bool _ble = false;
  bool _showDeviceList = false;
  bool _selectedPrinterSaved = false;
  PrinterDevice? _selectedDevice;
  int _paperWidthMm = 80;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _scanTimeout?.cancel();
    unawaited(_scanSubscription?.cancel());
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedPrinter = preferences.getStringList(_savedPrinterKey);
      if (!mounted) return;
      setState(() {
        final savedWidth = preferences.getInt(_paperWidthKey);
        if (savedWidth == 58) {
          _paperWidthMm = 58;
        } else if (savedWidth == 80) {
          _paperWidthMm = 80;
        }
        if (savedPrinter != null &&
            savedPrinter.length == 3 &&
            savedPrinter[0].isNotEmpty &&
            savedPrinter[1].isNotEmpty) {
          _selectedDevice = PrinterDevice(
            name: savedPrinter[0],
            address: savedPrinter[1],
          );
          _ble = savedPrinter[2] == '1';
          _selectedPrinterSaved = true;
        } else {
          _showDeviceList = true;
        }
        _loadingSettings = false;
      });
      if (_selectedDevice == null) _scan();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSettings = false;
        _showDeviceList = true;
      });
      _showError('Could not load printer settings: $error');
      _scan();
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
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
              if (!mounted) return;
              setState(() => _scanning = false);
              _showError(error);
            },
            onDone: () {
              if (mounted) setState(() => _scanning = false);
            },
          );
      _scanTimeout = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _scanning = false);
        unawaited(_scanSubscription?.cancel());
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _showError('Could not search for Bluetooth printers: $error');
    }
  }

  void _selectPrinter(PrinterDevice device) {
    _scanTimeout?.cancel();
    unawaited(_scanSubscription?.cancel());
    setState(() {
      _selectedDevice = device;
      _selectedPrinterSaved = false;
      _showDeviceList = false;
      _scanning = false;
    });
  }

  void _chooseAnotherPrinter() {
    setState(() {
      _selectedDevice = null;
      _selectedPrinterSaved = false;
      _showDeviceList = true;
    });
    _scan();
  }

  Future<void> _savePrinter(PrinterDevice device) async {
    final address = device.address;
    if (address == null ||
        address.isEmpty ||
        _savingPrinter ||
        _feedingPaper ||
        _printing) {
      return;
    }
    setState(() => _savingPrinter = true);
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setStringList(_savedPrinterKey, [
        device.name,
        address,
        _ble ? '1' : '0',
      ]);
      if (!saved) throw StateError('Printer preference was not saved.');
      if (!mounted) return;
      setState(() => _selectedPrinterSaved = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('pos_printer_saved'.tr)));
    } catch (error) {
      _showError('${'pos_printer_save_failed'.tr}: $error');
    } finally {
      if (mounted) setState(() => _savingPrinter = false);
    }
  }

  Future<void> _savePaperWidth(int width) async {
    setState(() => _paperWidthMm = width);
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setInt(_paperWidthKey, width);
      if (!saved) throw StateError('Paper width preference was not saved.');
    } catch (error) {
      _showError('${'pos_printer_save_failed'.tr}: $error');
    }
  }

  Future<void> _print(PrinterDevice device) async {
    final address = device.address;
    if (address == null || address.isEmpty || _printing || _feedingPaper) {
      return;
    }
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
      if (mounted) setState(() => _printed = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not print receipt: $error')),
        );
      }
    } finally {
      try {
        await _manager.disconnect(type: PrinterType.bluetooth);
      } catch (error) {
        debugPrint('Could not disconnect thermal printer: $error');
      }
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _feedPaper(PrinterDevice device, int lines) async {
    final address = device.address;
    if (address == null ||
        address.isEmpty ||
        _printing ||
        _feedingPaper ||
        _savingPrinter ||
        lines < 1 ||
        lines > 255) {
      return;
    }
    setState(() => _feedingPaper = true);
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
      final sent = await _manager.send(
        type: PrinterType.bluetooth,
        bytes: [0x1B, 0x64, lines],
      );
      if (!sent) throw StateError('Printer did not accept the feed command.');
    } catch (error) {
      if (mounted) {
        _showError('Could not move printer paper: $error');
      }
    } finally {
      try {
        await _manager.disconnect(type: PrinterType.bluetooth);
      } catch (error) {
        debugPrint('Could not disconnect thermal printer: $error');
      }
      if (mounted) setState(() => _feedingPaper = false);
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
  Widget build(BuildContext context) {
    final selectedDevice = _selectedDevice;
    return AlertDialog(
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
                  onChanged: _printing || _feedingPaper || _loadingSettings
                      ? null
                      : (value) {
                          if (value != null) unawaited(_savePaperWidth(value));
                        },
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'pos_printer_size_remembered'.tr,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text('pos_printer_ble'.tr),
              value: _ble,
              onChanged: _printing || _feedingPaper || _loadingSettings
                  ? null
                  : (value) {
                      setState(() {
                        _ble = value;
                        _selectedDevice = null;
                        _selectedPrinterSaved = false;
                        _showDeviceList = true;
                      });
                      _scan();
                    },
            ),
            const SizedBox(height: 8),
            if (_loadingSettings)
              const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (selectedDevice != null && !_showDeviceList)
              Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.print_rounded),
                      title: Text(
                        selectedDevice.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(selectedDevice.address ?? ''),
                      trailing: Icon(
                        _selectedPrinterSaved
                            ? Icons.bookmark_rounded
                            : Icons.check_circle_rounded,
                        color: _selectedPrinterSaved
                            ? Theme.of(context).colorScheme.primary
                            : Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: 'pos_printer_feed_short'.tr,
                          child: OutlinedButton.icon(
                            onPressed: _printing || _feedingPaper
                                ? null
                                : () => _feedPaper(selectedDevice, 1),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            label: Text('pos_printer_feed_short'.tr),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: 'pos_printer_feed_long'.tr,
                          child: OutlinedButton.icon(
                            onPressed: _printing || _feedingPaper
                                ? null
                                : () => _feedPaper(selectedDevice, 5),
                            icon: const Icon(
                              Icons.keyboard_double_arrow_down_rounded,
                            ),
                            label: Text('pos_printer_feed_long'.tr),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _printing ||
                                  _feedingPaper ||
                                  _savingPrinter ||
                                  _selectedPrinterSaved
                              ? null
                              : () => _savePrinter(selectedDevice),
                          icon: _savingPrinter
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _selectedPrinterSaved
                                      ? Icons.bookmark_added_rounded
                                      : Icons.bookmark_add_outlined,
                                ),
                          label: Text(
                            _selectedPrinterSaved
                                ? 'pos_printer_saved'.tr
                                : 'pos_printer_save'.tr,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'pos_printer_choose'.tr,
                        onPressed: _printing || _feedingPaper || _savingPrinter
                            ? null
                            : _chooseAnotherPrinter,
                        icon: const Icon(Icons.swap_horiz_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _printing || _feedingPaper
                          ? null
                          : () => _print(selectedDevice),
                      icon: _printing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.print_rounded),
                      label: Text('pos_printer_print'.tr),
                    ),
                  ),
                ],
              )
            else ...[
              if (_scanning) const LinearProgressIndicator(),
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
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _printing || _savingPrinter
                                ? null
                                : () => _selectPrinter(device),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_showDeviceList && !_loadingSettings)
          TextButton(
            onPressed: _printing || _feedingPaper || _scanning ? null : _scan,
            child: Text('pos_printer_scan_again'.tr),
          ),
        TextButton(
          onPressed: _printing || _feedingPaper || _savingPrinter
              ? null
              : () => Navigator.of(context).pop(_printed),
          child: Text('pos_done'.tr),
        ),
      ],
    );
  }
}
