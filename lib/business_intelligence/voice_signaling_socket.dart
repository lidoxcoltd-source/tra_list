import 'voice_signaling_socket_stub.dart'
    if (dart.library.io) 'voice_signaling_socket_io.dart'
    if (dart.library.html) 'voice_signaling_socket_web.dart'
    as platform;
import 'voice_signaling_socket_base.dart';

export 'voice_signaling_socket_base.dart';

Future<VoiceSignalingSocket> connectVoiceSignalingSocket(Uri url) =>
    platform.connectVoiceSignalingSocket(url);
