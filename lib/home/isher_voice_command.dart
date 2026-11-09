enum IsherVoiceIntent { wake, chat, voice }

class IsherVoiceCommand {
  static final _wakeWords = {'isher', 'isha', 'aisha'};
  static final _chatWords = {
    'chat',
    'kuchat',
    'andika',
    'kuandika',
    'ujumbe',
    'type',
    'text',
  };
  static final _voiceWords = {
    'call',
    'voice',
    'sauti',
    'simu',
    'ongea',
    'zungumza',
    'piga',
    'kupiga',
  };

  static Set<String> _words(String phrase) => phrase
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toSet();

  static bool isWakePhrase(String phrase) =>
      _words(phrase).intersection(_wakeWords).isNotEmpty;

  static IsherVoiceIntent? parseChoice(String phrase) {
    final words = _words(phrase);
    if (words.intersection(_chatWords).isNotEmpty) return IsherVoiceIntent.chat;
    if (words.intersection(_voiceWords).isNotEmpty) {
      return IsherVoiceIntent.voice;
    }
    return null;
  }
}
