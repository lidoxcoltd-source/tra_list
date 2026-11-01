import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/business_account_service.dart';
import 'package:tra_list/theme/app_theme.dart';

class BusinessSetupPage extends StatefulWidget {
  const BusinessSetupPage({super.key});

  @override
  State<BusinessSetupPage> createState() => _BusinessSetupPageState();
}

class _BusinessSetupPageState extends State<BusinessSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _phone = TextEditingController();
  final _invitationCode = TextEditingController();
  bool _saving = false;

  Future<void> _retryBusinessAccess() async {
    try {
      await BusinessAccessService.initializeForCurrentUser();
      if (BusinessAccessService.hasBusinessAccess && mounted) {
        Get.offAllNamed(AppRoutes.home);
      } else if (mounted) {
        setState(() {});
      }
    } catch (error, stackTrace) {
      debugPrint('Could not retry business access: $error');
      debugPrintStack(stackTrace: stackTrace);
      BusinessAccessService.initializationError = error.toString();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _businessName.dispose();
    _phone.dispose();
    _invitationCode.dispose();
    super.dispose();
  }

  Future<void> _createBusiness() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final businessId = await BusinessAccountService.createBusiness(
        name: _businessName.text,
        phone: _phone.text,
      );
      await BusinessAccessService.initializeForCurrentUser();
      await BusinessAccessService.selectBusiness(businessId);
      if (mounted) Get.offAllNamed(AppRoutes.home);
    } catch (error) {
      debugPrint('Business setup failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'business_setup_failed'.tr} $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _claimInvitation() async {
    if (_invitationCode.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw StateError('Sign in before joining a business.');
      }
      await currentUser.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser == null) {
        throw StateError('Sign in before joining a business.');
      }
      if (!refreshedUser.emailVerified) {
        await refreshedUser.sendEmailVerification();
        throw StateError('business_invite_verify_email'.tr);
      }
      final businessId = await BusinessAccountService.claimInvitation(
        _invitationCode.text,
      );
      await BusinessAccessService.initializeForCurrentUser();
      await BusinessAccessService.selectBusiness(businessId);
      if (mounted) Get.offAllNamed(AppRoutes.home);
    } catch (error) {
      debugPrint('Business invitation claim failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'business_invite_claim_failed'.tr} $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MjasiColors.background,
    appBar: AppBar(title: Text('business_setup_title'.tr)),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              _hero(),
              const SizedBox(height: MjasiSpacing.lg),
              Card(
                elevation: 0,
                color: MjasiColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(MjasiRadius.lg),
                  side: const BorderSide(color: MjasiColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (BusinessAccessService.initializationError !=
                            null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: MjasiColors.warningBackground,
                              borderRadius: BorderRadius.circular(
                                MjasiRadius.sm,
                              ),
                              border: Border.all(
                                color: MjasiColors.warning.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'business_access_restore_failed'.tr,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: MjasiColors.textPrimary,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _saving
                                      ? null
                                      : _retryBusinessAccess,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text('business_access_retry'.tr),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        _sectionTitle(
                          Icons.add_business_outlined,
                          'business_setup_create'.tr,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _businessName,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'account_business_name'.tr,
                            prefixIcon: const Icon(Icons.storefront_outlined),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'account_business_name_required'.tr
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'account_phone_optional'.tr,
                            prefixIcon: const Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: MjasiColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                MjasiRadius.sm,
                              ),
                            ),
                          ),
                          onPressed: _saving ? null : _createBusiness,
                          child: _saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text('business_setup_create'.tr),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                Get.locale?.languageCode == 'sw' ? 'AU' : 'OR',
                                style: const TextStyle(
                                  color: MjasiColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _sectionTitle(
                          Icons.group_add_outlined,
                          'business_setup_join_title'.tr,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'business_setup_join_description'.tr,
                          style: const TextStyle(
                            color: MjasiColors.textSecondary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _invitationCode,
                          textCapitalization: TextCapitalization.none,
                          decoration: InputDecoration(
                            labelText: 'business_invitation_code'.tr,
                            prefixIcon: const Icon(
                              Icons.confirmation_number_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            foregroundColor: MjasiColors.primaryBlue,
                            side: const BorderSide(
                              color: MjasiColors.primaryBlue,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                MjasiRadius.sm,
                              ),
                            ),
                          ),
                          onPressed: _saving ? null : _claimInvitation,
                          icon: const Icon(Icons.group_add_outlined),
                          label: Text('business_invitation_join'.tr),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [MjasiColors.primaryNavy, MjasiColors.primaryBlue],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(MjasiRadius.lg),
    ),
    child: Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.storefront_rounded,
            size: 32,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'business_setup_title'.tr,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'business_setup_description'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 13.5,
            height: 1.35,
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(IconData icon, String text) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: MjasiColors.lightBlue,
          borderRadius: BorderRadius.circular(MjasiRadius.sm),
        ),
        child: Icon(icon, size: 18, color: MjasiColors.primaryBlue),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MjasiColors.textPrimary,
          ),
        ),
      ),
    ],
  );
}
