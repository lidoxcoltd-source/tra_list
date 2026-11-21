import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:tra_list/jobs/models/debt.dart';
import 'package:tra_list/jobs/services/debt_service.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/profile_service.dart';

Future<bool?> showVoiceDebtEntryDialog(BuildContext context) =>
    showDialog<bool>(
      context: context,
      builder: (context) => const VoiceDebtEntryDialog(),
    );

class VoiceDebtEntryDialog extends StatefulWidget {
  const VoiceDebtEntryDialog({super.key});

  @override
  State<VoiceDebtEntryDialog> createState() => _VoiceDebtEntryDialogState();
}

class _VoiceDebtEntryDialogState extends State<VoiceDebtEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _speech = SpeechToText();
  DebtDirection _direction = DebtDirection.customerOwesShop;
  String _reason = 'advance';
  DateTime? _dueDate;
  TextEditingController? _listeningController;
  String? _speechError;
  String? _saveError;
  String? _shopLoadWarning;
  String _shopNickname = '';
  List<String> _shops = const [];
  bool _loadingShop = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadShops());
  }

  @override
  void dispose() {
    unawaited(_speech.cancel());
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadShops() async {
    if (!BusinessAccessService.isOwner.value) {
      final shop = DebtService.assignedShop;
      if (mounted) {
        setState(() {
          _shops = shop.isEmpty ? const [] : [shop];
          _shopNickname = shop;
          _loadingShop = false;
        });
      }
      return;
    }

    var fallbackShop = BusinessAccessService.shopNickname.value.trim();
    try {
      final profile = await ProfileService.loadOrCreate();
      final profileShop = profile['shopNickname']?.toString().trim() ?? '';
      final ownShop = profileShop.isNotEmpty
          ? profileShop
          : (profile['name']?.toString().trim().isNotEmpty == true
                ? profile['name'].toString().trim()
                : fallbackShop);
      if (ownShop.isNotEmpty) fallbackShop = ownShop;
      final shops = <String>{if (ownShop.isNotEmpty) ownShop};
      final memberships = await FirebaseFirestore.instance
          .collection('employeeMemberships')
          .where('businessUid', isEqualTo: BusinessAccessService.businessId)
          .get()
          .timeout(const Duration(seconds: 15));
      for (final membership in memberships.docs) {
        final shop = membership.data()['shopNickname']?.toString().trim() ?? '';
        if (shop.isNotEmpty) shops.add(shop);
      }
      final sortedShops = shops.toList()..sort();
      if (!mounted) return;
      setState(() {
        _shops = sortedShops;
        _shopNickname = ownShop.isNotEmpty
            ? ownShop
            : (sortedShops.isEmpty ? '' : sortedShops.first);
        _loadingShop = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Voice debt shop lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _shops = fallbackShop.isEmpty ? const [] : [fallbackShop];
        _shopNickname = fallbackShop;
        _shopLoadWarning = 'debt_shops_load_error'.tr;
        _loadingShop = false;
      });
    }
  }

  Future<void> _listenFor(TextEditingController controller) async {
    if (_speech.isListening && _listeningController == controller) {
      await _speech.stop();
      if (mounted) setState(() => _listeningController = null);
      return;
    }
    if (_speech.isListening) await _speech.stop();
    if (mounted) {
      setState(() {
        _listeningController = controller;
        _speechError = null;
      });
    }
    try {
      final available = await _speech.initialize(
        onError: (error) {
          debugPrint('On-device debt dictation failed: ${error.errorMsg}');
          if (mounted) {
            setState(() {
              _listeningController = null;
              _speechError = 'bi_voice_debt_local_unavailable'.tr;
            });
          }
        },
        onStatus: (status) {
          if (status != SpeechToText.listeningStatus &&
              mounted &&
              _listeningController != null) {
            setState(() => _listeningController = null);
          }
        },
      );
      if (!available) {
        throw StateError('On-device speech recognition unavailable');
      }
      if (!mounted) return;
      final locale = Get.locale?.languageCode == 'sw' ? 'sw_TZ' : 'en_US';
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          cancelOnError: true,
          listenFor: const Duration(seconds: 30),
          listenMode: ListenMode.dictation,
          localeId: locale,
          onDevice: true,
          partialResults: true,
          pauseFor: const Duration(seconds: 4),
        ),
        onResult: (SpeechRecognitionResult result) {
          if (!mounted || _listeningController != controller) return;
          controller.value = TextEditingValue(
            text: result.recognizedWords.trim(),
            selection: TextSelection.collapsed(
              offset: result.recognizedWords.trim().length,
            ),
          );
          if (result.finalResult) {
            setState(() => _listeningController = null);
          }
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Could not start on-device debt dictation: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _listeningController = null;
          _speechError = 'bi_voice_debt_local_unavailable'.tr;
        });
      }
    }
  }

  double? _amount() {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );
    if (amount == null ||
        !amount.isFinite ||
        amount <= 0) {
      return null;
    }
    return amount;
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
    if (date != null && mounted) setState(() => _dueDate = date);
  }

  Future<void> _save() async {
    if (_listeningController != null ||
        !_formKey.currentState!.validate() ||
        _shopNickname.isEmpty ||
        !BusinessAccessService.can('jobs', 'create')) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final debt = Debt(
        debtorName: _nameController.text.trim(),
        phone: '',
        direction: _direction,
        reason: _reason,
        notes: _notesController.text.trim(),
        principal: _amount()!,
        dueDate: _dueDate,
        shopNickname: _shopNickname,
      );
      await DebtService.save(debt, isEditing: false);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Voice debt save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _saveError = 'bi_voice_debt_save_error'.tr);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(
    String label,
    TextEditingController controller,
  ) => InputDecoration(
    labelText: label,
    suffixIcon: IconButton(
      tooltip: _listeningController == controller
          ? 'bi_voice_debt_listening'.tr
          : 'bi_voice_debt_speak_field'.tr,
      onPressed: _saving ? null : () => _listenFor(controller),
      icon: Icon(
        _listeningController == controller
            ? Icons.stop_circle_outlined
            : Icons.mic_none_rounded,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _listeningController != null;
    return AlertDialog(
      title: Text('debt_add_title'.tr),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'bi_voice_debt_local_privacy'.tr,
                        style: const TextStyle(fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('bi_voice_debt_review_note'.tr),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoration('debt_person_name'.tr, _nameController),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'required_field'.tr
                      : null,
                ),
                TextFormField(
                  controller: _amountController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _decoration(
                    'debt_original_amount'.tr,
                    _amountController,
                  ).copyWith(
                    helperText: 'bi_voice_debt_amount_hint'.tr,
                  ),
                  validator: (_) =>
                      _amount() == null
                      ? 'bi_voice_debt_amount_invalid'.tr
                      : null,
                ),
                DropdownButtonFormField<DebtDirection>(
                  initialValue: _direction,
                  decoration: InputDecoration(labelText: 'debt_direction'.tr),
                  items: [
                    DropdownMenuItem(
                      value: DebtDirection.customerOwesShop,
                      child: Text('debt_customer_owes'.tr),
                    ),
                    DropdownMenuItem(
                      value: DebtDirection.shopOwesOther,
                      child: Text('debt_shop_owes'.tr),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _direction = value);
                        },
                ),
                DropdownButtonFormField<String>(
                  initialValue: _reason,
                  decoration: InputDecoration(labelText: 'debt_reason'.tr),
                  items: [
                    for (final reason in const [
                      'advance',
                      'goods_credit',
                      'service',
                      'other',
                    ])
                      DropdownMenuItem(
                        value: reason,
                        child: Text('debt_reason_$reason'.tr),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _reason = value);
                        },
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _pickDueDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    _dueDate == null
                        ? 'debt_due_date_optional'.tr
                        : '${'debt_due_date_optional'.tr}: ${_dueDate!.toIso8601String().substring(0, 10)}',
                  ),
                ),
                TextFormField(
                  controller: _notesController,
                  enabled: !_saving,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: _decoration(
                    'debt_notes_optional'.tr,
                    _notesController,
                  ),
                ),
                if (_loadingShop)
                  Text('debt_shops_loading'.tr)
                else if (_shops.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: _shopNickname,
                    decoration: InputDecoration(
                      labelText: 'transactions_filter_shop'.tr,
                    ),
                    items: [
                      for (final shop in _shops)
                        DropdownMenuItem(value: shop, child: Text(shop)),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _shopNickname = value);
                            }
                          },
                  )
                else if (_shopNickname.isNotEmpty)
                  Text('${'transactions_filter_shop'.tr}: $_shopNickname')
                else
                  Text('debt_shop_required'.tr),
                if (_shopLoadWarning != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _shopLoadWarning!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_speechError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _speechError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_saveError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _saveError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: Text('cancel'.tr),
        ),
        FilledButton.icon(
          onPressed: busy || _loadingShop || _shopNickname.isEmpty
              ? null
              : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text('debt_save_action'.tr),
        ),
      ],
    );
  }
}
