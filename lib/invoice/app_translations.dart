import 'package:get/get.dart';
import 'package:tra_list/invoice/translations/en_us.dart';
import 'package:tra_list/invoice/translations/sw_tz.dart';

class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en_US': enUsTranslations,
    'sw_TZ': swTzTranslations,
  };
}
