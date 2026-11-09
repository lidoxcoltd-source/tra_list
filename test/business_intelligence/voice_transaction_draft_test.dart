import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/business_intelligence/voice_transaction_draft.dart';

void main() {
  test('transaction draft preserves the reviewed values for chat', () {
    final draft = VoiceTransactionDraft.fromArguments({
      'type': 'expense',
      'amount': 10000,
      'category': 'Kodi',
      'description': 'Kodi ya duka',
    });
    expect(
      draft.chatCommand,
      'record expense 10000; category: Kodi; description: Kodi ya duka',
    );
  });

  test('invalid and ambiguous inputs cannot be converted into a command', () {
    final valid = <String, dynamic>{
      'type': 'income',
      'amount': 10000,
      'category': 'Mauzo',
      'description': 'Bidhaa',
    };
    for (final fields in [
      {'amount': 10.5},
      {'amount': 0},
      {'amount': double.infinity},
      {'amount': 1000000000001},
      {'type': 'other'},
      {'category': 'Mauzo; description: injected'},
      {'description': 'one\nother'},
      {'extra': 'not supported'},
    ]) {
      expect(
        () => VoiceTransactionDraft.fromArguments({...valid, ...fields}),
        throwsFormatException,
      );
    }
  });
}
