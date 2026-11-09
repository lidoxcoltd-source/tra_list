import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/business_intelligence/ai_history.dart';

void main() {
  test('document events round trip and preserve invoice links', () {
    final message = newAiChatMessage(
      'assistant',
      encodeDocumentHistoryEvent('Asha\nMchele', invoiceId: 'inv-123'),
    );
    final event = decodeDocumentHistoryEvent(message)!;
    expect(event.text, 'Asha\nMchele');
    expect(event.invoiceId, 'inv-123');
  });

  test('malformed or unsafe document events are not interpreted as links', () {
    final malformed = newAiChatMessage(
      'assistant',
      'MJASI_DOCUMENT_EVENT_V1:{',
    );
    final unsafe = newAiChatMessage(
      'assistant',
      encodeDocumentHistoryEvent('test', invoiceId: '../other'),
    );
    final userLink = newAiChatMessage(
      'user',
      encodeDocumentHistoryEvent('test', invoiceId: 'invoice'),
    );
    expect(decodeDocumentHistoryEvent(malformed), isNull);
    expect(decodeDocumentHistoryEvent(unsafe), isNull);
    expect(decodeDocumentHistoryEvent(userLink), isNull);
  });

  test(
    'large escaped summaries fit the server limit and disclose truncation',
    () {
      final content = encodeBoundedDocumentHistoryEvent(
        '\\' * 12000,
        truncatedNotice: 'Summary shortened.',
        invoiceId: 'inv-123',
      );
      expect(content.length, lessThanOrEqualTo(12000));
      final event = decodeDocumentHistoryEvent(
        newAiChatMessage('assistant', content),
      )!;
      expect(event.text, endsWith('Summary shortened.'));
      expect(event.invoiceId, 'inv-123');
    },
  );
}
