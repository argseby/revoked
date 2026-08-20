import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// The one way the app hands file bytes to the device: a save dialog where the
/// OS has one (desktop), the share sheet where that is the native idiom
/// (mobile). Returns false when the user backed out.
Future<bool> saveFileToDevice({
  required Uint8List bytes,
  required String filename,
  String? mime,
}) async {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: filename, mimeType: mime)],
        fileNameOverrides: [filename],
      ),
    );
    return result.status == ShareResultStatus.success ||
        result.status == ShareResultStatus.unavailable;
  }

  final saved = await FilePicker.saveFile(
    fileName: filename,
    bytes: bytes,
    mimeType: mime ?? 'application/octet-stream',
  );
  return saved != null;
}

/// Human-readable byte count for file rows and previews.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double v = bytes.toDouble();
  int unit = -1;
  while (v >= 1024 && unit < units.length - 1) {
    v /= 1024;
    unit++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[unit]}';
}
