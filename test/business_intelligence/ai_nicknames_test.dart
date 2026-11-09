import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/ai_models.dart';
import 'package:tra_list/business_intelligence/ai_models_ui.dart';
import 'package:tra_list/invoice/app_translations.dart';

void main() {
  test('model nickname round trips without changing the model identifier', () {
    final model = AiModelOption.fromMap({
      'id': 'gpt-4o-mini',
      'provider': 'openai',
      'label': 'GPT-4o mini',
      'nickname': 'Msaidizi',
      'enabled': true,
      'messagePrice': 0,
      'creditCost': 1,
    });
    expect(model.id, 'gpt-4o-mini');
    expect(model.provider, 'openai');
    expect(model.toMap()['nickname'], 'Msaidizi');
  });

  test('nickname labels have generic fallbacks', () {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('sw', 'TZ');
    const model = AiModelOption(
      id: 'gemini-3.8-flash',
      provider: 'gemini',
      label: 'Gemini 3.8 Flash',
      enabled: true,
      messagePrice: 0,
      creditCost: 1,
    );
    expect(isherProviderNickname('gemini', {}), 'Isher AI 2');
    expect(isherProviderNickname('gemini', {'gemini': 'Mwangaza'}), 'Mwangaza');
    expect(isherModelNickname(model, [model]), 'Toleo 3');
  });
}
