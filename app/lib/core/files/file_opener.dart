import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

const _tempPrefix = 'revoked-view-';

/// Android's side lives in MainActivity: an ACTION_VIEW intent over a
/// FileProvider URI, which is how Android opens a file in its default app.
const _androidViewer = MethodChannel('revoked/file_viewer');

/// Hands file bytes to whatever the OS opens that type with.
///
/// Another app can only read a file, so the bytes are written to a fresh
/// private temp directory first; [purgeOpenedFiles] clears those. iOS, and an
/// Android with no app for the type, get the share sheet instead. Returns false
/// when nothing could open it.
Future<bool> openFileOnDevice({
  required Uint8List bytes,
  required String filename,
  String? mime,
}) async {
  if (!kIsWeb && Platform.isAndroid) {
    try {
      final opened = await _androidViewer.invokeMethod<bool>('open', {
        'bytes': bytes,
        'name': safeOpenFilename(filename, mime),
        'mime': (mime ?? '').split(';').first.trim(),
      });
      if (opened == true) return true;
    } on PlatformException {
      // Fall through to the share sheet.
    }
  }
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: filename, mimeType: mime)],
        fileNameOverrides: [filename],
      ),
    );
    return result.status != ShareResultStatus.unavailable;
  }

  try {
    // createTemp is mkdtemp: a 0700 directory, so other local users cannot
    // read the decrypted copy while it waits for the viewer.
    final dir = await Directory.systemTemp.createTemp(_tempPrefix);
    final file = File(
      '${dir.path}${Platform.pathSeparator}${safeOpenFilename(filename, mime)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    // Arguments go straight to the process, never through a shell: the name
    // can come from whoever answered a request.
    final (exe, args) = Platform.isMacOS
        ? ('open', [file.path])
        : Platform.isWindows
        ? ('explorer.exe', [file.path])
        : ('xdg-open', [file.path]);
    await Process.start(exe, args, mode: ProcessStartMode.detached);
    return true;
  } on Object {
    return false;
  }
}

/// Deletes every copy [openFileOnDevice] left behind. The viewer may still be
/// reading one when it is written, so they are cleared later instead: on
/// sign-out and on the next start.
Future<void> purgeOpenedFiles() async {
  if (kIsWeb) return;
  if (Platform.isAndroid) {
    try {
      await _androidViewer.invokeMethod<void>('purge');
    } on Object {
      // Retried on the next start.
    }
    return;
  }
  try {
    await for (final entry in Directory.systemTemp.list()) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is Directory && name.startsWith(_tempPrefix)) {
        await entry.delete(recursive: true);
      }
    }
  } on Object {
    // Best effort: a copy that cannot be deleted now is retried next time.
  }
}

/// A filename that is a single safe path segment and keeps an extension, so
/// the OS still picks the right app. Anything outside a plain character set is
/// replaced, which also rules out traversal and shell metacharacters.
@visibleForTesting
String safeOpenFilename(String filename, [String? mime]) {
  final base = filename.split(RegExp(r'[/\\]')).last;
  var name = base
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')
      .replaceFirst(RegExp(r'^[.\s]+'), '')
      .trim();
  if (name.isEmpty) name = 'file';
  if (!name.contains('.')) {
    final ext = _extensionFor(mime);
    if (ext != null) name = '$name.$ext';
  }
  if (name.length > 120) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 && name.length - dot <= 10 ? name.substring(dot) : '';
    name = name.substring(0, 120 - ext.length) + ext;
  }
  return name;
}

String? _extensionFor(String? mime) {
  return switch ((mime ?? '').split(';').first.trim().toLowerCase()) {
    'application/pdf' => 'pdf',
    'text/plain' => 'txt',
    'text/csv' => 'csv',
    'application/json' => 'json',
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'application/zip' => 'zip',
    _ => null,
  };
}
