import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/home/isher_speech_error.dart';

void main() {
  group('Isher speech error recovery', () {
    test('retries Android timeout and recognition service errors', () {
      expect(isRetryableIsherSpeechError('error_speech_timeout'), isTrue);
      expect(isRetryableIsherSpeechError('error_no_match'), isTrue);
      expect(isRetryableIsherSpeechError('error_busy'), isTrue);
      expect(isRetryableIsherSpeechError('error_network_timeout'), isTrue);
    });

    test('does not retry permission or unsupported-language errors', () {
      expect(isRetryableIsherSpeechError('error_permission'), isFalse);
      expect(
        isRetryableIsherSpeechError('error_language_not_supported'),
        isFalse,
      );
      expect(
        isRetryableIsherSpeechError('error_language_unavailable'),
        isFalse,
      );
    });

    test('matches retryable error identifiers case-insensitively', () {
      expect(isRetryableIsherSpeechError('ERROR_BUSY'), isTrue);
    });
  });
}
