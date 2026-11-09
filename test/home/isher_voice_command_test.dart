import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/home/isher_voice_command.dart';

void main() {
  group('Isher wake phrase', () {
    test('recognizes Isher and Aisha as separate spoken words', () {
      expect(IsherVoiceCommand.isWakePhrase('Hello Isher'), isTrue);
      expect(IsherVoiceCommand.isWakePhrase('Aisha'), isTrue);
      expect(IsherVoiceCommand.isWakePhrase('Isha, habari'), isTrue);
      expect(IsherVoiceCommand.isWakePhrase('business'), isFalse);
    });
  });

  group('Isher voice choice', () {
    test('recognizes chat and typing choices', () {
      expect(IsherVoiceCommand.parseChoice('Nataka kuchat'), IsherVoiceIntent.chat);
      expect(IsherVoiceCommand.parseChoice('andika ujumbe'), IsherVoiceIntent.chat);
      expect(IsherVoiceCommand.parseChoice('Chat'), IsherVoiceIntent.chat);
    });

    test('recognizes call and voice choices', () {
      expect(IsherVoiceCommand.parseChoice('kupiga simu'), IsherVoiceIntent.voice);
      expect(IsherVoiceCommand.parseChoice('nataka sauti'), IsherVoiceIntent.voice);
      expect(IsherVoiceCommand.parseChoice('call Isher'), IsherVoiceIntent.voice);
    });

    test('asks again for an unrecognized choice', () {
      expect(IsherVoiceCommand.parseChoice('sales report'), isNull);
    });
  });
}
