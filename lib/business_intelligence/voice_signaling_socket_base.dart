abstract interface class VoiceSignalingSocket {
  Stream<dynamic> get messages;
  bool get isOpen;

  void add(String message);
  Future<void> close();
}
