import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../legal/legal_page.dart';
import '../legal/legal_service.dart';
import 'app_urls_service.dart';

const _brand = Color(0xFF0E5962);

class _Editor {
  _Editor(LegalContent c)
    : titleEn = TextEditingController(text: c.titleEn),
      titleSw = TextEditingController(text: c.titleSw),
      bodyEn = TextEditingController(text: c.bodyEn),
      bodySw = TextEditingController(text: c.bodySw);

  final TextEditingController titleEn;
  final TextEditingController titleSw;
  final TextEditingController bodyEn;
  final TextEditingController bodySw;

  void setFrom(LegalContent c) {
    titleEn.text = c.titleEn;
    titleSw.text = c.titleSw;
    bodyEn.text = c.bodyEn;
    bodySw.text = c.bodySw;
  }

  LegalContent toContent() => LegalContent(
    titleEn: titleEn.text,
    titleSw: titleSw.text,
    bodyEn: bodyEn.text,
    bodySw: bodySw.text,
  );

  void dispose() {
    titleEn.dispose();
    titleSw.dispose();
    bodyEn.dispose();
    bodySw.dispose();
  }
}

class LegalAdminPage extends StatefulWidget {
  const LegalAdminPage({super.key});

  @override
  State<LegalAdminPage> createState() => _LegalAdminPageState();
}

