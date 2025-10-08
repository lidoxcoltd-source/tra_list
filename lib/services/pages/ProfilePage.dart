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
import 'package:tra_list/services/profile_service.dart';

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
  Uint8List? pickedBytes;
  String? pickedExt;

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
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Company Profile'),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accentColor, brandColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : _save,
        icon: busy || uploadProgress != null
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_alt),
        label: Text(
          busy
              ? 'Saving...'
              : (uploadProgress != null ? 'Uploading...' : 'Save Changes'),
        ),
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 80),
              children: [
                _buildPreviewCard(w),
                const SizedBox(height: 12),
                _buildSection(
                  icon: Icons.business,
                  title: 'Company Details',
                  children: [
                    _buildTextField(
                      nameC,
                      'Company Name',
                      Icons.label_important,
                    ),
                    _buildTextField(addressC, 'Address', Icons.location_on),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(phoneC, 'Phone', Icons.phone),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: phoneC.text),
                          ),
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
                    _buildTextField(emailC, 'Email', Icons.email),
                    _buildTextField(websiteC, 'Website', Icons.language),
                    _buildTextField(taxIdC, 'Tax ID', Icons.badge),
                    _buildTextField(
                      handleC,
                      'Social Handle',
                      Icons.alternate_email,
                    ),
                  ],
                ),
                _buildSection(
                  icon: Icons.payment,
                  title: 'Payment Details',
                  children: [
                    _buildTextField(
                      beneficiaryC,
                      'Beneficiary Name',
                      Icons.person,
                    ),
                    _buildTextField(bankC, 'Bank Name', Icons.account_balance),
                    _buildTextField(accountC, 'Account Number', Icons.pin),
                    _buildTextField(swiftC, 'SWIFT/BIC Code', Icons.code),
                    _buildTextField(
                      paymentMethodC,
                      'Default Payment Method',
                      Icons.credit_card,
                    ),
                  ],
                ),
                _buildSection(
                  icon: Icons.color_lens,
                  title: 'Branding & Theming',
                  children: [
                    _buildColorRow(
                      'Brand Color',
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
                    const SizedBox(height: 12),
                    _logoCard(w),
                    if (uploadProgress != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: uploadProgress! <= 1
                                  ? uploadProgress
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${(uploadProgress! * 100).toStringAsFixed(0)}%',
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Cancel upload',
                            onPressed: _currentUploadTask != null
                                ? _cancelUpload
                                : null,
                            icon: const Icon(Icons.cancel),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildPreviewCard(double width) {
    final boxH = (width * 0.28).clamp(120, 200).toDouble();
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live Preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(width: boxH, height: boxH, child: _previewBox()),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (nameC.text.isNotEmpty)
                        Text(
                          nameC.text,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: brandColor,
                          ),
                        ),
                      if (addressC.text.isNotEmpty) Text(addressC.text),
                      if (phoneC.text.isNotEmpty) Text('Tel: ${phoneC.text}'),
                      if (emailC.text.isNotEmpty) Text(emailC.text),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewBox() {
    final radius = BorderRadius.circular(10);
    return InkWell(
      onTap: () {
        if (pickedBytes != null || (logoUrl ?? '').isNotEmpty)
          _showFullScreenPreview();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: radius,
        ),
        padding: const EdgeInsets.all(8),
        child: ClipRRect(borderRadius: radius, child: _previewWidget()),
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

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) => Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: ExpansionTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: children),
        ),
      ],
    ),
  );

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 20),
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _buildColorRow(
    String label,
    Color color,
    ValueChanged<Color> onColorSelected,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: () => _showColorPicker(color, onColorSelected),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit, size: 18),
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

  Widget _logoCard(double width) {
    final boxH = (width * 0.4).clamp(140, 260).toDouble();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: boxH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _previewWidget(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: (busy || uploadProgress != null)
                    ? null
                    : _chooseImage,
                icon: const Icon(Icons.add_a_photo),
                label: const Text('Choose'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: pickedBytes != null
                    ? () => setState(() => pickedBytes = null)
                    : null,
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
              const SizedBox(width: 8),
              if ((logoUrl ?? '').isNotEmpty)
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: logoUrl ?? '')),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy URL'),
                ),
              const Spacer(),
              if (!kIsWeb && (logoUrl ?? '').isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final fixed =
                        await ProfileService.repairLogoUrlForCurrentUser();
                    if (fixed != null && mounted)
                      setState(() => logoUrl = fixed.trim());
                  },
                  icon: const Icon(Icons.build_circle_outlined),
                  label: const Text('Repair URL'),
                ),
            ],
          ),
        ],
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

  Future<void> _save() async {
    if (busy) return;
    try {
      setState(() => busy = true);
      String? newUrl = logoUrl;

      if (pickedBytes != null) {
        newUrl = await _uploadBytes(pickedBytes!, pickedExt);
        if (mounted) setState(() => pickedBytes = null);
      }

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
        if (newUrl != null) 'logoUrl': newUrl,
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
