import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../routes.dart';
import '../services/convert_to_business.dart';
import '../services/business_access_service.dart';
import '../services/account_mode_service.dart';
import '../stock/stock_models.dart';
import '../stock/stock_service.dart';
import 'market_models.dart';
import 'market_audio.dart';
import 'market_image_editor_page.dart';
import 'market_video.dart';
import 'market_video_audio.dart';
import 'market_video_preview.dart';
import 'market_palette.dart';
import 'market_service.dart';
import 'market_text_card.dart';

class _ThousandsSeparatorFormatter extends TextInputFormatter {
  const _ThousandsSeparatorFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawValue = newValue.text.replaceAll(',', '');
    if (rawValue.isEmpty) return newValue.copyWith(text: '');
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(rawValue)) return oldValue;

    final parts = rawValue.split('.');
    final groupedInteger = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final formatted = parts.length == 1
        ? groupedInteger
        : '$groupedInteger.${parts.last}';
    final cursorAtEnd = newValue.selection.extentOffset == newValue.text.length;
    if (cursorAtEnd) {
      return newValue.copyWith(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    final digitsBeforeCursor = newValue.text
        .substring(0, newValue.selection.extentOffset)
        .replaceAll(RegExp(r'\D'), '')
        .length;
    var cursorOffset = 0;
    var digitsSeen = 0;
    while (cursorOffset < formatted.length && digitsSeen < digitsBeforeCursor) {
      if (RegExp(r'\d').hasMatch(formatted[cursorOffset])) digitsSeen++;
      cursorOffset++;
    }
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }
}

/// Opens the post composer, or asks personal accounts to use a business one.
Future<bool?> openMarketComposer(
  BuildContext context, {
  String initialType = 'post',
}) async {
  if (AccountModeService.current != AccountMode.business) {
    final switchAccount = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: MarketPalette.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: MarketPalette.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: MarketPalette.blueSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: MarketPalette.blue,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'market_business_only_title'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MarketPalette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'market_business_only_body'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MarketPalette.textMuted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MarketPalette.text,
                          side: const BorderSide(color: MarketPalette.border),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('close'.tr),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: MarketPalette.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('market_business_only_action'.tr),
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
    if (switchAccount == true && context.mounted) {
      final converted = await convertToBusinessAccount(context);
      if (converted) Get.offAllNamed(AppRoutes.market);
    }
    return null;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MarketPalette.surface,
    builder: (_) => Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: CreatePostSheet(initialType: initialType),
    ),
  );
}

class CreatePostSheet extends StatefulWidget {
  const CreatePostSheet({super.key, this.initialType = 'post'});

  final String initialType;

