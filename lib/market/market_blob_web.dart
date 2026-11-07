import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

String? createVideoBlobUrl(Uint8List bytes, String mime) {
  final blob = html.Blob([bytes], mime);
  return html.Url.createObjectUrlFromBlob(blob);
}

Future<Uint8List?> createVideoThumbnail(Uint8List bytes, String mime) async {
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final video = html.VideoElement()
    ..muted = true
    ..preload = 'auto'
    ..style.position = 'fixed'
    ..style.left = '-10000px'
    ..style.top = '0'
    ..style.width = '1px'
    ..style.height = '1px';
  video.setAttribute('playsinline', '');
  try {
    final metadata = video.onLoadedMetadata.first.timeout(
      const Duration(seconds: 20),
    );
    final firstFrame = video.onLoadedData.first.timeout(
      const Duration(seconds: 20),
    );
    html.document.body?.append(video);
    video.src = url;
    video.load();
    await metadata;
    // Browsers often do not decode the first frame until playback is requested.
    // Start muted inline playback briefly so canvas has a real frame to capture.
    try {
      await video.play();
    } catch (_) {
      // Some browsers allow frame extraction without playback.
    }
    await firstFrame;
    if (video.videoWidth <= 0 || video.videoHeight <= 0) return null;

    final duration = video.duration;
    final frameTime = duration.isFinite && duration > 0
        ? math.min(0.4, duration / 2)
        : 0.0;
    if (frameTime > 0 && video.readyState >= 2) {
      final seeked = video.onSeeked.first.timeout(const Duration(seconds: 5));
      video.currentTime = frameTime;
      try {
        await seeked;
      } catch (_) {
        // Keep the already decoded opening frame if this codec cannot seek.
      }
    }

    const maxWidth = 720;
    final width = math.min(maxWidth, video.videoWidth);
    final height = (video.videoHeight * width / video.videoWidth).round();
    final canvas = html.CanvasElement(width: width, height: height);
    canvas.context2D.drawImageScaled(video, 0, 0, width, height);
    final encoded = canvas.toDataUrl('image/jpeg', 0.78).split(',').last;
    return base64Decode(encoded);
  } catch (error) {
    // Some codecs do not allow seeking during metadata load. The upload still
    // succeeds, and the player can use its regular cover fallback.
    developer.log('Could not generate browser video thumbnail: $error');
    return null;
  } finally {
    video.pause();
    video.src = '';
    video.load();
    video.remove();
    html.Url.revokeObjectUrl(url);
  }
}
