import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/invoice/language_controller.dart';

/// Compact EN/SW language picker for screens shown before sign-in.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key, this.color = Colors.black87});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<LanguageController>()
        ? Get.find<LanguageController>()
        : Get.put(LanguageController());

    return GetBuilder<LanguageController>(
      builder: (_) {
        final code = (Get.locale?.languageCode ?? 'en').toLowerCase();
        return PopupMenuButton<String>(
          onSelected: (value) =>
              controller.changeLanguage(value, value == 'sw' ? 'TZ' : 'US'),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: 'en',
              checked: code == 'en',
              child: Text('language_english'.tr),
            ),
            CheckedPopupMenuItem(
              value: 'sw',
              checked: code == 'sw',
              child: Text('language_swahili'.tr),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language_rounded, color: color, size: 20),
                const SizedBox(width: 5),
                Text(
                  code == 'sw' ? 'SW' : 'EN',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Icon(Icons.arrow_drop_down_rounded, color: color),
              ],
            ),
          ),
        );
      },
    );
  }
}