  @override
  State<CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<CreatePostSheet> {
  final _formKey = GlobalKey<FormState>();
  final _captionController = TextEditingController();
  final _productNameController = TextEditingController();
  final _priceController = TextEditingController();
  final List<Uint8List> _imageBytes = [];
  final List<String> _imageExtensions = [];
  String _productId = '';
  String _productOwnerUid = '';
  bool _productInStock = true;
  late String _type;
  bool _publishing = false;
  double _uploadProgress = 0;
  MarketAudioSelection? _audio;
  MarketVideoSelection? _video;
  LocalVideoInfo _videoInfo = const LocalVideoInfo();
  int _textBg = 0;
  int _textFont = 0;

  bool get _inTextMode => _textMode && _type != 'product';

  Widget _textStyleSection() {
    final colors =
        marketTextGradients[_textBg.clamp(0, marketTextGradients.length - 1)];
    final fg = colors.first.computeLuminance() > .6
        ? const Color(0xFF1F2937)
        : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(minHeight: 240),
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
              ),
              child: TextFormField(
                controller: _captionController,
                minLines: 3,
                maxLines: 10,
                maxLength: 2000,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.sentences,
                cursorColor: fg,
                onChanged: (_) => setState(() {}),
                style: marketTextStyle(_textFont, 24, fg),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'market_caption'.tr
                    : null,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  counterStyle: TextStyle(color: fg.withValues(alpha: .7)),
                  errorStyle: TextStyle(color: fg),
                  hintText: 'market_caption'.tr,
                  hintStyle: marketTextStyle(
                    _textFont,
                    24,
                    fg.withValues(alpha: .6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: marketTextGradients.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => setState(() => _textBg = index),
                child: Container(
                  width: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: marketTextGradients[index],
                    ),
                    border: Border.all(
                      color: _textBg == index
                          ? MarketPalette.blue
                          : MarketPalette.border,
                      width: _textBg == index ? 3 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < marketTextFontLabels.length; i++)
                ChoiceChip(
                  label: Text(
                    marketTextFontLabels[i].tr,
                    style: marketTextStyle(i, 13, MarketPalette.text),
                  ),
                  selected: _textFont == i,
                  onSelected: (_) => setState(() => _textFont = i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _useVideo = false;
  bool _textMode = false;

  Future<void> _pickVideo() async {
    final selection = await pickMarketVideo(context);
    if (selection == null || !mounted) return;
    setState(() {
      _video = selection;
      _videoInfo = const LocalVideoInfo();
      _audio = null;
    });
    final info = await prepareLocalVideo(selection.bytes, selection.extension);
    if (mounted && identical(_video, selection)) {
      setState(() => _videoInfo = info);
    }
  }

  bool get _canVideo =>
      AccountModeService.current == AccountMode.business &&
      BusinessAccessService.can('stock', 'create');

  Widget _mediaSwitch() {
    Widget item(String mode, IconData icon, String label) {
      final textOn = _textMode && _type != 'product';
      final selected = mode == 'text'
          ? textOn
          : !textOn && _useVideo == (mode == 'video');
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _publishing
              ? null
              : () => setState(() {
                  _textMode = mode == 'text';
                  _useVideo = mode == 'video';
                  if (_useVideo) {
                    _audio = null;
                  } else {
                    _video = null;
                  }
                  if (_textMode) {
                    _imageBytes.clear();
                    _imageExtensions.clear();
                  }
                }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? MarketPalette.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : MarketPalette.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: selected ? Colors.white : MarketPalette.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: MarketPalette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MarketPalette.border),
      ),
      child: Row(
        children: [
          item('image', Icons.image_outlined, 'market_media_photo'.tr),
          if (_canVideo)
            item('video', Icons.videocam_rounded, 'market_media_video'.tr),
          if (_type != 'product')
            item('text', Icons.text_fields_rounded, 'market_media_text'.tr),
        ],
      ),
    );
  }

  DateTime? _publishAt;

  void _addHashtag(String tag) {
    final text = _captionController.text;
    if (extractHashtags(text).contains(tag)) return;
    final separator = text.isEmpty || text.endsWith(' ') || text.endsWith('\n')
        ? ''
        : ' ';
    final next = '$text$separator#$tag ';
    _captionController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _captionController.dispose();
    _productNameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_imageBytes.length >= 10) {
      _showMessage('market_photos_limit'.tr);
      return;
    }
    try {
      final picker = ImagePicker();
      final List<XFile> files;
      if (_type == 'status') {
        final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (context) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text('market_gallery'.tr),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text('market_camera'.tr),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ],
            ),
          ),
        );
        if (source == null) return;
        final file = await picker.pickImage(
          source: source,
          maxWidth: 1400,
          maxHeight: 1400,
          imageQuality: 82,
        );
        files = file == null ? const [] : [file];
      } else {
        files = await picker.pickMultiImage(
          maxWidth: 1400,
          maxHeight: 1400,
          imageQuality: 82,
        );
      }
      if (!mounted || files.isEmpty) return;

      final bytesToAdd = <Uint8List>[];
      final extensionsToAdd = <String>[];
      for (final file in files.take(10 - _imageBytes.length)) {
        final extension = file.name.split('.').last.toLowerCase();
        if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
          _showMessage('market_invalid_photo'.tr);
          continue;
        }
        final bytes = await file.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          _showMessage('market_invalid_photo'.tr);
          continue;
        }
        bytesToAdd.add(bytes);
        extensionsToAdd.add(extension);
      }
      if (!mounted) return;
      setState(() {
        _imageBytes.addAll(bytesToAdd);
        _imageExtensions.addAll(extensionsToAdd);
      });
    } catch (_) {
      if (mounted) _showMessage('market_invalid_photo'.tr);
    }
  }

  Future<void> _editImage(int index) async {
    final edited = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MarketImageEditorPage(bytes: _imageBytes[index]),
      ),
    );
    if (edited == null || !mounted || index >= _imageBytes.length) return;
    if (edited.length > 5 * 1024 * 1024) {
      _showMessage('market_invalid_photo'.tr);
      return;
    }
    setState(() {
      _imageBytes[index] = edited;
      _imageExtensions[index] = 'jpg';
    });
  }

  Future<void> _pickAudio() async {
    final selection = await pickMarketSound(context);
    if (selection != null && mounted) setState(() => _audio = selection);
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _publishAt ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _publishAt ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!picked.isAfter(now)) {
      _showMessage('market_schedule_future'.tr);
      return;
    }
    setState(() => _publishAt = picked);
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    final isVideo = _useVideo;
    final text = _captionController.text.trim();
    final noMedia = isVideo ? _video == null : _imageBytes.isEmpty;
    if (noMedia && (_type == 'product' || text.isEmpty)) {
      _showMessage(
        _type != 'product'
            ? 'market_text_or_media_required'.tr
            : isVideo
            ? 'market_video_required'.tr
            : 'market_photos_required'.tr,
      );
      return;
    }
    if (!isVideo && _type == 'status' && _imageBytes.length > 1) {
      _showMessage('market_status_one_image'.tr);
      return;
    }
    setState(() {
      _publishing = true;
      _uploadProgress = 0;
    });
    try {
      await MarketService.publishPost(
        type: _type,
        caption: _captionController.text,
        category: '',
        productName: _productNameController.text,
        productId: _type == 'product' || _type == 'status' ? _productId : '',
        productOwnerUid: _type == 'product' || _type == 'status'
            ? _productOwnerUid
            : '',
        price: _type == 'product'
            ? (double.tryParse(
                    _priceController.text.replaceAll(',', '').trim(),
                  ) ??
                  0)
            : 0,
        inStock: _productInStock,
        imageBytes: List.unmodifiable(isVideo ? <Uint8List>[] : _imageBytes),
        imageExtensions: List.unmodifiable(
          isVideo ? <String>[] : _imageExtensions,
        ),
        audio: isVideo ? null : _audio,
        video: isVideo ? _video : null,
        publishAt: _type == 'status' ? null : _publishAt,
        textBg: _textBg,
        textFont: _textFont,
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );
      if (!mounted) return;
      if (isVideo && _video != null) {
        final title = _productNameController.text.trim().isNotEmpty
            ? _productNameController.text
            : _captionController.text.split('\n').first;
        unawaited(
          autoShareVideoSound(
            video: _video!.bytes,
            videoName: _video!.name,
            title: title,
            cover: _videoInfo.thumbnail,
          ),
        );
      }
      _showMessage('market_published'.tr);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _showMessage('${'market_publish_failed'.tr}\n$error');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _selectInventoryProduct() async {
    if (AccountModeService.current != AccountMode.business ||
        !BusinessAccessService.can('stock', 'view') ||
        (_type == 'product' && !BusinessAccessService.can('stock', 'create'))) {
      return;
    }
    final productsStream = StockService.current().watchProducts();
    final selected = await showDialog<Product>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('market_select_inventory_product'.tr),
        content: SizedBox(
          width: 480,
          height: 420,
          child: StreamBuilder<List<Product>>(
            stream: productsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('stk_error'.tr));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final products = snapshot.data!
                  .where((product) => product.active)
                  .toList();
              if (products.isEmpty) {
                return Center(child: Text('market_no_inventory_products'.tr));
              }
              return ListView.separated(
                itemCount: products.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ListTile(
                    leading: product.imageUrl.isEmpty
                        ? const Icon(Icons.inventory_2_outlined)
                        : Image.network(
                            product.imageUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.inventory_2_outlined),
                          ),
                    title: Text(product.name),
                    subtitle: Text(
                      'TZS ${product.sellPrice.toStringAsFixed(0)} · '
                      '${product.tracked ? product.quantity : '∞'} ${product.unit}',
                    ),
                    onTap: () => Navigator.of(context).pop(product),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('cancel'.tr),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _productId = selected.id ?? '';
      _productOwnerUid = BusinessAccessService.businessId;
      _productInStock = !selected.tracked || selected.quantity > 0;
      _productNameController.text = selected.name;
      _priceController.text = NumberFormat(
        '#,##0.##',
      ).format(selected.sellPrice);
    });
  }

  InputDecoration _decoration(
    String label, {
    String? helper,
    IconData? icon,
    bool alignHint = false,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      helperText: helper,
      alignLabelWithHint: alignHint,
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 20, color: MarketPalette.textMuted),
      filled: true,
      fillColor: MarketPalette.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: border(MarketPalette.border),
      focusedBorder: border(MarketPalette.blue, 1.6),
      errorBorder: border(MarketPalette.red),
      focusedErrorBorder: border(MarketPalette.red, 1.6),
    );
  }

  Widget _section(String title, {Widget? trailing, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: MarketPalette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _typeCard(String value, IconData icon, String label) {
    final selected = _type == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _publishing ? null : () => setState(() => _type = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? MarketPalette.blueSoft : MarketPalette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? MarketPalette.blue : MarketPalette.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 24,
                color: selected ? MarketPalette.blue : MarketPalette.textMuted,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? MarketPalette.blue : MarketPalette.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    bool active = false,
    VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    return Material(
      color: active ? MarketPalette.blueSoft : MarketPalette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _publishing ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? MarketPalette.blue : MarketPalette.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: active ? MarketPalette.blue : MarketPalette.blueSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: active ? Colors.white : MarketPalette.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MarketPalette.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MarketPalette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _publishing ? null : onClear,
                  icon: const Icon(Icons.close_rounded, size: 20),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: MarketPalette.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoTile({required Widget child, VoidCallback? onTap}) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Material(
        color: MarketPalette.blueSoft,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }

  Widget _buildPhotos() {
    final single = _type == 'status';
    final canAdd = !_publishing && !(single && _imageBytes.isNotEmpty);
    final addTile = _photoTile(
      onTap: canAdd ? _pickImages : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 28,
            color: canAdd ? MarketPalette.blue : MarketPalette.textMuted,
          ),
          const SizedBox(height: 6),
          Text(
            'market_add_photos'.tr,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: canAdd ? MarketPalette.blue : MarketPalette.textMuted,
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount:
            _imageBytes.length + (single && _imageBytes.isNotEmpty ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == _imageBytes.length) return addTile;
          return SizedBox(
            width: 104,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: _publishing ? null : () => _editImage(index),
                    child: Image.memory(
                      _imageBytes[index],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (index == 0 && _imageBytes.length > 1)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: InkWell(
                    onTap: _publishing
                        ? null
                        : () => setState(() {
                            _imageBytes.removeAt(index);
                            _imageExtensions.removeAt(index);
                          }),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final video = _video;
    final audio = _audio;
    final at = _publishAt;
    final isBusiness = AccountModeService.current == AccountMode.business;
    return FractionallySizedBox(
      heightFactor: .94,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: MarketPalette.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'market_create_post'.tr,
                    style: const TextStyle(
                      color: MarketPalette.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: localizations.closeButtonTooltip,
                  onPressed: _publishing ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                children: [
                  Row(
                    children: [
                      _typeCard(
                        'status',
                        Icons.timelapse_rounded,
                        'market_status'.tr,
                      ),
                      const SizedBox(width: 10),
                      _typeCard(
                        'post',
                        Icons.image_outlined,
                        'market_regular_post'.tr,
                      ),
                      const SizedBox(width: 10),
                      _typeCard(
                        'product',
                        Icons.sell_outlined,
                        'market_product_listing'.tr,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _section(
                    _textMode && _type != 'product'
                        ? 'market_media_text'.tr
                        : _useVideo
                        ? 'market_media_video'.tr
                        : 'market_add_photos'.tr,
                    trailing: _useVideo || _textMode
                        ? null
                        : Text(
                            '${_imageBytes.length}/${_type == 'status' ? 1 : 10}',
                            style: const TextStyle(
                              color: MarketPalette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _mediaSwitch(),
                        if (_inTextMode) _textStyleSection(),
                        if (_useVideo)
                          _optionTile(
                            icon: Icons.videocam_rounded,
                            title: video?.name ?? 'market_video_add'.tr,
                            subtitle: video == null
                                ? '${marketVideoMaxSeconds}s, 50MB'
                                : null,
                            active: video != null,
                            onTap: _pickVideo,
                            onClear: video == null
                                ? null
                                : () => setState(() => _video = null),
                          ),
                        if (_useVideo && video != null && _videoInfo.hasPreview)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: MarketLocalVideoPreview(
                              key: ValueKey(_videoInfo.path ?? _videoInfo.url),
                              path: _videoInfo.path,
                              url: _videoInfo.url,
                            ),
                          )
                        else if (!_useVideo &&
                            !(_textMode && _type != 'product'))
                          _buildPhotos(),
                      ],
                    ),
                  ),
                  if (_type == 'product')
                    _section(
                      'market_product_listing'.tr,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isBusiness &&
                              BusinessAccessService.can('stock', 'create'))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _optionTile(
                                icon: Icons.inventory_2_outlined,
                                title: 'market_select_inventory_product'.tr,
                                active: _productId.isNotEmpty,
                                onTap: _selectInventoryProduct,
                              ),
                            ),
                          TextFormField(
                            controller: _productNameController,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) {
                              if (_productId.isNotEmpty) {
                                setState(() {
                                  _productId = '';
                                  _productOwnerUid = '';
                                  _productInStock = true;
                                });
                              }
                            },
                            decoration: _decoration(
                              'market_product_name'.tr,
                              icon: Icons.label_outline_rounded,
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'market_product_name'.tr
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _priceController,
                            onChanged: (_) {
                              if (_productId.isNotEmpty) {
                                setState(() {
                                  _productId = '';
                                  _productOwnerUid = '';
                                  _productInStock = true;
                                });
                              }
                            },
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: const [
                              _ThousandsSeparatorFormatter(),
                            ],
                            decoration: _decoration(
                              '${'market_price'.tr} (${'market_optional'.tr})',
                              icon: Icons.payments_outlined,
                            ),
                            validator: (value) {
                              final text = (value ?? '')
                                  .replaceAll(',', '')
                                  .trim();
                              if (text.isEmpty) return null;
                              final price = double.tryParse(text);
                              if (price == null || price < 0) {
                                return 'market_price'.tr;
                              }
                              return null;
                            },
                          ),
                          if (_productId.isEmpty)
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _productInStock,
                              onChanged: _publishing
                                  ? null
                                  : (value) =>
                                        setState(() => _productInStock = value),
                              title: Text('market_in_stock'.tr),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  size: 15,
                                  color: MarketPalette.textMuted,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'market_whatsapp_from_profile'.tr,
                                    style: const TextStyle(
                                      color: MarketPalette.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!_inTextMode)
                    _section(
                      'market_caption'.tr,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_type == 'status' &&
                              isBusiness &&
                              BusinessAccessService.can('stock', 'view'))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _optionTile(
                                icon: Icons.link_rounded,
                                title: 'market_link_status_product'.tr,
                                active: _productId.isNotEmpty,
                                onTap: _selectInventoryProduct,
                              ),
                            ),
                          TextFormField(
                            controller: _captionController,
                            minLines: 4,
                            maxLines: 8,
                            maxLength: 2000,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => setState(() {}),
                            decoration: _decoration(
                              'market_caption'.tr,
                              helper: 'market_hashtag_help'.tr,
                              alignHint: true,
                            ),
                            validator: (value) =>
                                _type != 'status' &&
                                    (value == null || value.trim().isEmpty)
                                ? 'market_caption'.tr
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 0,
                            children: [
                              for (final tag in marketSuggestedHashtags)
                                ActionChip(
                                  label: Text('#$tag'),
                                  labelStyle: const TextStyle(
                                    color: MarketPalette.blue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  backgroundColor: MarketPalette.blueSoft,
                                  side: BorderSide.none,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _publishing
                                      ? null
                                      : () => _addHashtag(tag),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (!_useVideo)
                    _section(
                      'market_sound_add'.tr,
                      child: _optionTile(
                        icon: Icons.music_note_rounded,
                        title: audio == null
                            ? 'market_sound_add'.tr
                            : (audio.title.isEmpty
                                  ? 'market_sound'.tr
                                  : audio.title),
                        active: audio != null,
                        onTap: _pickAudio,
                        onClear: audio == null
                            ? null
                            : () => setState(() => _audio = null),
                      ),
                    ),
                  if (_type != 'status')
                    _section(
                      'market_schedule'.tr,
                      child: _optionTile(
                        icon: Icons.schedule_rounded,
                        title: at == null
                            ? 'market_schedule'.tr
                            : '${'market_schedule_at'.tr}: '
                                  '${localizations.formatShortDate(at)} '
                                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
                        active: at != null,
                        onTap: _pickSchedule,
                        onClear: at == null
                            ? null
                            : () => setState(() => _publishAt = null),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: const BoxDecoration(
              color: MarketPalette.surface,
              border: Border(top: BorderSide(color: MarketPalette.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_publishing) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _uploadProgress,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _publishing ? null : _publish,
                  icon: _publishing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _publishing
                        ? '${(_uploadProgress * 100).round()}%'
                        : 'market_publish'.tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
