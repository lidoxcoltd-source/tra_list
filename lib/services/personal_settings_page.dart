import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/invoice/language_controller.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/convert_to_business.dart';
import 'package:tra_list/services/personal_finance_service.dart';
import 'package:tra_list/services/push_service.dart';
import 'package:tra_list/theme/app_theme.dart';

class PersonalSettingsPage extends StatefulWidget {
  const PersonalSettingsPage({super.key});

  @override
  State<PersonalSettingsPage> createState() => _PersonalSettingsPageState();
}

class _PersonalSettingsPageState extends State<PersonalSettingsPage> {
  final _nameController = TextEditingController();
  final _photoController = TextEditingController();
  final _language = Get.isRegistered<LanguageController>()
      ? Get.find<LanguageController>()
      : Get.put(LanguageController());

  String _currency = 'TZS';
  String _dateFormat = 'dd/MM/yyyy';
  bool _notificationsEnabled = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await PersonalFinanceService.loadProfile();
      if (!mounted) return;
      _nameController.text = profile['displayName'] as String;
      _photoController.text = profile['photoUrl'] as String;
      setState(() {
        _currency = profile['currency'] as String;
        _dateFormat = profile['dateFormat'] as String;
        _notificationsEnabled = profile['notificationsEnabled'] as bool;
      });
    } catch (error) {
      if (mounted) _showMessage('personal_load_error'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final displayName = _nameController.text.trim();
    final photoUrl = _photoController.text.trim();
    final photoUri = photoUrl.isEmpty ? null : Uri.tryParse(photoUrl);
    if (displayName.isEmpty || displayName.length > 100) {
      _showMessage('account_full_name_required'.tr);
      return;
    }
    if (photoUrl.isNotEmpty &&
        (photoUri == null ||
            photoUri.scheme != 'https' ||
            photoUri.host.isEmpty)) {
      _showMessage('personal_save_error'.tr);
      return;
    }
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Sign in to save personal settings.');
      await user.updateDisplayName(displayName);
      await user.updatePhotoURL(photoUrl.isEmpty ? null : photoUrl);
      await PersonalFinanceService.saveProfile({
        'displayName': displayName,
        'photoUrl': photoUrl,
        'currency': _currency,
        'dateFormat': _dateFormat,
        'notificationsEnabled': _notificationsEnabled,
      });
      if (mounted) {
        _showMessage('personal_settings_saved'.tr);
      }
    } catch (error) {
      if (mounted) _showMessage('personal_save_error'.tr);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    await PushService.unregister();
    await FirebaseAuth.instance.signOut();
    BusinessAccessService.clear();
    Get.offAllNamed(AppRoutes.login);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _photoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: MjasiColors.background,
      appBar: AppBar(title: Text('personal_settings'.tr)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: const Color(0xFFEAF1FF),
                        backgroundImage: _photoController.text.trim().isEmpty
                            ? null
                            : NetworkImage(_photoController.text.trim()),
                        child: _photoController.text.trim().isEmpty
                            ? const Icon(
                                Icons.person_outline,
                                color: MjasiColors.primaryBlue,
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'personal_display_name'.tr,
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _photoController,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'personal_photo_url'.tr,
                          prefixIcon: const Icon(Icons.image_outlined),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.language),
                      title: Text('language'.tr),
                      trailing: DropdownButton<String>(
                        value: _language.locale.languageCode == 'sw'
                            ? 'sw'
                            : 'en',
                        items: [
                          DropdownMenuItem(
                            value: 'en',
                            child: Text('language_english'.tr),
                          ),
                          DropdownMenuItem(
                            value: 'sw',
                            child: Text('language_swahili'.tr),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          _language.changeLanguage(
                            value,
                            value == 'sw' ? 'TZ' : 'US',
                          );
                          setState(() {});
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: Text('personal_currency'.tr),
                      trailing: DropdownButton<String>(
                        value: _currency,
                        items: const ['TZS', 'KES', 'USD']
                            .map(
                              (currency) => DropdownMenuItem(
                                value: currency,
                                child: Text(currency),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _currency = value);
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: Text('personal_date_format'.tr),
                      trailing: DropdownButton<String>(
                        value: _dateFormat,
                        items: const ['dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd']
                            .map((format) {
                              return DropdownMenuItem(
                                value: format,
                                child: Text(format),
                              );
                            })
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _dateFormat = value);
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_outlined),
                      title: Text('personal_notifications'.tr),
                      value: _notificationsEnabled,
                      onChanged: (value) =>
                          setState(() => _notificationsEnabled = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: Text('personal_privacy'.tr),
                      subtitle: Text('personal_privacy_description'.tr),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text('convert_business_title'.tr),
                      subtitle: Text('convert_business_subtitle'.tr),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final converted = await convertToBusinessAccount(
                          context,
                        );
                        if (converted) Get.offAllNamed(AppRoutes.home);
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: Text(
                        FirebaseAuth.instance.currentUser?.email ?? '',
                      ),
                      subtitle: Text('personal_account'.tr),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text('save'.tr),
              ),
              TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout_rounded),
                label: Text('home_sign_out'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
