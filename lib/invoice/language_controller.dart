import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class LanguageController extends GetxController {
  final _box = GetStorage();
  final _key = 'locale';

  Locale get locale => _loadLocaleFromBox();

  Locale _loadLocaleFromBox() {
    final localeString = _box.read(_key) as String?;
    if (localeString == null) return const Locale('en', 'US');
    final parts = localeString.split('_');
    return Locale(parts[0], parts[1]);
  }

  void changeLanguage(String langCode, String countryCode) {
    final locale = Locale(langCode, countryCode);
    Get.updateLocale(locale);
    _box.write(_key, '${langCode}_$countryCode');
    update(); // Notifies listeners
  }
}
