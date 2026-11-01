import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:tra_list/invoice/language_controller.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/market/market_service.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/push_service.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'package:get/get.dart';

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
  final shopNicknameC = TextEditingController();
  final addressC = TextEditingController();
  final phoneC = TextEditingController();
  final secondaryPhoneC = TextEditingController();
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
  Uint8List? pickedBytes;
  String? pickedExt;

  // Upload state
  double? uploadProgress;
  UploadTask? _currentUploadTask;
  bool busy = true;
  bool _uploadingVerificationDocument = false;
  final bool _staffProfile = !BusinessAccessService.isOwner.value;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      if (FirebaseAuth.instance.currentUser == null && !_staffProfile) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      if (_staffProfile) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw StateError('Sign in to open your profile.');
        final snapshot = await FirebaseFirestore.instance
            .collection('userProfiles')
            .doc(user.uid)
            .get();
        final data = snapshot.data() ?? const <String, dynamic>{};
        if (!mounted) return;
        secondaryPhoneC.text = data['secondaryPhone']?.toString() ?? '';
        nameC.text = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'profile_title'.tr;
        emailC.text = user.email ?? '';
        final photoUrl =
            data['photoUrl']?.toString().trim() ?? user.photoURL?.trim() ?? '';
        setState(() {
          logoUrl = photoUrl;
          pickedBytes = null;
        });
        return;
      }
      final data = await ProfileService.loadOrCreate();
      if (!mounted) return;
      nameC.text = data['name']?.toString() ?? '';
      shopNicknameC.text = data['shopNickname']?.toString() ?? '';
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

      final savedLogoUrl = data['logoUrl']?.toString().trim() ?? '';
      final savedLogoUri = Uri.tryParse(savedLogoUrl);
      final publicLogoUrl =
          savedLogoUri?.scheme == 'https' && savedLogoUri!.host.isNotEmpty
          ? savedLogoUrl
          : '';
      final colors = (data['colors'] as Map?) ?? {};
      setState(() {
        brandColor = Color(0xFF000000 | (colors['brand'] as int? ?? 0xF15A24));
        accentColor = Color(
          0xFF000000 | (colors['accent'] as int? ?? 0x1976D2),
        );
        footerColor = Color(
          0xFF000000 | (colors['footer'] as int? ?? 0x424242),
        );
        logoUrl = publicLogoUrl;

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
    shopNicknameC.dispose();
    addressC.dispose();
    phoneC.dispose();
    secondaryPhoneC.dispose();
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
    if (_staffProfile) return _buildStaffProfilePage();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: MjasiColors.background,
        appBar: AppBar(
          title: Text('profile_title'.tr),
          actions: [
            Obx(() {
              final businesses = BusinessAccessService.availableBusinesses;
              if (businesses.length < 2) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                tooltip: 'business_select'.tr,
                icon: const Icon(Icons.swap_horiz_rounded),
                onSelected: (id) async {
                  try {
                    await BusinessAccessService.selectBusiness(id);
                    await _boot();
                  } catch (error) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('business_select_error'.tr)),
                      );
                    }
                  }
                },
                itemBuilder: (context) => [
                  for (final business in businesses)
                    PopupMenuItem(
                      value: business.businessId,
                      child: Text(
                        business.businessName.isEmpty
                            ? business.businessId
                            : business.businessName,
                      ),
                    ),
                ],
              );
            }),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(
              horizontal: MjasiSpacing.md,
            ),
            labelColor: MjasiColors.primaryBlue,
            unselectedLabelColor: MjasiColors.textSecondary,
            indicatorColor: MjasiColors.primaryBlue,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(
                icon: const Icon(Icons.business_outlined, size: 18),
                text: 'profile_company_details'.tr,
              ),
              Tab(
                icon: const Icon(Icons.payment_outlined, size: 18),
                text: 'profile_payment_details'.tr,
              ),
              Tab(
                icon: const Icon(Icons.palette_outlined, size: 18),
                text: 'profile_branding'.tr,
              ),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _boot,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            MjasiSpacing.lg,
                            MjasiSpacing.md,
                            MjasiSpacing.lg,
                            0,
                          ),
                          child: _buildCompanyHeader(),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildCompanyTab(),
                              _buildPaymentTab(),
                              _buildBrandingTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildSaveBar(),
      ),
    );
  }

  Widget _buildStaffProfilePage() {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      appBar: AppBar(
        title: Text('personal_settings'.tr),
        backgroundColor: MjasiColors.background,
        actions: [
          IconButton(
            tooltip: 'home_sign_out'.tr,
            onPressed: busy ? null : _signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(MjasiSpacing.lg),
            children: [
              Container(
                padding: const EdgeInsets.all(MjasiSpacing.lg),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [MjasiColors.primaryNavy, MjasiColors.primaryBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(MjasiRadius.md),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: busy ? null : _chooseImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.white,
                            child: ClipOval(
                              child: SizedBox(
                                width: 62,
                                height: 62,
                                child: _previewWidget(),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 23,
                              height: 23,
                              decoration: BoxDecoration(
                                color: MjasiColors.secondaryBlue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: MjasiSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nameC.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: MjasiSpacing.xs),
                          Text(
                            'personal_settings'.tr,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MjasiSpacing.md),
              _buildFormCard(
                title: 'personal_settings'.tr,
                icon: Icons.person_outline_rounded,
                children: [
                  Text(
                    'personal_profile_photo'.tr,
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: MjasiSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _chooseImage,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: Text('personal_photo_change'.tr),
                  ),
                  const SizedBox(height: MjasiSpacing.md),
                  _buildTextField(
                    secondaryPhoneC,
                    'personal_secondary_phone'.tr,
                    Icons.phone_iphone_outlined,
                    keyboardType: TextInputType.phone,
                    maxLength: 32,
                  ),
                ],
              ),
              const SizedBox(height: MjasiSpacing.md),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: busy ? null : _saveStaffProfile,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text('profile_save_changes'.tr),
                ),
              ),
              const SizedBox(height: MjasiSpacing.sm),
              OutlinedButton.icon(
                onPressed: busy ? null : _signOut,
                icon: const Icon(Icons.logout_rounded),
                label: Text('home_sign_out'.tr),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MjasiColors.error,
                  side: const BorderSide(color: MjasiColors.error),
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyHeader() {
    return Container(
      padding: const EdgeInsets.all(MjasiSpacing.md),
      decoration: BoxDecoration(
        color: MjasiColors.surface,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        border: Border.all(color: MjasiColors.border),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: busy ? null : _chooseImage,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(MjasiRadius.sm),
                  child: Container(
                    width: 60,
                    height: 60,
                    color: MjasiColors.background,
                    child: _previewWidget(),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: brandColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: MjasiSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameC.text.isNotEmpty ? nameC.text : 'profile_title'.tr,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: MjasiColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (emailC.text.isNotEmpty)
                  Text(
                    emailC.text,
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (phoneC.text.isNotEmpty)
                  Text(
                    phoneC.text,
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
    );
  }

  Widget _buildSaveBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          MjasiSpacing.lg,
          MjasiSpacing.sm,
          MjasiSpacing.lg,
          MjasiSpacing.md,
        ),
        decoration: BoxDecoration(
          color: MjasiColors.surface,
          border: const Border(top: BorderSide(color: MjasiColors.border)),
        ),
        child: uploadProgress != null
            ? Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: uploadProgress! <= 1 ? uploadProgress : null,
                        backgroundColor: MjasiColors.border,
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
                height: 48,
                child: FilledButton(
                  onPressed: busy ? null : _save,
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_rounded, size: 19),
                            const SizedBox(width: MjasiSpacing.sm),
                            Text(
                              'profile_save_changes'.tr,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
      ),
    );
  }

  Widget _buildCompanyTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        MjasiSpacing.lg,
        MjasiSpacing.md,
        MjasiSpacing.lg,
        MjasiSpacing.lg,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _buildFormCard(
          title: 'profile_language'.tr,
          icon: Icons.language_outlined,
          children: [_buildLanguageSelector()],
        ),
        const SizedBox(height: 12),
        _buildFormCard(
          title: 'Company Information',
          icon: Icons.business_outlined,
          children: [
            _buildTextField(nameC, 'Company Name', Icons.label_outline),
            _buildTextField(
              shopNicknameC,
              'profile_shop_nickname'.tr,
              Icons.storefront_outlined,
              enabled: BusinessAccessService.isOwner.value,
            ),
            _buildTextField(addressC, 'Address', Icons.location_on_outlined),
            _buildTextField(phoneC, 'Phone', Icons.phone_outlined),
            _buildTextField(emailC, 'Email', Icons.email_outlined),
            _buildTextField(websiteC, 'Website', Icons.language_outlined),
            _buildTextField(taxIdC, 'Tax ID / TIN', Icons.badge_outlined),
            _buildTextField(handleC, 'Social Handle', Icons.alternate_email),
          ],
        ),
        const SizedBox(height: 12),
        _buildFormCard(
          title: 'market_verification_documents_title'.tr,
          icon: Icons.verified_user_outlined,
          children: [
            Text('market_verification_documents_help'.tr),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _uploadingVerificationDocument
                    ? null
                    : _uploadBusinessVerificationDocument,
                icon: _uploadingVerificationDocument
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined),
                label: Text('market_upload_documents_for_verification'.tr),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _uploadBusinessVerificationDocument() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('market_verification_documents_title'.tr),
            ),
            for (final documentType in const ['tin', 'tra', 'brela', 'other'])
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text('market_document_$documentType'.tr),
                onTap: () => Navigator.pop(context, documentType),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('market_document_unavailable'.tr)));
      return;
    }

    setState(() => _uploadingVerificationDocument = true);
    try {
      await MarketService.uploadBusinessDocument(
        uid: BusinessAccessService.businessId,
        type: type,
        fileName: file.name,
        bytes: bytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('market_document_submitted'.tr)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _uploadingVerificationDocument = false);
    }
  }

  Widget _buildPaymentTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        MjasiSpacing.lg,
        MjasiSpacing.md,
        MjasiSpacing.lg,
        MjasiSpacing.lg,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
      padding: const EdgeInsets.fromLTRB(
        MjasiSpacing.lg,
        MjasiSpacing.md,
        MjasiSpacing.lg,
        MjasiSpacing.lg,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!selected) {
            langController.changeLanguage(code, code == 'sw' ? 'TZ' : 'US');
            _saveLanguage(code);
          }
        },
        borderRadius: BorderRadius.circular(MjasiRadius.sm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
            vertical: MjasiSpacing.md,
            horizontal: MjasiSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected ? MjasiColors.lightBlue : MjasiColors.background,
            borderRadius: BorderRadius.circular(MjasiRadius.sm),
            border: Border.all(
              color: selected ? MjasiColors.primaryBlue : MjasiColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: MjasiSpacing.sm),
              Flexible(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? MjasiColors.primaryBlue
                        : MjasiColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: MjasiSpacing.xs),
                const Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: MjasiColors.primaryBlue,
                ),
              ],
            ],
          ),
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
    if ((logoUrl ?? '').isNotEmpty) {
      final url = logoUrl!.trim();
      final uri = Uri.tryParse(url);
      if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
        return Image.network(
          url,
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
    return const Center(
      child: Icon(Icons.image_outlined, size: 40, color: Colors.grey),
    );
  }

  Widget _buildFormCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: MjasiSpacing.md,
              vertical: MjasiSpacing.xs,
            ),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: MjasiColors.lightBlue,
                borderRadius: BorderRadius.circular(MjasiRadius.sm),
              ),
              child: Icon(icon, size: 19, color: MjasiColors.primaryBlue),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: MjasiColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1, color: MjasiColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MjasiSpacing.md,
              MjasiSpacing.md,
              MjasiSpacing.md,
              MjasiSpacing.xs,
            ),
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
    IconData icon, {
    bool enabled = true,
    TextInputType? keyboardType,
    int? maxLength,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: MjasiSpacing.md),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLength: maxLength,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 19, color: MjasiColors.textSecondary),
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 13,
          color: MjasiColors.textSecondary,
        ),
        filled: true,
        fillColor: enabled ? MjasiColors.surface : MjasiColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MjasiSpacing.md,
          vertical: MjasiSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MjasiRadius.sm),
          borderSide: const BorderSide(color: MjasiColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MjasiRadius.sm),
          borderSide: const BorderSide(color: MjasiColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MjasiRadius.sm),
          borderSide: const BorderSide(
            color: MjasiColors.primaryBlue,
            width: 1.5,
          ),
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
      padding: const EdgeInsets.only(bottom: MjasiSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MjasiColors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _showColorPicker(color, onColorSelected),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MjasiSpacing.md,
                vertical: MjasiSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: MjasiColors.background,
                borderRadius: BorderRadius.circular(MjasiRadius.sm),
                border: Border.all(color: MjasiColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: MjasiSpacing.sm),
                  Text(
                    '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                    style: const TextStyle(
                      color: MjasiColors.textPrimary,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: MjasiColors.textSecondary,
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
    final hasImage = pickedBytes != null || (logoUrl ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const SizedBox(height: MjasiSpacing.md),
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
            if ((logoUrl ?? '').isNotEmpty)
              _actionChip(
                icon: Icons.copy,
                label: 'Copy URL',
                color: const Color(0xFF4A5568),
                onTap: () =>
                    Clipboard.setData(ClipboardData(text: logoUrl ?? '')),
              ),
            if (!kIsWeb && (logoUrl ?? '').isNotEmpty)
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
          ],
        ),
        const SizedBox(height: 6),
      ],
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
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
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

  Future<String> _uploadStaffPhoto(Uint8List bytes, String? ext) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before updating your photo.');
    if (bytes.length >= 5 * 1024 * 1024) {
      throw ArgumentError('Choose an image smaller than 5 MB.');
    }
    final safeExt = switch (ext?.toLowerCase()) {
      'jpg' || 'jpeg' => 'jpg',
      'png' => 'png',
      'webp' => 'webp',
      _ => throw ArgumentError('Choose a JPG, PNG, or WebP image.'),
    };
    final contentType = switch (safeExt) {
      'jpg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw StateError('Unsupported profile image format.'),
    };
    final ref = FirebaseStorage.instance.ref().child(
      'userProfiles/${user.uid}/profile/profile_${DateTime.now().millisecondsSinceEpoch}.$safeExt',
    );
    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: contentType, cacheControl: 'private'),
    );
    _currentUploadTask = task;
    try {
      final result = await task.timeout(const Duration(seconds: 120));
      if (result.state != TaskState.success) {
        throw StateError('Profile image upload failed: ${result.state}.');
      }
      return await ref.getDownloadURL();
    } finally {
      _currentUploadTask = null;
    }
  }

  Future<void> _saveStaffProfile() async {
    if (busy) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar('error'.tr, 'personal_save_error'.tr);
      return;
    }
    setState(() => busy = true);
    try {
      var photoUrl = logoUrl ?? '';
      if (pickedBytes != null) {
        photoUrl = await _uploadStaffPhoto(pickedBytes!, pickedExt);
      }
      await user.updatePhotoURL(photoUrl.isEmpty ? null : photoUrl);
      await FirebaseFirestore.instance
          .collection('userProfiles')
          .doc(user.uid)
          .set({
            'displayName': user.displayName ?? '',
            'photoUrl': photoUrl,
            'secondaryPhone': secondaryPhoneC.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        logoUrl = photoUrl;
        pickedBytes = null;
      });
      Get.snackbar('success'.tr, 'personal_settings_saved'.tr);
    } catch (error, stackTrace) {
      debugPrint('Could not save staff profile: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) Get.snackbar('error'.tr, 'personal_save_error'.tr);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signOut() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await PushService.unregister();
      await FirebaseAuth.instance.signOut();
      BusinessAccessService.clear();
      Get.offAllNamed(AppRoutes.login);
    } catch (error, stackTrace) {
      debugPrint('Could not sign out from profile: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => busy = false);
        Get.snackbar('error'.tr, 'personal_sign_out_error'.tr);
      }
    }
  }

  Future<void> _save() async {
    if (busy) return;
    if (!BusinessAccessService.can('profile', 'edit')) {
      Get.snackbar('Error', 'staff_no_permission'.tr);
      return;
    }
    try {
      setState(() => busy = true);
      String? newUrl = logoUrl;

      if (pickedBytes != null) {
        newUrl = await _uploadBytes(pickedBytes!, pickedExt);
      }

      await ProfileService.save({
        'name': nameC.text.trim(),
        'shopNickname': shopNicknameC.text.trim(),
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
        'logoSource': 'firebase',
        if (newUrl != null) 'logoUrl': newUrl,
        'language': langController.locale.languageCode,
      });
      await MarketService.syncBusinessLogoToPublicProfile(
        uid: BusinessAccessService.businessId,
        photoUrl: newUrl ?? '',
      );

      if (!mounted) return;
      setState(() {
        logoUrl = newUrl;
        pickedBytes = null;
      });
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
      if (!BusinessAccessService.can('profile', 'edit')) {
        throw StateError(
          'You do not have permission to change the business logo.',
        );
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      final uid = BusinessAccessService.businessId;

      final safeExt = switch (ext?.toLowerCase()) {
        'jpg' || 'jpeg' => 'jpg',
        'png' => 'png',
        'webp' => 'webp',
        _ => throw ArgumentError('Choose a JPG, PNG, or WebP logo.'),
      };
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'users/$uid/logo_$ts.$safeExt';
      final ref = storage.ref().child(path);
      final metadata = SettableMetadata(
        contentType: switch (safeExt) {
          'jpg' => 'image/jpeg',
          'png' => 'image/png',
          'webp' => 'image/webp',
          _ => throw StateError('Unsupported company logo format.'),
        },
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
