import 'dart:async';
import 'dart:js_interop';

import 'voice_signaling_socket_base.dart';
import 'package:web/web.dart' as web;

Future<VoiceSignalingSocket> connectVoiceSignalingSocket(Uri url) async {
  final socket = web.WebSocket(url.toString());
  final connection = Completer<void>();
  final messages = StreamController<dynamic>();

  socket.onmessage = ((web.MessageEvent event) {
    try {
      messages.add((event.data as JSString).toDart);
    } catch (error, stack) {
      messages.addError(error, stack);
    }
  }).toJS;
  socket.onerror = ((web.Event _) {
    final error = StateError('Voice signaling connection failed.');
    if (!connection.isCompleted) connection.completeError(error);
    messages.addError(error);
  }).toJS;
  socket.onclose = ((web.Event _) {
    if (!connection.isCompleted) {
      connection.completeError(StateError('Voice signaling closed early.'));
    }
    unawaited(messages.close());
  }).toJS;
  socket.onopen = ((web.Event _) {
    if (!connection.isCompleted) connection.complete();
  }).toJS;

  try {
    await connection.future.timeout(const Duration(seconds: 15));
  } catch (_) {
    socket.close();
    rethrow;
  }
  return _WebVoiceSignalingSocket(socket, messages);
}

class _WebVoiceSignalingSocket implements VoiceSignalingSocket {
  _WebVoiceSignalingSocket(this._socket, this._messages);

  final web.WebSocket _socket;
  final StreamController<dynamic> _messages;

  @override
  Stream<dynamic> get messages => _messages.stream;

  @override
  bool get isOpen => _socket.readyState == web.WebSocket.OPEN;

  @override
  void add(String message) {
    if (!isOpen) throw StateError('Voice signaling connection is closed.');
    _socket.send(message.toJS);
  }

  @override
  Future<void> close() async {
    if (_socket.readyState != web.WebSocket.CLOSED) _socket.close();
  }
}
