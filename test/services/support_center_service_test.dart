import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/services/support_center_service.dart';

void main() {
  group('SupportCenterConfig', () {
    test('loads a WhatsApp number and valid FAQ entries', () {
      final config = SupportCenterConfig.fromMap({
        'whatsappNumber': '255712345678',
        'faqs': [
          {
            'question': 'How do I install?',
            'answer': 'Open the download page.',
          },
          {'question': '', 'answer': 'Invalid question is ignored.'},
          'invalid faq data',
        ],
      });

      expect(config.whatsappNumber, '255712345678');
      expect(config.faqs, hasLength(1));
      expect(config.faqs.single.question, 'How do I install?');
      expect(config.faqs.single.answer, 'Open the download page.');
    });

    test('returns an empty configuration for missing or malformed data', () {
      expect(SupportCenterConfig.fromMap(null).faqs, isEmpty);
      expect(SupportCenterConfig.fromMap({'faqs': 'invalid'}).faqs, isEmpty);
    });
  });
}
