import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';

/// A file staged for upload, held as a handle rather than as bytes.
///
/// Reading a picked file into memory costs its full size for as long as the
/// drawer stays open and again while the request body is built, so a large
/// record was an out-of-memory kill on mobile before a byte reached the wire.
/// [open] is a factory rather than a stream because a byte stream can only be
/// consumed once and a retried save needs a second one.
class PendingUpload {
  final String name;
  final int size;
  final Stream<List<int>> Function() open;

  const PendingUpload({
    required this.name,
    required this.size,
    required this.open,
  });

  static const _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  };

  bool get isImage {
    final lower = name.toLowerCase();
    return _imageExtensions.any(lower.endsWith);
  }

  /// Reads the file whole. Only ever for a bounded preview — the upload path
  /// streams, and this undoes that.
  Future<Uint8List> readAll() async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in open()) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static Future<PendingUpload> fromPicked(PlatformFile file) async =>
      PendingUpload(
        name: file.name,
        size: await file.length(),
        open: file.readAsByteStream,
      );

  /// Null for a dropped directory, which has a name and no readable content.
  static Future<PendingUpload?> fromDropped(DropItem item) async {
    if (item is DropItemDirectory) return null;
    return PendingUpload(
      name: item.name,
      size: await item.length(),
      open: item.openRead,
    );
  }
}
