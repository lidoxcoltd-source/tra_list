import 'dart:io';

import 'voice_signaling_socket_base.dart';

Future<VoiceSignalingSocket> connectVoiceSignalingSocket(Uri url) async =>
    _IoVoiceSignalingSocket(await WebSocket.connect(url.toString()));

class _IoVoiceSignalingSocket implements VoiceSignalingSocket {
  _IoVoiceSignalingSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<dynamic> get messages => _socket;

  @override
  bool get isOpen => _socket.readyState == WebSocket.open;

  @override
  void add(String message) => _socket.add(message);

  @override
  Future<void> close() async {
    await _socket.close();
  }
}
