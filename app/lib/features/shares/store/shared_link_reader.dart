import 'dart:typed_data';

import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart'
    show SealedContent;

/// Why an end-to-end encrypted entry on a link stays closed.
enum ClosedEntry {
  rollback(
    'This entry is older than the saved version',
    'This device has already read a newer or different encrypted version of '
        'this entry. The returned value is not shown.',
  ),

  /// The address carried no key, as when only part of it was copied.
  incomplete(
    'This link is incomplete',
    'Some entries on this link are end-to-end encrypted. The key that opens '
        'them is the end of the link\'s address, after “#k=”, and it is '
        'missing here, for example because only part of the address was '
        'copied. The complete link opens them.',
  ),

  /// The key does not open what the link holds for the entry.
  replaced(
    'The key of this link was replaced',
    'Some entries on this link are end-to-end encrypted, and the key in '
        'this address does not open them. It was replaced, or the address '
        'was changed on the way. The current link comes from the sender.',
  ),

  /// The link fell behind the record: the server sent nothing to open.
  unavailable(
    'Encrypted · not available on this link right now',
    'An encrypted entry was changed and has not been renewed for this link '
        'yet. Until then it is not shown, rather than an older version of it.',
  ),

  /// What the server sent is not what the key was made for.
  damaged(
    'This entry could not be decrypted',
    'An encrypted entry on this link could not be decrypted: what the server '
        'sent does not match the key in this address.',
  );

  /// Said in the entry's row, in place of a value.
  final String title;

  /// Said once above the entries.
  final String detail;

  const ClosedEntry(this.title, this.detail);

  static ClosedEntry? of(Map<String, dynamic> record) {
    final name = record[SharedLinkReader.closedField];
    for (final state in values) {
      if (state.name == name) return state;
    }
    return null;
  }
}

/// Opens the end-to-end encrypted entries of a share the way anyone holding
/// its address can: with what the server returned for the link and the key
/// the address ended in (design/e2ee-sharing.md §3). Nothing an account or a
/// device holds is involved, so it reads the same signed out, and the link
/// page does the same in a browser (`routes/publicPageSealing.go`).
abstract final class SharedLinkReader {
  /// Set on an entry that stays closed, to a [ClosedEntry]'s name. Such an
  /// entry carries no value.
  static const closedField = 'closed';

  /// Set on an entry that was opened here.
  static const encryptedField = 'encrypted';

  /// On an opened encrypted file: what its blob opens with, a
  /// [SharedFileSeal]. Held in memory only, like the address key.
  static const fileSealField = 'fileSeal';

  /// Opens an encrypted file's blob, as fetched with its download token,
  /// into the bytes its seal describes. Throws [SealingException] for a blob
  /// that is not that file.
  static Uint8List openFile(Map<String, dynamic> record, Uint8List blob) {
    final seal = record[fileSealField];
    final id = record['id'];
    final size = record['size'];
    if (seal is! SharedFileSeal || id is! String || size is! int) {
      throw const SealingException('This file cannot be opened here.');
    }
    return SealedFile.open(
      fileKey: seal.fileKey,
      blob: blob,
      workspace: seal.workspace,
      record: id,
      size: size,
    );
  }

  static const _served = [
    'sealed',
    'sealedValue',
    'sealedVersion',
    'viewerWrap',
    'unavailable',
    'value',
  ];

  /// [data] as the public read returned it, with every encrypted entry
  /// opened into an ordinary record or closed with the reason. [data] itself
  /// is left as it was.
  static Map<String, dynamic> open(
    Map<String, dynamic> data,
    Uint8List? linkKey,
  ) {
    final records = data['records'];
    if (records is! List) return data;
    return {
      ...data,
      'records': [
        for (final r in records)
          if (r is Map<String, dynamic> && r['sealed'] == true)
            _openEntry(r, linkKey)
          else
            r,
      ],
    };
  }

  static Map<String, dynamic> _closed(
    Map<String, dynamic> entry,
    ClosedEntry why,
  ) => {
    for (final e in entry.entries)
      // A closed file offers nothing to download.
      if (!_served.contains(e.key) && e.key != 'downloadToken') e.key: e.value,
    closedField: why.name,
  };

  static Map<String, dynamic> _openEntry(
    Map<String, dynamic> entry,
    Uint8List? linkKey,
  ) {
    if (entry['unavailable'] == true) {
      return _closed(entry, ClosedEntry.unavailable);
    }
    if (linkKey == null) return _closed(entry, ClosedEntry.incomplete);

    final record = entry['id'];
    final version = entry['sealedVersion'];
    final wrap = entry['viewerWrap'];
    final sealed = entry['sealedValue'];
    if (record is! String ||
        version is! int ||
        wrap is! String ||
        sealed is! String) {
      return _closed(entry, ClosedEntry.damaged);
    }

    final LinkViewerSeal seal;
    try {
      seal = SealedFormats.openLinkViewer(
        copyKey: SealedFormats.linkCopyKey(linkKey: linkKey, record: record),
        wrapped: wrap,
        record: record,
        version: version,
      );
    } on SealingException {
      return _closed(entry, ClosedEntry.replaced);
    } on FormatException {
      return _closed(entry, ClosedEntry.damaged);
    }

    final recordKey = entry['key'];
    try {
      final content = SealedContent.tryDecode(
        SealedFormats.openValue(
          valueKey: seal.valueKey,
          sealed: sealed,
          workspace: seal.workspace,
          record: record,
          recordKey: recordKey is String ? recordKey : '',
          version: version,
        ),
      );
      // Decrypted, but not a value with its label, type and format.
      if (content == null) return _closed(entry, ClosedEntry.damaged);
      final file = content.file;
      if (file != null) {
        // The name, type and exact size from inside the seal; what the
        // server states beside the blob describes only the blob.
        return {
          for (final e in entry.entries)
            if (!_served.contains(e.key)) e.key: e.value,
          'value': '',
          'label': content.label,
          'type': 'file',
          'format': content.format,
          'filename': file.name,
          'mime': file.mime,
          'size': file.size,
          fileSealField: SharedFileSeal(
            fileKey: file.fileKey,
            workspace: seal.workspace,
          ),
          encryptedField: true,
        };
      }
      return {
        for (final e in entry.entries)
          if (!_served.contains(e.key)) e.key: e.value,
        'value': content.value,
        // The label, type and format that were encrypted with the value, not
        // the copies the server states beside the ciphertext.
        'label': content.label,
        'type': content.type,
        'format': content.format,
        encryptedField: true,
      };
    } on SealingException {
      return _closed(entry, ClosedEntry.damaged);
    } on FormatException {
      return _closed(entry, ClosedEntry.damaged);
    }
  }
}

/// What an encrypted file on a link opens with: its file key from inside the
/// seal, and the workspace it is bound to.
class SharedFileSeal {
  final Uint8List fileKey;
  final String workspace;

  const SharedFileSeal({required this.fileKey, required this.workspace});
}
