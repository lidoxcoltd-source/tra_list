import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'super_admin_subscription_service.dart';

class SuperAdminSubscriptionsPage extends StatefulWidget {
  const SuperAdminSubscriptionsPage({super.key});

  @override
  State<SuperAdminSubscriptionsPage> createState() =>
      _SuperAdminSubscriptionsPageState();
}

class _SuperAdminSubscriptionsPageState
    extends State<SuperAdminSubscriptionsPage> {
  static const _ink = Color(0xFF19313A);
  static const _brand = Color(0xFF0E5962);
  static const _canvas = Color(0xFFF5F7F8);

  final _searchController = TextEditingController();
  final _planAmountController = TextEditingController();
  final _planMonthsController = TextEditingController();
  final _planDaysController = TextEditingController();
  final _mobileLogosController = TextEditingController();
  final _cardLogosController = TextEditingController();
  bool _savingLogos = false;
  bool _uploadingLogo = false;
  List<ManagedBusinessSubscription> _businesses = [];
  SubscriptionPlanSettings _plan = SubscriptionPlanSettings.defaults;
  bool _loading = true;
  bool _savingPlan = false;
  TrialSettings _trial = TrialSettings.defaults;
  bool _trialEnabled = true;
  bool _savingTrial = false;
  final TextEditingController _trialDaysController = TextEditingController(
    text: '7',
  );
  String? _error;
  String _statusFilter = 'all';
  final Set<String> _updating = {};

  @override
  void initState() {
    super.initState();
    _planAmountController.text = '${_plan.amount}';
    _setPlanDurationFields(_plan.durationDays);
    _loadBusinesses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _planAmountController.dispose();
    _trialDaysController.dispose();
    _planMonthsController.dispose();
    _planDaysController.dispose();
    _mobileLogosController.dispose();
    _cardLogosController.dispose();
    super.dispose();
  }

  void _setPlanDurationFields(int durationDays) {
    _planMonthsController.text = '${durationDays ~/ 30}';
    _planDaysController.text = '${durationDays % 30}';
  }

  String _formatDuration(int durationDays) {
    return 'duration_months_days'.trParams({
      'months': '${durationDays ~/ 30}',
      'days': '${durationDays % 30}',
    });
  }

  Future<void> _loadBusinesses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final businesses = await SuperAdminSubscriptionService.loadBusinesses();
      final plan = await SuperAdminSubscriptionService.loadPlanSettings();
      final trial = await SuperAdminSubscriptionService.loadTrialSettings();
      if (!mounted) return;
      setState(() {
        _trial = trial;
        _trialEnabled = trial.enabled;
        _trialDaysController.text = '${trial.durationDays}';
        _businesses = businesses;
        _plan = plan;
        _planAmountController.text = '${plan.amount}';
        _mobileLogosController.text = PaymentLogo.toText(plan.mobileLogos);
        _cardLogosController.text = PaymentLogo.toText(plan.cardLogos);
        _setPlanDurationFields(plan.durationDays);
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load users for subscription management: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<ManagedBusinessSubscription> get _filteredBusinesses {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    final expiringBefore = now.add(const Duration(days: 30));
    return _businesses.where((business) {
      final matchesQuery =
          query.isEmpty ||
          business.name.toLowerCase().contains(query) ||
          business.ownerName.toLowerCase().contains(query) ||
          business.email.toLowerCase().contains(query) ||
          business.phone.toLowerCase().contains(query) ||
          business.address.toLowerCase().contains(query) ||
          business.website.toLowerCase().contains(query) ||
          business.taxId.toLowerCase().contains(query) ||
          business.handle.toLowerCase().contains(query) ||
          business.businessId.toLowerCase().contains(query);
      final matchesStatus = switch (_statusFilter) {
        'subscribed' => business.isSubscribed,
        'trial' => !business.isSubscribed && business.isTrial,
        'expiring' =>
          business.isSubscribed &&
              business.expiry != null &&
              business.expiry!.isAfter(now) &&
              !business.expiry!.isAfter(expiringBefore),
        'disabled' => business.isDisabled,
        'unsubscribed' => !business.isSubscribed && !business.isTrial,
        _ => true,
      };
      return matchesQuery && matchesStatus;
    }).toList();
  }

  Widget _uploadButton(TextEditingController target) {
    return IconButton(
      tooltip: 'admin_logos_upload'.tr,
      onPressed: _uploadingLogo ? null : () => _uploadLogo(target),
      icon: _uploadingLogo
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_rounded),
    );
  }

  Future<void> _uploadLogo(TextEditingController target) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    if (bytes.length > 1024 * 1024) {
      Get.snackbar('error'.tr, 'admin_logos_too_big'.tr);
      return;
    }
    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'png';
    final type = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      _ => 'image/jpeg',
    };
    if (type == 'image/svg+xml') {
      Get.snackbar('error'.tr, 'admin_logos_no_svg'.tr);
      return;
    }
    final defaultName = file.name.contains('.')
        ? file.name.substring(0, file.name.lastIndexOf('.'))
        : file.name;
    if (!mounted) return;
    final nameController = TextEditingController(text: defaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('admin_logos_name'.tr),
        content: TextField(controller: nameController, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: Text('admin_logos_add'.tr),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (!mounted || name == null || name.isEmpty) return;
    setState(() => _uploadingLogo = true);
    try {
      final ref = FirebaseStorage.instance.ref(
        'payment_logos/${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await ref.putData(bytes, SettableMetadata(contentType: type));
      final url = await ref.getDownloadURL();
      final current = target.text.trimRight();
      target.text = current.isEmpty
          ? '${name.replaceAll('|', ' ')} | $url'
          : '$current\n${name.replaceAll('|', ' ')} | $url';
    } catch (e) {
      Get.snackbar('error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _saveLogos() async {
    setState(() => _savingLogos = true);
    try {
      await SuperAdminSubscriptionService.savePaymentLogos(
        mobile: PaymentLogo.fromText(_mobileLogosController.text),
        card: PaymentLogo.fromText(_cardLogosController.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('admin_logos_saved'.tr)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: const Color(0xFFB34343),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingLogos = false);
    }
  }

  Future<void> _savePlan() async {
    final amount = int.tryParse(_planAmountController.text.trim());
    final months = int.tryParse(_planMonthsController.text.trim());
    final days = int.tryParse(_planDaysController.text.trim());
    final durationDays = months != null && days != null
        ? months * 30 + days
        : null;
    if (amount == null ||
        amount <= 0 ||
        months == null ||
        months < 0 ||
        days == null ||
        days < 0 ||
        days > 29 ||
        durationDays == null ||
        durationDays <= 0 ||
        durationDays > 3650) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('admin_plan_invalid'.tr)));
      return;
    }

    setState(() => _savingPlan = true);
    try {
      final plan = await SuperAdminSubscriptionService.savePlanSettings(
        amount: amount,
        durationDays: durationDays,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('admin_plan_saved'.tr)));
    } catch (error, stackTrace) {
      debugPrint('Failed to save subscription plan settings: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'admin_subscription_update_error'.trParams({
              'error': error.toString(),
            }),
          ),
          backgroundColor: const Color(0xFFB34343),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingPlan = false);
    }
  }

  Future<void> _changeSubscription(ManagedBusinessSubscription business) async {
    final subscribe = !business.isSubscribed;
    final expiry = subscribe
        ? DateTime.now().add(Duration(days: _plan.durationDays))
        : null;
    final dateLabel = expiry == null ? '' : DateFormat.yMMMd().format(expiry);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          subscribe
              ? 'admin_subscribe_confirm_title'.tr
              : 'admin_unsubscribe_confirm_title'.tr,
        ),
        content: Text(
          subscribe
              ? 'admin_subscribe_confirm_message'.trParams({'date': dateLabel})
              : 'admin_unsubscribe_confirm_message'.trParams({
                  'name': _displayName(business),
                }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: subscribe ? _brand : const Color(0xFFB34343),
            ),
            child: Text(
              subscribe
                  ? 'admin_subscribe_for_days'.trParams({
                      'duration': _formatDuration(_plan.durationDays),
                    })
                  : 'admin_unsubscribe'.tr,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _updating.add(business.businessId));
    try {
      await SuperAdminSubscriptionService.setSubscribed(
        business.businessId,
        subscribed: subscribe,
      );
      if (!mounted) return;
      await _loadBusinesses();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            subscribe
                ? 'admin_subscription_enabled'.tr
                : 'admin_subscription_disabled'.tr,
          ),
          backgroundColor: subscribe
              ? const Color(0xFF237A52)
              : const Color(0xFFB34343),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to change subscription for ${business.businessId}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'admin_subscription_update_error'.trParams({
              'error': error.toString(),
            }),
          ),
          backgroundColor: const Color(0xFFB34343),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating.remove(business.businessId));
    }
  }

  Future<void> _extendSubscription(ManagedBusinessSubscription business) async {
    final durationController = TextEditingController(
      text: '${_plan.durationDays}',
    );
    final formKey = GlobalKey<FormState>();
    final days = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('admin_extend_subscription'.tr),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: durationController,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'admin_extension_days'.tr,
              suffixText: 'days'.tr,
            ),
            validator: (value) {
              final days = int.tryParse(value?.trim() ?? '');
              if (days == null || days <= 0 || days > 3650) {
                return 'admin_extension_days_invalid'.tr;
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(
                  context,
                ).pop(int.parse(durationController.text.trim()));
              }
            },
            child: Text('admin_extend_subscription'.tr),
          ),
        ],
      ),
    );
    durationController.dispose();
    if (days == null || !mounted) return;

    setState(() => _updating.add(business.businessId));
    try {
      final expiry = await SuperAdminSubscriptionService.extendSubscription(
        business.businessId,
        additionalDays: days,
      );
      if (!mounted) return;
      await _loadBusinesses();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'admin_subscription_extended'.trParams({
              'date': DateFormat.yMMMd().format(expiry),
            }),
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to extend subscription for ${business.businessId}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'admin_subscription_update_error'.trParams({
              'error': error.toString(),
            }),
          ),
          backgroundColor: const Color(0xFFB34343),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating.remove(business.businessId));
    }
  }

  Future<void> _changeAccountAccess(
    ManagedBusinessSubscription business,
  ) async {
    final enable = business.isDisabled;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          enable ? 'admin_enable_user_title'.tr : 'admin_disable_user_title'.tr,
        ),
        content: Text(
          enable
              ? 'admin_enable_user_message'.trParams({
                  'name': _displayName(business),
                })
              : 'admin_disable_user_message'.trParams({
                  'name': _displayName(business),
                }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: enable ? _brand : const Color(0xFFB34343),
            ),
            child: Text(
              enable ? 'admin_enable_user'.tr : 'admin_disable_user'.tr,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _updating.add(business.businessId));
    try {
      await SuperAdminSubscriptionService.setAccountEnabled(
        business.businessId,
        enabled: enable,
      );
      if (!mounted) return;
      await _loadBusinesses();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enable
                ? 'admin_user_enabled_success'.tr
                : 'admin_user_disabled_success'.tr,
          ),
          backgroundColor: enable
              ? const Color(0xFF237A52)
              : const Color(0xFFB34343),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to ${enable ? 'enable' : 'disable'} account '
        '${business.businessId}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'admin_subscription_update_error'.trParams({
              'error': error.toString(),
            }),
          ),
          backgroundColor: const Color(0xFFB34343),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating.remove(business.businessId));
    }
  }

  String _displayName(ManagedBusinessSubscription business) =>
      business.name.isNotEmpty
      ? business.name
      : business.ownerName.isNotEmpty
      ? business.ownerName
      : business.businessId;

  @override
  Widget build(BuildContext context) {
    final businesses = _filteredBusinesses;
    final activeCount = _businesses.where((item) => item.isSubscribed).length;
    final trialCount = _businesses
        .where((item) => !item.isSubscribed && item.isTrial)
        .length;
    final now = DateTime.now();
    final expiringBefore = now.add(const Duration(days: 30));
    final expiringCount = _businesses.where((item) {
      final expiry = item.expiry;
      return item.isSubscribed &&
          expiry != null &&
          expiry.isAfter(now) &&
          !expiry.isAfter(expiringBefore);
    }).length;
    final disabledCount = _businesses.where((item) => item.isDisabled).length;

    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        title: Text('admin_subscriptions_title'.tr),
        backgroundColor: _canvas,
        foregroundColor: _ink,
        actions: [
          IconButton(
            tooltip: 'refresh'.tr,
            onPressed: _loading ? null : _loadBusinesses,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadBusinesses,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildOverviewStats(
                        activeCount: activeCount,
                        trialCount: trialCount,
                        expiringCount: expiringCount,
                        disabledCount: disabledCount,
                      ),
                      const SizedBox(height: 8),
                      _buildPlanSettings(),
                      const SizedBox(height: 8),
                      _buildTrialSettings(),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'admin_users_search'.tr,
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 11,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E9EA),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E9EA),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildStatusFilters(),
                    ],
                  ),
                ),
              ),
              ..._buildContent(businesses),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewStats({
    required int activeCount,
    required int trialCount,
    required int expiringCount,
    required int disabledCount,
  }) {
    final stats = [
      (
        Icons.verified_user_outlined,
        'admin_status_subscribed'.tr,
        activeCount,
        const Color(0xFF237A52),
      ),
      (
        Icons.hourglass_top_rounded,
        'admin_status_trial'.tr,
        trialCount,
        const Color(0xFF98620B),
      ),
      (
        Icons.event_busy_outlined,
        'admin_expiring_soon'.tr,
        expiringCount,
        const Color(0xFFB66D22),
      ),
      (
        Icons.person_off_outlined,
        'admin_user_disabled_status'.tr,
        disabledCount,
        const Color(0xFFB34343),
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final stat in stats)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                constraints: const BoxConstraints(minWidth: 112),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E9EA)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(stat.$1, color: stat.$4, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${stat.$3}',
                      style: TextStyle(
                        color: stat.$4,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      stat.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF52656C),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveTrial() async {
    final days = int.tryParse(_trialDaysController.text.trim());
    if (days == null || days < 1 || days > 365) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('admin_trial_invalid'.tr)));
      return;
    }
    setState(() => _savingTrial = true);
    try {
      await SuperAdminSubscriptionService.saveTrialSettings(
        enabled: _trialEnabled,
        durationDays: days,
      );
      if (!mounted) return;
      setState(
        () =>
            _trial = TrialSettings(enabled: _trialEnabled, durationDays: days),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('admin_trial_saved'.tr)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'admin_subscription_update_error'.trParams({
              'error': error.toString(),
            }),
          ),
          backgroundColor: const Color(0xFFB34343),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingTrial = false);
    }
  }

  Future<void> _grantTrial(ManagedBusinessSubscription business) async {
    final controller = TextEditingController(text: '${_trial.durationDays}');
    final days = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('admin_trial_grant'.tr),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'admin_trial_days'.tr),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value >= 1 && value <= 365) {
                Navigator.pop(context, value);
              }
            },
            child: Text('admin_trial_grant'.tr),
          ),
        ],
      ),
    );
    controller.dispose();
    if (days == null) return;
    await _runTrialAction(
      business,
      () => SuperAdminSubscriptionService.grantTrial(
        business.businessId,
        days: days,
      ),
    );
  }

  Future<void> _runTrialAction(
    ManagedBusinessSubscription business,
    Future<void> Function() action,
  ) async {
    setState(() => _updating.add(business.businessId));
    try {
      await action();
      await _loadBusinesses();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('admin_trial_updated'.tr)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'admin_subscription_update_error'.trParams({
              'error': error.toString(),
            }),
          ),
          backgroundColor: const Color(0xFFB34343),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating.remove(business.businessId));
    }
  }

  Widget _buildTrialSettings() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E9EA)),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        visualDensity: VisualDensity.compact,
        leading: const Icon(
          Icons.card_giftcard_outlined,
          color: _brand,
          size: 20,
        ),
        title: Text(
          'admin_trial_settings'.tr,
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          _trial.enabled
              ? 'admin_trial_summary_on'.trParams({
                  'days': '${_trial.durationDays}',
                })
              : 'admin_trial_summary_off'.tr,
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'admin_trial_help'.tr,
              style: const TextStyle(color: Color(0xFF75838A), fontSize: 12),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _trialEnabled,
            onChanged: (value) => setState(() => _trialEnabled = value),
            title: Text('admin_trial_enabled'.tr),
          ),
          TextField(
            controller: _trialDaysController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'admin_trial_days'.tr,
              prefixIcon: const Icon(Icons.calendar_today_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _savingTrial || _loading ? null : _saveTrial,
              icon: _savingTrial
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text('save'.tr),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanSettings() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E9EA)),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        visualDensity: VisualDensity.compact,
        leading: const Icon(
          Icons.price_change_outlined,
          color: _brand,
          size: 20,
        ),
        title: Text(
          'admin_plan_settings'.tr,
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${NumberFormat('#,##0').format(_plan.amount)} TZS · '
          '${_formatDuration(_plan.durationDays)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'admin_plan_existing_unchanged'.tr,
              style: const TextStyle(color: Color(0xFF75838A), fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final amountField = TextField(
                controller: _planAmountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'admin_plan_amount'.tr,
                  prefixIcon: const Icon(Icons.payments_outlined),
                  suffixText: 'TZS',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              );
              final monthsField = TextField(
                controller: _planMonthsController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'admin_plan_months'.tr,
                  prefixIcon: const Icon(Icons.calendar_month_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              );
              final daysField = TextField(
                controller: _planDaysController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'admin_plan_days'.tr,
                  prefixIcon: const Icon(Icons.calendar_today_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              );
              final saveButton = FilledButton.icon(
                onPressed: _savingPlan || _loading ? null : _savePlan,
                icon: _savingPlan
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text('save'.tr),
              );
              if (constraints.maxWidth < 600) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    amountField,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: monthsField),
                        const SizedBox(width: 8),
                        Expanded(child: daysField),
                      ],
                    ),
                    const SizedBox(height: 8),
                    saveButton,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: amountField),
                  const SizedBox(width: 10),
                  Expanded(child: monthsField),
                  const SizedBox(width: 10),
                  Expanded(child: daysField),
                  const SizedBox(width: 10),
                  saveButton,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'admin_logos_help'.tr,
              style: const TextStyle(color: Color(0xFF75838A), fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _mobileLogosController,
            minLines: 2,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: 'admin_logos_mobile'.tr,
              hintText: 'M-Pesa | https://.../mpesa.png',
              prefixIcon: const Icon(Icons.phone_iphone_rounded),
              suffixIcon: _uploadButton(_mobileLogosController),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cardLogosController,
            minLines: 2,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: 'admin_logos_card'.tr,
              hintText: 'Visa | https://.../visa.png',
              prefixIcon: const Icon(Icons.credit_card_rounded),
              suffixIcon: _uploadButton(_cardLogosController),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _savingLogos || _loading ? null : _saveLogos,
              icon: _savingLogos
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text('admin_logos_save'.tr),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilters() {
    const filters = [
      ('all', 'admin_filter_all'),
      ('subscribed', 'admin_filter_subscribed'),
      ('trial', 'admin_filter_trial'),
      ('expiring', 'admin_filter_expiring'),
      ('unsubscribed', 'admin_filter_unsubscribed'),
      ('disabled', 'admin_filter_disabled'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter.$2.tr),
                selected: _statusFilter == filter.$1,
                onSelected: (_) => setState(() => _statusFilter = filter.$1),
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 12),
                padding: const EdgeInsets.symmetric(horizontal: 3),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildContent(List<ManagedBusinessSubscription> businesses) {
    if (_loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    'admin_users_load_error'.trParams({'error': _error!}),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _loadBusinesses,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('categories_retry'.tr),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }
    if (businesses.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _businesses.isEmpty
                    ? 'admin_users_empty'.tr
                    : 'admin_users_search_empty'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF75838A)),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _businessCard(businesses[index]),
            ),
            childCount: businesses.length,
          ),
        ),
      ),
    ];
  }

  Widget _businessCard(ManagedBusinessSubscription business) {
    final active = business.isSubscribed;
    final trial = !active && business.isTrial;
    final color = business.isDisabled
        ? const Color(0xFFB34343)
        : active
        ? const Color(0xFF237A52)
        : trial
        ? const Color(0xFF98620B)
        : const Color(0xFF75838A);
    final status = business.isDisabled
        ? 'admin_user_disabled_status'.tr
        : active
        ? 'admin_status_subscribed'.tr
        : trial
        ? 'admin_status_trial'.tr
        : 'admin_status_unsubscribed'.tr;
    final busy = _updating.contains(business.businessId);
    final hasAdditionalDetails =
        business.address.isNotEmpty ||
        business.website.isNotEmpty ||
        business.taxId.isNotEmpty ||
        business.handle.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E9EA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE7F2F1),
                foregroundColor: _brand,
                child: Text(
                  _displayName(business).isEmpty
                      ? '?'
                      : _displayName(business).substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName(business),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _detailRow(
            Icons.person_outline,
            business.ownerName.isNotEmpty
                ? business.ownerName
                : 'admin_owner_name_not_provided'.tr,
          ),
          _detailRow(
            Icons.email_outlined,
            business.email.isNotEmpty
                ? business.email
                : 'admin_email_not_provided'.tr,
          ),
          if (business.phone.isNotEmpty)
            _detailRow(Icons.phone_outlined, business.phone),
          if (business.amount != null && business.durationDays != null)
            _detailRow(
              Icons.receipt_long_outlined,
              'admin_subscription_plan_snapshot'.trParams({
                'amount': NumberFormat('#,##0').format(business.amount),
                'duration': _formatDuration(business.durationDays!),
              }),
            ),
          if (active && business.expiry != null) ...[
            Text(
              'admin_subscription_expiry'.trParams({
                'date': DateFormat.yMMMd().format(business.expiry!),
              }),
              style: const TextStyle(color: Color(0xFF75838A), fontSize: 11),
            ),
          ],
          if (hasAdditionalDetails)
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                visualDensity: VisualDensity.compact,
                leading: const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Color(0xFF75838A),
                ),
                title: Text(
                  'admin_business_id'.trParams({'id': business.businessId}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF75838A),
                    fontSize: 11,
                  ),
                ),
                children: [
                  if (business.address.isNotEmpty)
                    _detailRow(Icons.location_on_outlined, business.address),
                  if (business.website.isNotEmpty)
                    _detailRow(Icons.language_rounded, business.website),
                  if (business.taxId.isNotEmpty)
                    _detailRow(
                      Icons.badge_outlined,
                      'admin_tax_id'.trParams({'id': business.taxId}),
                    ),
                  if (business.handle.isNotEmpty)
                    _detailRow(
                      Icons.alternate_email_rounded,
                      'admin_handle'.trParams({'handle': business.handle}),
                    ),
                ],
              ),
            )
          else
            _detailRow(
              Icons.info_outline_rounded,
              'admin_business_id'.trParams({'id': business.businessId}),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : () => _changeSubscription(business),
                  style: FilledButton.styleFrom(
                    backgroundColor: active ? const Color(0xFFB34343) : _brand,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          active
                              ? Icons.block_rounded
                              : Icons.verified_user_outlined,
                          size: 16,
                        ),
                  label: Text(
                    active
                        ? 'admin_unsubscribe'.tr
                        : 'admin_subscribe_for_days'.trParams({
                            'duration': _formatDuration(_plan.durationDays),
                          }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                enabled: !busy,
                tooltip: 'home_more'.tr,
                onSelected: (action) {
                  if (action == 'extend') {
                    _extendSubscription(business);
                  } else if (action == 'trial') {
                    _grantTrial(business);
                  } else if (action == 'endtrial') {
                    _runTrialAction(
                      business,
                      () => SuperAdminSubscriptionService.endTrial(
                        business.businessId,
                      ),
                    );
                  } else {
                    _changeAccountAccess(business);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'trial',
                    child: Row(
                      children: [
                        const Icon(Icons.card_giftcard_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text('admin_trial_grant'.tr),
                      ],
                    ),
                  ),
                  if (business.isTrial)
                    PopupMenuItem(
                      value: 'endtrial',
                      child: Row(
                        children: [
                          const Icon(Icons.timer_off_outlined, size: 20),
                          const SizedBox(width: 12),
                          Text('admin_trial_end'.tr),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'extend',
                    child: Row(
                      children: [
                        const Icon(Icons.more_time_rounded, size: 20),
                        const SizedBox(width: 12),
                        Text('admin_extend_subscription'.tr),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'access',
                    child: Row(
                      children: [
                        Icon(
                          business.isDisabled
                              ? Icons.lock_open_rounded
                              : Icons.person_off_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          business.isDisabled
                              ? 'admin_enable_user'.tr
                              : 'admin_disable_user'.tr,
                        ),
                      ],
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF75838A)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF52656C), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
