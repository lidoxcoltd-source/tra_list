import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:tra_list/invoice/language_controller.dart';
import 'package:tra_list/services/company_logo_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:get/get.dart';

/// Improved and professional re-design of the original ProfilePage.
/// Features added:
/// - Color picker dialog (flutter_colorpicker) with quick swatches
/// - Improved image picker (camera/gallery on mobile + file picker on web)
/// - Interactive preview (zoom/pan) + full-screen preview dialog
/// - Better upload progress with percent, and upload cancel support
/// - Cleaner, card-based UI with consistent padding and icons

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final LanguageController langController =
      Get.isRegistered<LanguageController>()
      ? Get.find<LanguageController>()
      : Get.put(LanguageController());

  final nameC = TextEditingController();
  final addressC = TextEditingController();
  final phoneC = TextEditingController();
  final emailC = TextEditingController();
  final websiteC = TextEditingController();
  final taxIdC = TextEditingController();
  final handleC = TextEditingController();

  // Payment
  final beneficiaryC = TextEditingController();
  final bankC = TextEditingController();
  final accountC = TextEditingController();
  final swiftC = TextEditingController();
  final paymentMethodC = TextEditingController();

  // Colors stored as Color objects for easier handling
  Color brandColor = const Color(0xFFF15A24);
  Color accentColor = const Color(0xFF1976D2);
  Color footerColor = const Color(0xFF424242);

  // Logo/image
  String? logoUrl;
  String logoSource = 'firebase'; // firebase | local
  Uint8List? pickedBytes;
  String? pickedExt;
  Uint8List? localLogoBytes;

  // Upload state
  double? uploadProgress;
  UploadTask? _currentUploadTask;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      final data = await ProfileService.loadOrCreate();
      if (!mounted) return;
      nameC.text = data['name']?.toString() ?? '';
      addressC.text = data['address']?.toString() ?? '';
      phoneC.text = data['phone']?.toString() ?? '';
      emailC.text = data['email']?.toString() ?? '';
      websiteC.text = data['website']?.toString() ?? '';
      taxIdC.text = data['taxId']?.toString() ?? '';
      handleC.text = data['handle']?.toString() ?? '';

      beneficiaryC.text = data['beneficiary']?.toString() ?? '';
      bankC.text = data['bank']?.toString() ?? '';
      accountC.text = data['account']?.toString() ?? '';
      swiftC.text = data['swift']?.toString() ?? '';
      paymentMethodC.text = data['paymentMethod']?.toString() ?? '';

      final colors = (data['colors'] as Map?) ?? {};
      setState(() {
        brandColor = Color(0xFF000000 | (colors['brand'] as int? ?? 0xF15A24));
        accentColor = Color(
          0xFF000000 | (colors['accent'] as int? ?? 0x1976D2),
        );
        footerColor = Color(
          0xFF000000 | (colors['footer'] as int? ?? 0x424242),
        );
        logoUrl = (data['logoUrl']?.toString().trim() ?? '');
        logoSource = (data['logoSource']?.toString().trim().isNotEmpty ?? false)
            ? data['logoSource'].toString().trim().toLowerCase()
            : 'firebase';

        // Load language from profile
        final langCode = data['language']?.toString();
        if (langCode != null) {
          final currentLang = langController.locale.languageCode;
          if (langCode != currentLang) {
            langController.changeLanguage(
              langCode,
              langCode == 'sw' ? 'TZ' : 'US',
            );
          }
        }
      });

      localLogoBytes = await CompanyLogoService.loadLocalLogoBytes();
      final sourceFromApp = await CompanyLogoService.getLogoSource(
        fallback: logoSource,
      );
      if (mounted) {
        setState(() {
          logoSource = sourceFromApp.toLowerCase();
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Init error: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    nameC.dispose();
    addressC.dispose();
    phoneC.dispose();
    emailC.dispose();
    websiteC.dispose();
    taxIdC.dispose();
    handleC.dispose();
    beneficiaryC.dispose();
    bankC.dispose();
    accountC.dispose();
    swiftC.dispose();
    paymentMethodC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F9),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1A2B3C),
          title: Text(
            'profile_title'.tr,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          bottom: TabBar(
            labelColor: brandColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: brandColor,
            indicatorWeight: 2.5,
            tabs: const [
              Tab(
                icon: Icon(Icons.business_outlined, size: 18),
                text: 'Company',
              ),
              Tab(
                icon: Icon(Icons.payment_outlined, size: 18),
                text: 'Payment',
              ),
              Tab(
                icon: Icon(Icons.palette_outlined, size: 18),
                text: 'Branding',
              ),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCompanyHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _boot,
                child: TabBarView(
                  children: [
                    _buildCompanyTab(),
                    _buildPaymentTab(),
                    _buildBrandingTab(),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildSaveBar(),
      ),
    );
  }

  Widget _buildCompanyHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: busy ? null : _chooseImage,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 68,
                    height: 68,
                    color: Colors.grey.shade100,
                    child: _previewWidget(),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: brandColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameC.text.isNotEmpty ? nameC.text : 'Your Company',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: Color(0xFF1A2B3C),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (emailC.text.isNotEmpty)
                  Text(
                    emailC.text,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (phoneC.text.isNotEmpty)
                  Text(
                    phoneC.text,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: uploadProgress != null
            ? Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: uploadProgress! <= 1 ? uploadProgress : null,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(brandColor),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(uploadProgress! * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Cancel upload',
                    onPressed: _currentUploadTask != null
                        ? _cancelUpload
                        : null,
                    icon: const Icon(Icons.cancel_outlined),
                    color: Colors.red,
                  ),
                ],
              )
            : SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: brandColor.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
      ),
    );
  }

  Widget _buildCompanyTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        _buildFormCard(
          title: 'Language',
          icon: Icons.language_outlined,
          children: [_buildLanguageSelector()],
        ),
        const SizedBox(height: 12),
        _buildFormCard(
          title: 'Company Information',
          icon: Icons.business_outlined,
          children: [
            _buildTextField(nameC, 'Company Name', Icons.label_outline),
            _buildTextField(addressC, 'Address', Icons.location_on_outlined),
            _buildTextField(phoneC, 'Phone', Icons.phone_outlined),
            _buildTextField(emailC, 'Email', Icons.email_outlined),
            _buildTextField(websiteC, 'Website', Icons.language_outlined),
            _buildTextField(taxIdC, 'Tax ID / TIN', Icons.badge_outlined),
            _buildTextField(handleC, 'Social Handle', Icons.alternate_email),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        _buildFormCard(
          title: 'Payment Details',
          icon: Icons.account_balance_outlined,
          children: [
            _buildTextField(
              beneficiaryC,
              'Beneficiary Name',
              Icons.person_outline,
            ),
            _buildTextField(bankC, 'Bank Name', Icons.account_balance_outlined),
            _buildTextField(accountC, 'Account Number', Icons.pin_outlined),
            _buildTextField(swiftC, 'SWIFT / BIC Code', Icons.code_outlined),
            _buildTextField(
              paymentMethodC,
              'Default Payment Method',
              Icons.credit_card_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBrandingTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        _buildFormCard(
          title: 'Brand Colors',
          icon: Icons.palette_outlined,
          children: [
            _buildColorRow(
              'Primary Brand Color',
              brandColor,
              (c) => setState(() => brandColor = c),
            ),
            _buildColorRow(
              'Accent Color',
              accentColor,
              (c) => setState(() => accentColor = c),
            ),
            _buildColorRow(
              'Footer Color',
              footerColor,
              (c) => setState(() => footerColor = c),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildFormCard(
          title: 'Company Logo',
          icon: Icons.image_outlined,
          children: [_buildLogoUploadArea()],
        ),
      ],
    );
  }

  Widget _buildLanguageSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildLangOption('en', 'English', '\u{1f1ec}\u{1f1e7}'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildLangOption('sw', 'Kiswahili', '\u{1f1f9}\u{1f1ff}'),
        ),
      ],
    );
  }

  Widget _buildLangOption(String code, String name, String flag) {
    final selected = langController.locale.languageCode == code;
    return GestureDetector(
      onTap: () {
        if (!selected) {
          langController.changeLanguage(code, code == 'sw' ? 'TZ' : 'US');
          _saveLanguage(code);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? brandColor.withOpacity(0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? brandColor : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? brandColor : Colors.grey.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_circle, size: 14, color: brandColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewWidget() {
    if (pickedBytes != null) {
      return InteractiveViewer(
        child: Image.memory(pickedBytes!, fit: BoxFit.contain),
      );
    }
    if (logoSource == 'local' && localLogoBytes != null) {
      return InteractiveViewer(
        child: Image.memory(localLogoBytes!, fit: BoxFit.contain),
      );
    }
    if ((logoUrl ?? '').isNotEmpty) {
      final url = logoUrl!.trim();
      final inlineBytes = CompanyLogoService.tryDecodeInlineImageBytes(url);

      if (inlineBytes != null) {
        return InteractiveViewer(
          child: Image.memory(inlineBytes, fit: BoxFit.contain),
        );
      }

      if (CompanyLogoService.isLocalOnlyImageUrl(url)) {
        if (localLogoBytes != null) {
          return InteractiveViewer(
            child: Image.memory(localLogoBytes!, fit: BoxFit.contain),
          );
        }

        return const Center(
          child: Text('Local image is not available in this browser session'),
        );
      }

      return Image.network(
        url,
        headers: const {'Cache-Control': 'no-cache'},
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (_, err, __) {
          debugPrint('Image load error for $url -> $err');
          return const Center(child: Text('Unable to load image'));
        },
      );
    }
    return const Center(
      child: Icon(Icons.image_outlined, size: 40, color: Colors.grey),
    );
  }

  Widget _buildFormCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: brandColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: brandColor),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF1A2B3C),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade500),
        labelText: label,
        labelStyle: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: brandColor, width: 1.8),
        ),
      ),
    ),
  );

  Widget _buildColorRow(
    String label,
    Color color,
    ValueChanged<Color> onColorSelected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF4A5568),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _showColorPicker(color, onColorSelected),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                    style: const TextStyle(fontSize: 12, letterSpacing: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showColorPicker(
    Color start,
    ValueChanged<Color> onChanged,
  ) async {
    Color temp = start;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick Color'),
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColorPicker(
                pickerColor: temp,
                onColorChanged: (c) => temp = c,
                showLabel: true,
                pickerAreaHeightPercent: 0.7,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _swatch(Colors.blue, () => temp = Colors.blue),
                  _swatch(Colors.green, () => temp = Colors.green),
                  _swatch(Colors.orange, () => temp = Colors.orange),
                  _swatch(Colors.pink, () => temp = Colors.pink),
                  _swatch(Colors.grey, () => temp = Colors.grey),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              onChanged(temp);
              Navigator.of(context).pop();
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  Widget _swatch(Color c, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(6),
      ),
    ),
  );

  Widget _buildLogoUploadArea() {
    final hasImage =
        pickedBytes != null ||
        (logoSource == 'local' && localLogoBytes != null) ||
        (logoUrl ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSourceChip(
                'Cloud Storage',
                Icons.cloud_outlined,
                logoSource == 'firebase',
                () => setState(() => logoSource = 'firebase'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSourceChip(
                'Local Device',
                Icons.phone_android_outlined,
                logoSource == 'local',
                () => setState(() => logoSource = 'local'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: busy
              ? null
              : (hasImage ? _showFullScreenPreview : _chooseImage),
          child: Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasImage
                    ? Colors.grey.shade200
                    : brandColor.withOpacity(0.35),
                width: hasImage ? 1 : 1.5,
              ),
            ),
            child: hasImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: _previewWidget(),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 40,
                        color: brandColor.withOpacity(0.45),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tap to upload company logo',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PNG or JPG \u00b7 max 640 \u00d7 640 px',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _actionChip(
              icon: Icons.add_photo_alternate_outlined,
              label: 'Change Image',
              color: brandColor,
              onTap: busy ? null : _chooseImage,
            ),
            if (pickedBytes != null)
              _actionChip(
                icon: Icons.clear,
                label: 'Clear',
                color: Colors.red,
                onTap: () => setState(() => pickedBytes = null),
              ),
            if ((logoUrl ?? '').isNotEmpty && logoSource == 'firebase')
              _actionChip(
                icon: Icons.copy,
                label: 'Copy URL',
                color: const Color(0xFF4A5568),
                onTap: () =>
                    Clipboard.setData(ClipboardData(text: logoUrl ?? '')),
              ),
            if (!kIsWeb &&
                (logoUrl ?? '').isNotEmpty &&
                logoSource == 'firebase')
              _actionChip(
                icon: Icons.build_circle_outlined,
                label: 'Repair URL',
                color: Colors.orange,
                onTap: () async {
                  final fixed =
                      await ProfileService.repairLogoUrlForCurrentUser();
                  if (fixed != null && mounted) {
                    setState(() => logoUrl = fixed.trim());
                  }
                },
              ),
            if (logoSource == 'local' && localLogoBytes != null)
              _actionChip(
                icon: Icons.delete_outline,
                label: 'Remove Local',
                color: Colors.red,
                onTap: () async {
                  await CompanyLogoService.clearLocalLogo();
                  if (!mounted) return;
                  setState(() => localLogoBytes = null);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildSourceChip(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? brandColor.withOpacity(0.09) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? brandColor : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? brandColor : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? brandColor : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseImage() async {
    if (kIsWeb) {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (r == null) return;
      final f = r.files.single;
      if (f.bytes == null) return;
      setState(() {
        pickedBytes = f.bytes;
        pickedExt = (f.extension ?? '').toLowerCase();
      });
      return;
    }

    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pick from gallery'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(c, null),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      pickedBytes = bytes;
      pickedExt = picked.path.split('.').last.toLowerCase();
    });
  }

  Future<void> _showFullScreenPreview() async {
    await showDialog(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: Center(
                  child: InteractiveViewer(child: _previewWidget()),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Save only the language setting to Firebase.
  Future<void> _saveLanguage(String langCode) async {
    try {
      await ProfileService.save({'language': langCode});
      Get.snackbar(
        'Language Saved',
        'Your language preference has been updated.',
      );
    } catch (e) {
      Get.snackbar('Error', 'Could not save language preference: $e');
    }
  }

  Future<void> _save() async {
    if (busy) return;
    try {
      setState(() => busy = true);
      String? newUrl = logoUrl;

      if (pickedBytes != null) {
        if (logoSource == 'local') {
          await CompanyLogoService.saveLocalLogo(pickedBytes!);
          localLogoBytes = await CompanyLogoService.loadLocalLogoBytes();
        } else {
          newUrl = await _uploadBytes(pickedBytes!, pickedExt);
        }
        if (mounted) setState(() => pickedBytes = null);
      }

      await CompanyLogoService.setLogoSource(logoSource);

      await ProfileService.save({
        'name': nameC.text.trim(),
        'address': addressC.text.trim(),
        'phone': phoneC.text.trim(),
        'email': emailC.text.trim(),
        'website': websiteC.text.trim(),
        'taxId': taxIdC.text.trim(),
        'handle': handleC.text.trim(),
        'beneficiary': beneficiaryC.text.trim(),
        'bank': bankC.text.trim(),
        'account': accountC.text.trim(),
        'swift': swiftC.text.trim(),
        'paymentMethod': paymentMethodC.text.trim(),
        'colors': {
          'brand': brandColor.value & 0xFFFFFFFF,
          'accent': accentColor.value & 0xFFFFFFFF,
          'footer': footerColor.value & 0xFFFFFFFF,
        },
        'logoSource': logoSource,
        if (newUrl != null) 'logoUrl': newUrl,
        'language': langController.locale.languageCode,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted)
        setState(() {
          busy = false;
          uploadProgress = null;
        });
    }
  }

  Future<String?> _uploadBytes(Uint8List bytes, String? ext) async {
    final storage = FirebaseStorage.instance;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      final uid = user.uid;

      final safeExt = (ext == 'jpg' || ext == 'jpeg') ? 'jpg' : 'png';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'users/$uid/logo_$ts.$safeExt';
      final ref = storage.ref().child(path);
      final metadata = SettableMetadata(
        contentType: 'image/$safeExt',
        cacheControl: 'public, max-age=604800',
      );

      final uploadTask = ref.putData(bytes, metadata);
      _currentUploadTask = uploadTask;

      uploadProgress = 0.0;
      final sub = uploadTask.snapshotEvents.listen(
        (snap) {
          if (snap.totalBytes > 0) {
            final p = snap.bytesTransferred / snap.totalBytes;
            if (mounted) setState(() => uploadProgress = p);
          }
        },
        onError: (e) {
          debugPrint('snapshot error: $e');
          if (mounted) setState(() => uploadProgress = null);
        },
      );

      final snapshot = await uploadTask.timeout(const Duration(seconds: 120));
      await sub.cancel();
      _currentUploadTask = null;

      if (snapshot.state != TaskState.success)
        throw Exception('Upload failed with state ${snapshot.state}');

      final url = await ref.getDownloadURL();
      if (mounted)
        setState(() {
          uploadProgress = 1.0;
          logoUrl = url;
        });
      return url;
    } on FirebaseException catch (e) {
      debugPrint('FirebaseException: ${e.code} ${e.message}');
      if (mounted) setState(() => uploadProgress = null);
      rethrow;
    } on TimeoutException {
      debugPrint('Upload timed out');
      if (mounted) setState(() => uploadProgress = null);
      rethrow;
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) setState(() => uploadProgress = null);
      rethrow;
    }
  }

  Future<void> _cancelUpload() async {
    try {
      await _currentUploadTask?.cancel();
      if (mounted) setState(() => uploadProgress = null);
    } catch (e) {
      debugPrint('Cancel upload error: $e');
    }
  }
}
