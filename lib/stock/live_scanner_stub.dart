import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

Future<String?> scanLiveCamera(
  BuildContext context, {
  required Future<String?> Function(ImageSource source) scanImage,
  Future<String?> Function(BuildContext context)? searchProduct,
}) async => null;
