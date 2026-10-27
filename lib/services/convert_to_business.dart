import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'account_mode_service.dart';
import 'business_access_service.dart';
import 'profile_service.dart';

/// Business phone numbers are mandatory and must be reachable on WhatsApp.
String? validateBusinessWhatsapp(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'[\s\-()+]'), '');
  if (digits.isEmpty) return 'business_whatsapp_required'.tr;
  if (!RegExp(r'^\d{9,15}$').hasMatch(digits)) {
    return 'business_whatsapp_invalid'.tr;
  }
  return null;
}

/// Asks for business details and converts the signed-in personal account to a
/// business account. Returns true when the conversion succeeded.
Future<bool> convertToBusinessAccount(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var saving = false;
  String? error;

  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        Future<void> submit() async {
          if (!formKey.currentState!.validate()) return;
          setDialogState(() {
            saving = true;
            error = null;
          });
          try {
            await ProfileService.createForRegistration(
              ownerName: user.displayName?.trim() ?? '',
              businessName: nameController.text.trim(),
              email: user.email ?? '',
              phone: phoneController.text.trim(),
            );
            await AccountModeService.setForCurrentUser(AccountMode.business);
            await BusinessAccessService.initializeForCurrentUser();
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          } catch (e) {
            setDialogState(() {
              saving = false;
              error = '$e';
            });
          }
        }

        return AlertDialog(
          title: Text('convert_business_title'.tr),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('convert_business_body'.tr),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'convert_business_name'.tr,
                      prefixIcon: const Icon(Icons.storefront_outlined),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'convert_business_name_required'.tr
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'convert_business_phone'.tr,
                      helperText: 'business_whatsapp_hint'.tr,
                      prefixIcon: const Icon(Icons.chat_outlined),
                    ),
                    validator: validateBusinessWhatsapp,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: saving ? null : submit,
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('convert_business_action'.tr),
            ),
          ],
        );
      },
    ),
  );
  nameController.dispose();
  phoneController.dispose();
  return done == true;
}