class _LegalAdminPageState extends State<LegalAdminPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final Map<LegalKind, _Editor> _editors = {};
  final Map<LegalKind, bool> _sw = {
    LegalKind.privacy: false,
    LegalKind.terms: false,
  };
  final Map<LegalKind, bool> _preview = {
    LegalKind.privacy: false,
    LegalKind.terms: false,
  };
  bool _loading = true;
  bool _authorized = false;
  bool _saving = false;
  bool _savingContact = false;
  bool _savingUrls = false;
  final _companyCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _websiteUrlCtrl = TextEditingController();
  final _privacyUrlCtrl = TextEditingController();
  final _termsUrlCtrl = TextEditingController();

  bool get _isSw => Get.locale?.languageCode == 'sw';
  String _t(String en, String sw) => _isSw ? sw : en;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _companyCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _websiteUrlCtrl.dispose();
    _privacyUrlCtrl.dispose();
    _termsUrlCtrl.dispose();
    for (final e in _editors.values) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final user = FirebaseAuth.instance.currentUser;
    var ok = false;
    if (user != null) {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('profile')
          .doc('company')
          .get();
      final role = (profile.data()?['role']?.toString() ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      ok = role == 'superadmin';
    }
    if (ok) {
      for (final kind in LegalKind.values) {
        _editors[kind] = _Editor(await LegalService.load(kind));
      }
      final contact = await LegalService.loadContact();
      _companyCtrl.text = contact.companyName;
      _emailCtrl.text = contact.email;
      _phoneCtrl.text = contact.phone;
      _addressCtrl.text = contact.address;
      final urls = await AppUrlsService.load();
      _websiteUrlCtrl.text = urls.website;
      _privacyUrlCtrl.text = urls.privacyPolicy;
      _termsUrlCtrl.text = urls.termsOfService;
    }
    if (!mounted) return;
    setState(() {
      _authorized = ok;
      _loading = false;
    });
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFB34343) : null,
      ),
    );
  }

  Future<void> _save(LegalKind kind) async {
    final content = _editors[kind]!.toContent();
    if (content.titleEn.trim().isEmpty ||
        content.titleSw.trim().isEmpty ||
        content.bodyEn.trim().isEmpty ||
        content.bodySw.trim().isEmpty) {
      _snack(
        _t(
          'Fill the title and content in both English and Kiswahili.',
          'Jaza kichwa na maudhui kwa Kiingereza na Kiswahili.',
        ),
        error: true,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await LegalService.save(kind, content);
      _snack(
        _t(
          'Published. The public page is updated.',
          'Imechapishwa. Ukurasa wa umma umesasishwa.',
        ),
      );
    } catch (error) {
      _snack(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset(LegalKind kind) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Restore default text?', 'Rudisha maandishi ya awali?')),
        content: Text(
          _t(
            'This replaces the editor content with the built-in text. Nothing is published until you press Publish.',
            'Hii inabadilisha maudhui kwenye kihariri na maandishi ya awali. Hakuna kinachochapishwa hadi ubonyeze Chapisha.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Restore', 'Rudisha')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _editors[kind]!.setFrom(LegalDefaults.of(kind)));
    }
  }

  String _url(LegalKind kind) {
    final base = Uri.base;
    if (base.scheme != 'http' && base.scheme != 'https') {
      return kind == LegalKind.privacy
          ? AppUrls.defaults.privacyPolicy
          : AppUrls.defaults.termsOfService;
    }
    return base
        .replace(path: kind.path, query: null, fragment: null)
        .toString();
  }

  Future<void> _copy(LegalKind kind) async {
    await Clipboard.setData(ClipboardData(text: _url(kind)));
    _snack(_t('Link copied: ', 'Link imenakiliwa: ') + _url(kind));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t('Privacy & Terms pages', 'Kurasa za Faragha na Masharti'),
        ),
        bottom: _authorized
            ? TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: _t('Privacy Policy', 'Sera ya Faragha')),
                  Tab(text: _t('Terms & Conditions', 'Masharti')),
                  Tab(text: _t('App links', 'Viungo vya app')),
                ],
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_authorized
          ? Center(
              child: Text(
                _t(
                  'Only a super admin can edit these pages.',
                  'Super admin pekee anaweza kuhariri kurasa hizi.',
                ),
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                for (final kind in LegalKind.values) _editor(kind),
                _appUrlsEditor(),
              ],
            ),
    );
  }

  Future<void> _saveAppUrls() async {
    final urls = AppUrls(
      website: _websiteUrlCtrl.text.trim(),
      privacyPolicy: _privacyUrlCtrl.text.trim(),
      termsOfService: _termsUrlCtrl.text.trim(),
    );
    final error = AppUrlsService.validationError(urls);
    if (error != null) {
      _snack(
        _t(
          'Enter a valid HTTPS address for each link.',
          'Weka anwani sahihi za HTTPS kwa kila kiungo.',
        ),
        error: true,
      );
      return;
    }

    setState(() => _savingUrls = true);
    try {
      await AppUrlsService.save(urls);
      _snack(_t('App links saved.', 'Viungo vya app vimehifadhiwa.'));
    } catch (error) {
      _snack(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _savingUrls = false);
    }
  }

  void _restoreDefaultUrls() {
    _websiteUrlCtrl.text = AppUrls.defaults.website;
    _privacyUrlCtrl.text = AppUrls.defaults.privacyPolicy;
    _termsUrlCtrl.text = AppUrls.defaults.termsOfService;
    setState(() {});
  }

  Widget _appUrlsEditor() {
    InputDecoration decoration(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: const OutlineInputBorder(),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              _t(
                'Manage the links shown on the public App links page. Restore defaults and save to publish the built-in URLs.',
                'Simamia viungo vinavyoonekana kwenye ukurasa wa Viungo vya app. Rudisha defaults na uhifadhi ili kutumia URL za awali.',
              ),
              style: const TextStyle(color: Color(0xFF65738A), height: 1.5),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _websiteUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: decoration(
                _t('Website URL', 'Kiungo cha tovuti'),
                Icons.language_rounded,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _privacyUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: decoration(
                _t('Privacy Policy URL', 'Kiungo cha sera ya faragha'),
                Icons.privacy_tip_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _termsUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: decoration(
                _t('Terms & Conditions URL', 'Kiungo cha vigezo na masharti'),
                Icons.gavel_rounded,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _savingUrls ? null : _restoreDefaultUrls,
                  icon: const Icon(Icons.restore_rounded),
                  label: Text(_t('Restore defaults', 'Rudisha defaults')),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _savingUrls ? null : _saveAppUrls,
                  icon: _savingUrls
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_t('Save links', 'Hifadhi viungo')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveContact() async {
    final email = _emailCtrl.text.trim();
    if (!LegalContact.isValidEmail(email)) {
      _snack(
        _t('Enter a valid email address.', 'Weka barua pepe sahihi.'),
        error: true,
      );
      return;
    }
    setState(() => _savingContact = true);
    try {
      await LegalService.saveContact(
        LegalContact(
          companyName: _companyCtrl.text,
          email: email,
          phone: _phoneCtrl.text,
          address: _addressCtrl.text,
        ),
      );
      _snack(
        _t(
          'Contact details saved. They show on both public pages.',
          'Mawasiliano yamehifadhiwa. Yanaonekana kwenye kurasa zote mbili.',
        ),
      );
    } catch (error) {
      _snack(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _savingContact = false);
    }
  }

  Widget _contactCard() {
    InputDecoration deco(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: const OutlineInputBorder(),
      isDense: true,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E9EA)),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.contact_mail_outlined, color: _brand),
        title: Text(
          _t('Contact details (public)', 'Mawasiliano (ya umma)'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          _t(
            'Shown on the Privacy and Terms pages',
            'Yanaonekana kwenye kurasa za Faragha na Masharti',
          ),
          style: const TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: _companyCtrl,
            decoration: deco(
              _t('Company / legal name', 'Jina la kampuni'),
              Icons.business_rounded,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: deco(_t('Email', 'Barua pepe'), Icons.email_outlined),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: deco(
              _t('Phone number', 'Namba ya simu'),
              Icons.phone_outlined,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _addressCtrl,
            decoration: deco(
              _t('Address', 'Anwani'),
              Icons.location_on_outlined,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _savingContact ? null : _saveContact,
              icon: _savingContact
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_t('Save', 'Hifadhi')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor(LegalKind kind) {
    final e = _editors[kind]!;
    final sw = _sw[kind]!;
    final preview = _preview[kind]!;
    final title = sw ? e.titleSw : e.titleEn;
    final body = sw ? e.bodySw : e.bodyEn;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _contactCard(),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, color: _brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      _url(kind),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: _t('Copy link', 'Nakili link'),
                    onPressed: () => _copy(kind),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton(
                    tooltip: _t('Open page', 'Fungua ukurasa'),
                    onPressed: () => Get.toNamed(kind.path),
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('English')),
                    ButtonSegment(value: true, label: Text('Kiswahili')),
                  ],
                  selected: {sw},
                  onSelectionChanged: (v) =>
                      setState(() => _sw[kind] = v.first),
                ),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(_t('Edit', 'Hariri')),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: Text(_t('Preview', 'Hakiki')),
                    ),
                  ],
                  selected: {preview},
                  onSelectionChanged: (v) =>
                      setState(() => _preview[kind] = v.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (preview)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E9EA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.text,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    LegalBody(body.text),
                  ],
                ),
              )
            else ...[
              TextField(
                controller: title,
                decoration: InputDecoration(
                  labelText: _t('Page title', 'Kichwa cha ukurasa'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                minLines: 18,
                maxLines: null,
                maxLength: LegalService.maxBodyLength,
                style: const TextStyle(fontSize: 14, height: 1.5),
                decoration: InputDecoration(
                  labelText: _t('Content', 'Maudhui'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  'Format: "# Heading" starts a numbered section, "## Sub-heading", "- item" for bullets, "**bold**", "---" divider. A blank line separates paragraphs.',
                  'Muundo: "# Kichwa" huanza sehemu yenye namba, "## Kichwa kidogo", "- kitu" kwa orodha, "**nene**", "---" mstari. Mstari mtupu hutenganisha aya.',
                ),
                style: const TextStyle(color: Color(0xFF75838A), fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _reset(kind),
                  icon: const Icon(Icons.restore_rounded),
                  label: Text(_t('Restore default', 'Rudisha awali')),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _save(kind),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.publish_rounded),
                  label: Text(_t('Publish', 'Chapisha')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
