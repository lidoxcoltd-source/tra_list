import 'voice_signaling_socket_base.dart';

Future<VoiceSignalingSocket> connectVoiceSignalingSocket(Uri url) =>
    Future.error(UnsupportedError('Voice signaling is not supported here.'));
