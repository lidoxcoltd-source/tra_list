#!/usr/bin/env python3
# Rewrites the ProfilePage UI sections with the new professional design.

FILE = r'd:\PROJECTS\FLUTTER\TRA SAMPL\tra_list\lib\services\pages\ProfilePage.dart'

# ── NEW SECTION A: replaces build() + _buildPreviewCard ──────────────────────
NEW_A = r"""  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (phoneC.text.isNotEmpty)
                  Text(
                    phoneC.text,
                    style: TextStyle(
                      color: Colors.grey.shade500,
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
                        valueColor:
                            AlwaysStoppedAnimation<Color>(brandColor),
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
                    onPressed:
                        _currentUploadTask != null ? _cancelUpload : null,
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
            _buildTextField(
              addressC,
              'Address',
              Icons.location_on_outlined,
            ),
            _buildTextField(phoneC, 'Phone', Icons.phone_outlined),
            _buildTextField(emailC, 'Email', Icons.email_outlined),
            _buildTextField(websiteC, 'Website', Icons.language_outlined),
            _buildTextField(taxIdC, 'Tax ID / TIN', Icons.badge_outlined),
            _buildTextField(
              handleC,
              'Social Handle',
              Icons.alternate_email,
            ),
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
            _buildTextField(
              bankC,
              'Bank Name',
              Icons.account_balance_outlined,
            ),
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
        Expanded(child: _buildLangOption('en', 'English', '\U0001f1ec\U0001f1e7')),
        const SizedBox(width: 10),
        Expanded(child: _buildLangOption('sw', 'Kiswahili', '\U0001f1f9\U0001f1ff')),
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
          color:
              selected ? brandColor.withOpacity(0.08) : Colors.grey.shade50,
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
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
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
  }"""

# ── NEW SECTION B: replaces _buildSection + _buildTextField + _buildColorRow ─
NEW_B = r"""  Widget _buildFormCard({
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
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: controller,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade500),
            labelText: label,
            labelStyle:
                TextStyle(fontSize: 14, color: Colors.grey.shade600),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                    style: const TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
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
  }"""

# ── NEW SECTION C: replaces _logoCard ────────────────────────────────────────
NEW_C = r"""  Widget _buildLogoUploadArea() {
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
          onTap: busy ? null : _chooseImage,
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
          color: selected
              ? brandColor.withOpacity(0.09)
              : Colors.grey.shade50,
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
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
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
  }"""

# ── Apply replacements ────────────────────────────────────────────────────────
with open(FILE, 'r', encoding='utf-8') as f:
    src = f.read()

# Section A: build() + _buildPreviewCard  ->  new methods
A_START = '  @override\n  Widget build(BuildContext context) {'
A_END   = '\n\n  Widget _previewBox() {'
a0 = src.find(A_START)
a1 = src.find(A_END)
assert a0 != -1 and a1 != -1, f'Section A markers not found ({a0},{a1})'
src = src[:a0] + NEW_A + A_END + src[a1 + len(A_END):]

# Section B: _buildSection + _buildTextField + _buildColorRow  ->  new versions
B_START = '\n\n  Widget _buildSection({'
B_END   = '\n\n  Future<void> _showColorPicker('
b0 = src.find(B_START)
b1 = src.find(B_END)
assert b0 != -1 and b1 != -1, f'Section B markers not found ({b0},{b1})'
src = src[:b0] + '\n\n  ' + NEW_B + B_END + src[b1 + len(B_END):]

# Section C: _logoCard  ->  new logo methods
C_START = '\n\n  Widget _logoCard(double width) {'
C_END   = '\n\n  Future<void> _chooseImage() async {'
c0 = src.find(C_START)
c1 = src.find(C_END)
assert c0 != -1 and c1 != -1, f'Section C markers not found ({c0},{c1})'
src = src[:c0] + '\n\n  ' + NEW_C + C_END + src[c1 + len(C_END):]

with open(FILE, 'w', encoding='utf-8') as f:
    f.write(src)

print('Done. File rewritten successfully.')
