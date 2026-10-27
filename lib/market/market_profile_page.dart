import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../services/business_access_service.dart';
import '../services/account_mode_service.dart';
import '../services/pages/ProfilePage.dart';
import 'create_post_sheet.dart';
import 'market_models.dart';
import 'market_follow_list_page.dart';
import 'market_saved_posts_page.dart';
import 'market_insights_page.dart';
import 'market_service.dart';
import 'market_palette.dart';
import 'market_text_card.dart';

class MarketProfilePage extends StatefulWidget {
  const MarketProfilePage({
    super.key,
    required this.uid,
    this.embedded = false,
  });

  final String uid;
  final bool embedded;

  @override
  State<MarketProfilePage> createState() => _MarketProfilePageState();
}

class _MarketProfilePageState extends State<MarketProfilePage> {
  late Future<MarketProfile?> _profile;
  late Future<List<MarketPost>> _posts;
  bool? _followingOverride;
  bool _followBusy = false;
  bool _uploadingDocument = false;
  bool _updatingProfilePhoto = false;
  int? _followersCountOverride;
  final Map<String, Future<Uint8List>> _documentBytes = {};
  final Map<String, Future<Uint8List?>> _documentThumbnails = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _profile = MarketService.getPublicProfile(
      widget.uid,
      includeFollowCounts: true,
    );
    _posts = MarketService.searchAuthorPosts(widget.uid);
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_profile, _posts]);
  }

  Future<void> _openComposer() async {
    final published = await openMarketComposer(context);
    if (published == true && mounted) await _refresh();
  }

  Future<void> _shareProfile(MarketProfile profile) async {
    final url = 'https://mjasipos.web.app/#/market/profile/${profile.uid}';
    try {
      await SharePlus.instance.share(
        ShareParams(text: '${profile.name}\n$url'),
      );
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _contactProfile(MarketProfile profile) async {
    final phone = profile.whatsapp.replaceAll(RegExp(r'\D'), '');
    if (phone.length < 8 || phone.length > 15) {
      _message('market_seller_whatsapp_missing'.tr);
      return;
    }
    final uri = Uri.https('wa.me', '/$phone', {
      'text': 'Habari, naulizia biashara ya ${profile.name}.',
    });
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _message('support_whatsapp_open_error'.tr);
      }
    } catch (_) {
      _message('support_whatsapp_open_error'.tr);
    }
  }

  String _documentLabel(String type) => switch (type) {
    'tin' => 'market_document_tin'.tr,
    'tra' => 'market_document_tra'.tr,
    'brela' => 'market_document_brela'.tr,
    _ => 'market_document_other'.tr,
  };

  Future<void> _addBusinessDocument(MarketProfile profile) async {
    if (_uploadingDocument) return;
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MarketPalette.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in const ['tin', 'tra', 'brela', 'other'])
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(_documentLabel(type)),
                onTap: () => Navigator.pop(context, type),
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
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _message('market_document_unavailable'.tr);
      return;
    }
    setState(() => _uploadingDocument = true);
    try {
      await MarketService.uploadBusinessDocument(
        uid: profile.uid,
        type: type,
        fileName: file.name,
        bytes: bytes,
      );
      if (mounted) _message('market_document_submitted'.tr);
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) setState(() => _uploadingDocument = false);
    }
  }

  Future<Uint8List> _loadBusinessDocumentBytes(
    MarketBusinessDocument document,
  ) => _documentBytes.putIfAbsent(document.url, () async {
    final bytes = await FirebaseStorage.instance
        .refFromURL(document.url)
        .getData(10 * 1024 * 1024);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('market_document_open_error'.tr);
    }
    return bytes;
  });

  Future<Uint8List?> _loadDocumentThumbnail(MarketBusinessDocument document) =>
      _documentThumbnails.putIfAbsent(document.url, () async {
        try {
          final bytes = await _loadBusinessDocumentBytes(document);
          await for (final page in Printing.raster(
            bytes,
            pages: const [0],
            dpi: 72,
          )) {
            return page.toPng();
          }
        } catch (error) {
          debugPrint('Could not render document thumbnail: $error');
        }
        return null;
      });

  Widget _documentPreview(MarketBusinessDocument document) {
    if (document.contentType != 'application/pdf') {
      return Image.network(
        document.url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(
          Icons.broken_image_outlined,
          color: MarketPalette.textMuted,
        ),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _loadDocumentThumbnail(document),
      builder: (context, snapshot) {
        final thumbnail = snapshot.data;
        if (thumbnail != null) {
          return Image.memory(
            thumbnail,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(
              Icons.picture_as_pdf_outlined,
              color: MarketPalette.blue,
            ),
          );
        }
        return const Icon(
          Icons.picture_as_pdf_outlined,
          color: MarketPalette.blue,
        );
      },
    );
  }

  Future<void> _openBusinessDocument(MarketBusinessDocument document) async {
    final size = MediaQuery.sizeOf(context);
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: MarketPalette.surface,
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: size.height * 0.9,
          ),
          child: SizedBox(
            width: size.width * 0.9,
            height: size.height * 0.82,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_documentLabel(document.type)} · ${document.fileName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MarketPalette.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'close'.tr,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: document.contentType == 'application/pdf'
                        ? FutureBuilder<Uint8List>(
                            future: _loadBusinessDocumentBytes(document),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return Center(
                                  child: Text(
                                    'market_document_open_error'.tr,
                                    style: const TextStyle(
                                      color: MarketPalette.textMuted,
                                    ),
                                  ),
                                );
                              }
                              final bytes = snapshot.data;
                              if (bytes == null) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return PdfPreview(
                                build: (_) async => bytes,
                                canChangePageFormat: false,
                                canChangeOrientation: false,
                                canDebug: false,
                                allowPrinting: false,
                                allowSharing: false,
                                maxPageWidth: 700,
                              );
                            },
                          )
                        : InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 5,
                            child: Center(
                              child: Image.network(
                                document.url,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => Center(
                                  child: Text(
                                    'market_document_open_error'.tr,
                                    style: const TextStyle(
                                      color: MarketPalette.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeProfilePhoto(
    MarketProfile profile, {
    required bool canUseBusinessProfile,
  }) async {
    if (_updatingProfilePhoto) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MarketPalette.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canUseBusinessProfile)
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text('market_use_business_profile_photo'.tr),
                onTap: () => Navigator.pop(context, 'business'),
              ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: Text('market_upload_profile_photo'.tr),
              onTap: () => Navigator.pop(context, 'upload'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _updatingProfilePhoto = true);
    try {
      if (choice == 'business') {
        final businessPhoto = await MarketService.loadBusinessProfilePhoto(
          profile.uid,
        );
        if (businessPhoto == null) {
          throw StateError('market_business_profile_photo_unavailable'.tr);
        }
        final photoUrl = businessPhoto.url.isNotEmpty
            ? businessPhoto.url
            : await MarketService.uploadMarketProfilePhoto(
                uid: profile.uid,
                fileName: 'business-profile.jpg',
                bytes: businessPhoto.bytes!,
              );
        await MarketService.setMarketProfilePhoto(
          uid: profile.uid,
          source: 'business',
          photoUrl: photoUrl,
        );
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.single;
        final bytes = file.bytes;
        if (bytes == null) {
          throw StateError('market_document_unavailable'.tr);
        }
        final photoUrl = await MarketService.uploadMarketProfilePhoto(
          uid: profile.uid,
          fileName: file.name,
          bytes: bytes,
        );
        await MarketService.setMarketProfilePhoto(
          uid: profile.uid,
          source: 'custom',
          photoUrl: photoUrl,
        );
      }
      if (mounted) {
        await _refresh();
        if (mounted) _message('market_profile_photo_saved'.tr);
      }
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) setState(() => _updatingProfilePhoto = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  ButtonStyle get _profileActionStyle => FilledButton.styleFrom(
    backgroundColor: MarketPalette.blue,
    foregroundColor: MarketPalette.canvas,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  Future<void> _editProfile(MarketProfile profile) async {
    final isBusinessProfile =
        AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == widget.uid;
    final name = TextEditingController(text: profile.name);
    final bio = TextEditingController(text: profile.bio);
    final city = TextEditingController(text: profile.city);
    final whatsapp = TextEditingController(text: profile.whatsapp);
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('market_edit_profile'.tr),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isBusinessProfile)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'market_business_name_managed'.tr,
                          style: const TextStyle(
                            color: MarketPalette.textMuted,
                          ),
                        ),
                      ),
                    )
                  else
                    TextFormField(
                      controller: name,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: 'market_display_name'.tr,
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'market_display_name'.tr
                          : null,
                    ),
                  TextFormField(
                    controller: bio,
                    maxLength: 500,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: 'market_bio'.tr),
                  ),
                  TextFormField(
                    controller: city,
                    maxLength: 80,
                    decoration: InputDecoration(labelText: 'market_city'.tr),
                  ),
                  TextFormField(
                    controller: whatsapp,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'market_whatsapp_number'.tr,
                      helperText: 'market_whatsapp_hint'.tr,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: Text('save'.tr),
          ),
        ],
      ),
    );
    if (saved == true) {
      try {
        await MarketService.savePublicProfile(
          uid: widget.uid,
          name: isBusinessProfile ? profile.name : name.text,
          bio: bio.text,
          city: city.text,
          whatsapp: whatsapp.text,
        );
        await _refresh();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }
    name.dispose();
    bio.dispose();
    city.dispose();
    whatsapp.dispose();
  }

  Future<void> _editBusinessProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final canManageBusinessDocuments =
        AccountModeService.current == AccountMode.business &&
        BusinessAccessService.hasBusinessAccess &&
        BusinessAccessService.businessId == widget.uid &&
        BusinessAccessService.can('profile', 'edit');
    final ownProfile =
        FirebaseAuth.instance.currentUser?.uid == widget.uid ||
        canManageBusinessDocuments;

    return Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        appBar: widget.embedded
            ? null
            : AppBar(
                backgroundColor: MarketPalette.canvas,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                leading: ownProfile
                    ? IconButton(
                        tooltip: 'market_create_post'.tr,
                        icon: const Icon(Icons.add_rounded),
                        onPressed: _openComposer,
                      )
                    : null,
                title: FutureBuilder<MarketProfile?>(
                  future: _profile,
                  builder: (context, snapshot) => Text(
                    snapshot.data?.name ?? 'market_profile'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                centerTitle: false,
                actions: [
                  FutureBuilder<MarketProfile?>(
                    future: _profile,
                    builder: (context, snapshot) => IconButton(
                      tooltip: 'market_share_profile'.tr,
                      onPressed: snapshot.data == null
                          ? null
                          : () => _shareProfile(snapshot.data!),
                      icon: const Icon(Icons.share_outlined),
                    ),
                  ),
                ],
              ),
        body: FutureBuilder<MarketProfile?>(
          future: _profile,
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = profileSnapshot.data;
            if (profile == null) {
              return Center(child: Text('market_profile_unavailable'.tr));
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _profileHeader(
                      profile,
                      ownProfile,
                      canManageBusinessDocuments,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _businessDocuments(
                      profile,
                      canManageBusinessDocuments,
                    ),
                  ),
                  // ... (Sehemu ya posts inabaki kama ilivyo) ...
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Text(
                        'market_profile_posts'.tr,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  FutureBuilder<List<MarketPost>>(
                    future: _posts,
                    builder: (context, postsSnapshot) {
                      if (postsSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        );
                      }
                      final posts = postsSnapshot.data ?? const <MarketPost>[];
                      if (posts.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                'market_profile_empty'.tr,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        );
                      }
                      return SliverPadding(
                        padding: const EdgeInsets.all(2),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 2,
                                crossAxisSpacing: 2,
                              ),
                          itemCount: posts.length,
                          itemBuilder: (context, index) =>
                              _ProfilePostTile(post: posts[index]),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _profileHeader(
    MarketProfile profile,
    bool ownProfile,
    bool canEditBusiness,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SEHEMU YA JUU: PICHA NA TAKWIMU
          Row(
            children: [
              // Picha ya Profile
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.grey[800],
                    foregroundImage: profile.photoUrl.isEmpty
                        ? null
                        : NetworkImage(profile.photoUrl),
                    child: profile.photoUrl.isEmpty
                        ? Text(
                            profile.name.trim().isEmpty
                                ? '?'
                                : profile.name.trim()[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 30,
                            ),
                          )
                        : null,
                  ),
                  if (ownProfile)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Material(
                        color: MarketPalette.blue,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'market_change_profile_photo'.tr,
                          onPressed: _updatingProfilePhoto
                              ? null
                              : () => _changeProfilePhoto(
                                  profile,
                                  canUseBusinessProfile: canEditBusiness,
                                ),
                          icon: _updatingProfilePhoto
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: MarketPalette.canvas,
                                  ),
                                )
                              : const Icon(
                                  Icons.photo_camera_outlined,
                                  size: 18,
                                ),
                          color: MarketPalette.canvas,
                          iconSize: 18,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 20),
              // Takwimu
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _stat('market_posts_count'.tr, profile.postsCount),
                    _stat(
                      'market_followers'.tr,
                      _followersCountOverride ?? profile.followersCount,
                      onTap: () => Get.to(
                        () => MarketFollowListPage(
                          uid: profile.uid,
                          followers: true,
                        ),
                      ),
                    ),
                    _stat(
                      'market_following_count'.tr,
                      profile.followingCount,
                      onTap: () => Get.to(
                        () => MarketFollowListPage(
                          uid: profile.uid,
                          followers: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // SEHEMU YA MAELEZO (BIO)
          Row(
            children: [
              Flexible(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MarketPalette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              StreamBuilder<bool>(
                stream: MarketService.watchBusinessVerified(profile.uid),
                builder: (context, snapshot) => snapshot.data == true
                    ? Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Tooltip(
                          message: 'market_business_verified'.tr,
                          child: const Icon(
                            Icons.verified_rounded,
                            color: MarketPalette.blue,
                            size: 18,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (profile.category.isNotEmpty)
            Text(
              'market_cat_${profile.category}'.tr,
              style: const TextStyle(
                color: MarketPalette.textMuted,
                fontSize: 14,
              ),
            ),
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              profile.bio,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ],
          if (profile.city.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              profile.city,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
          if (profile.whatsapp.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _contactProfile(profile),
              child: Row(
                children: [
                  const Icon(
                    Icons.chat_outlined,
                    color: MarketPalette.blue,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'wa.me/${profile.whatsapp}',
                    style: const TextStyle(
                      color: MarketPalette.blue,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          if (ownProfile)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _editProfile(profile),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text('market_edit_profile'.tr),
                    style: _profileActionStyle,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'market_saved_posts'.tr,
                  onPressed: () => Get.to(() => const MarketSavedPostsPage()),
                  style: IconButton.styleFrom(
                    backgroundColor: MarketPalette.surfaceRaised,
                    foregroundColor: MarketPalette.text,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.bookmark_border_rounded),
                ),
                if (canEditBusiness) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'market_insights'.tr,
                    onPressed: () =>
                        Get.to(() => MarketInsightsPage(uid: profile.uid)),
                    style: IconButton.styleFrom(
                      backgroundColor: MarketPalette.surfaceRaised,
                      foregroundColor: MarketPalette.text,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.insights_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'market_edit_business'.tr,
                    onPressed: _editBusinessProfile,
                    style: IconButton.styleFrom(
                      backgroundColor: MarketPalette.surfaceRaised,
                      foregroundColor: MarketPalette.text,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.storefront_outlined),
                  ),
                ],
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: StreamBuilder<bool>(
                    stream: MarketService.watchFollowing(profile.uid),
                    builder: (context, snapshot) {
                      final following =
                          _followingOverride ?? snapshot.data == true;
                      return FilledButton(
                        onPressed: _followBusy
                            ? null
                            : () async {
                                setState(() => _followBusy = true);
                                try {
                                  final isFollowing =
                                      await MarketService.toggleFollow(
                                        profile.uid,
                                      );
                                  if (!mounted) return;
                                  setState(() {
                                    _followingOverride = isFollowing;
                                    final count =
                                        _followersCountOverride ??
                                        profile.followersCount;
                                    _followersCountOverride = isFollowing
                                        ? count + 1
                                        : count > 0
                                        ? count - 1
                                        : 0;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        (isFollowing
                                                ? 'market_follow_success'
                                                : 'market_unfollow_success')
                                            .tr,
                                      ),
                                    ),
                                  );
                                } catch (error) {
                                  if (mounted) _message('$error');
                                } finally {
                                  if (mounted) {
                                    setState(() => _followBusy = false);
                                  }
                                }
                              },
                        style: _profileActionStyle.copyWith(
                          backgroundColor: WidgetStatePropertyAll(
                            following
                                ? MarketPalette.surfaceRaised
                                : MarketPalette.blue,
                          ),
                          foregroundColor: WidgetStatePropertyAll(
                            following
                                ? MarketPalette.text
                                : MarketPalette.canvas,
                          ),
                        ),
                        child: _followBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                following
                                    ? 'market_following'.tr
                                    : 'market_follow'.tr,
                              ),
                      );
                    },
                  ),
                ),
                if (profile.whatsapp.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _contactProfile(profile),
                      icon: const Icon(Icons.chat_outlined),
                      label: Text('market_contact_whatsapp'.tr),
                      style: _profileActionStyle.copyWith(
                        backgroundColor: const WidgetStatePropertyAll(
                          MarketPalette.surfaceRaised,
                        ),
                        foregroundColor: const WidgetStatePropertyAll(
                          MarketPalette.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _businessDocuments(MarketProfile profile, bool canManageDocuments) {
    return StreamBuilder<List<MarketBusinessDocument>>(
      stream: MarketService.watchBusinessDocuments(profile.uid),
      builder: (context, snapshot) {
        final documents = snapshot.data ?? const <MarketBusinessDocument>[];
        if (!canManageDocuments && documents.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'market_business_documents'.tr,
                style: const TextStyle(
                  color: MarketPalette.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'market_documents_not_verified'.tr,
                style: const TextStyle(
                  color: MarketPalette.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: documents.length + (canManageDocuments ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    if (index == documents.length && canManageDocuments) {
                      return _documentBubble(
                        label: _uploadingDocument
                            ? 'market_document_uploading'.tr
                            : 'market_document_add'.tr,
                        icon: _uploadingDocument ? null : Icons.add_rounded,
                        onTap: _uploadingDocument
                            ? null
                            : () => _addBusinessDocument(profile),
                        isAdd: true,
                      );
                    }
                    final document = documents[index];
                    return _documentBubble(
                      label: _documentLabel(document.type),
                      preview: _documentPreview(document),
                      onTap: () => _openBusinessDocument(document),
                      icon: null,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _documentBubble({
    required String label,
    required IconData? icon,
    required VoidCallback? onTap,
    Widget? preview,
    bool isAdd = false,
  }) {
    return SizedBox(
      width: 68,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: isAdd ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isAdd ? null : BorderRadius.circular(8),
                color: MarketPalette.surfaceRaised,
                border: Border.all(
                  color: isAdd ? MarketPalette.border : MarketPalette.blue,
                  width: isAdd ? 1 : 2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child:
                  preview ??
                  (icon == null
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          icon,
                          color: isAdd
                              ? MarketPalette.textMuted
                              : MarketPalette.blue,
                          size: 24,
                        )),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MarketPalette.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int value, {VoidCallback? onTap}) => InkWell(
    onTap: onTap,
    child: Column(
      children: [
        Text(
          NumberFormat.compact().format(value), // Inatumia 5.8K badala ya 5876
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    ),
  );
}

class _ProfilePostTile extends StatelessWidget {
  const _ProfilePostTile({required this.post});

  final MarketPost post;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (post.isTextOnly)
        MarketTextCard(
          text: post.caption,
          seed: post.id,
          bg: post.textBg,
          font: post.textFont,
          fontSize: 11,
          maxLines: 5,
        )
      else if (post.images.isNotEmpty)
        Image.network(
          post.images.first,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: MarketPalette.surfaceRaised,
            child: Icon(Icons.broken_image_outlined),
          ),
        )
      else
        const ColoredBox(color: MarketPalette.surfaceRaised),
      if (post.price != null)
        Positioned(
          left: 4,
          right: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${post.currency} ${NumberFormat.decimalPattern().format(post.price)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
    ],
  );
}
