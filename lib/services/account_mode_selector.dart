import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/account_mode_service.dart';

class AccountModeSelector extends StatelessWidget {
  const AccountModeSelector({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  final AccountMode mode;
  final ValueChanged<AccountMode> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<AccountMode>(
    segments: [
      ButtonSegment(
        value: AccountMode.personal,
        icon: const Icon(Icons.person_outline),
        label: Text('mode_personal'.tr),
      ),
      ButtonSegment(
        value: AccountMode.business,
        icon: const Icon(Icons.storefront_outlined),
        label: Text('mode_business'.tr),
      ),
    ],
    selected: {mode},
    onSelectionChanged: (selection) => onChanged(selection.first),
  );
}
