import 'dart:typed_data';

import 'package:revoked_app/core/models/audience.dart';

import 'package:revoked_app/core/models/connection.dart';

/// Represents a record from the PocketBase `records` collection.
///
/// Two row shapes share this collection:
///   - Primary record: holds `value`, `aliasOf` is empty.
///   - Alias record: `aliasOf` points at a primary record id, `value` is
///     intentionally empty (the value resolves through the parent at read
///     time). Aliases keep their own `key`, `label`, `type`, `format` so the
///     UI can present them as first-class items grouped under the parent.
class Record {
  final String id;
  final String key;
  final String value;
  final String label;
  final String type; // 'text' | 'number'
  final String format; // 'hidden' | 'default'
  final String user;
  final String workspace;
  final String? created;
  final String? updated;

  /// Optional. Set when this record was instantiated as a result of an
  /// inbound public request submission; surfaces the responder's name
  /// or identifier in the vault UI.
  final String? requestedBy;

  /// Optional. When non-null this row is an alias and its `value` is
  /// always empty — the real value lives on the referenced parent.
  final String? aliasOf;

  /// File records: the name the owner gave the file, and what a downloader
  /// receives it as. Belongs to the record, so it survives replacing the file.
  final String? filename;

  /// The storage name PocketBase snakecased and suffixed. Owner-only, and only
  /// ever used to build the file URL — never shown, never served as the name.
  final String? file;

  /// Salted sha256 of the file's content — the currency check for downloads.
  final String? contentHash;
  final String? mime;
  final int size;

  /// End-to-end encrypted. The server holds only [sealedValue]; [value] is the
  /// decrypted text once [opened], and empty until then.
  final bool sealed;
  final String sealedValue;
  final int sealedVersion;
  final int keyEpoch;
  final String keyWrap;
  final bool opened;

  /// The connected tool or API key that wrote this record, and its name.
  /// Empty for what the owner wrote.
  final String writtenBy;
  final String writtenByName;

  /// This device knew the record as encrypted and now it isn't: someone stopped
  /// encrypting it, or the server is passing off a value of its own.
  final bool unsealedElsewhere;

  /// For an opened encrypted file: the key its blob opens with, from inside
  /// the sealed value. Held on this device only; never sent anywhere.
  final Uint8List? fileKey;

  Record({
    required this.id,
    required this.key,
    required this.value,
    required this.label,
    required this.type,
    required this.format,
    required this.user,
    required this.workspace,
    this.created,
    this.updated,
    this.requestedBy,
    this.aliasOf,
    this.filename,
    this.file,
    this.contentHash,
    this.mime,
    this.size = 0,
    this.sealed = false,
    this.sealedValue = '',
    this.sealedVersion = 0,
    this.keyEpoch = 0,
    this.keyWrap = '',
    this.opened = false,
    this.unsealedElsewhere = false,
    this.fileKey,
    this.writtenBy = '',
    this.writtenByName = '',
    this.audienceKind = 'private',
    this.audienceGroups = const [],
    this.editing = 'owner',
  });

  /// Who sees it on its own, beside the sections holding it: `private`,
  /// `workspace` or `groups` (VISIBILITY.md). Only its owner changes it.
  final String audienceKind;

  /// The groups that see it, when [audienceKind] is `groups`.
  final List<String> audienceGroups;

  /// Whether the members who see it, and may publish, may also change it.
  final String editing;

  factory Record.fromJson(Map<String, dynamic> json) {
    final requestedByRaw = json['requestedBy'];
    final aliasRaw = json['aliasOf'];
    return Record(
      id: json['id'] as String,
      key: json['key'] as String,
      // A sealed record has no plain value. If a server sends one anyway it is
      // not this record's, and must not reach a form or a screen.
      value: json['sealed'] == true ? '' : json['value'] as String? ?? '',
      label: json['label'] as String,
      type: json['type'] as String,
      format: json['format'] as String,
      user: json['user'] as String,
      workspace: json['workspace'] as String,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
      requestedBy: (requestedByRaw is String && requestedByRaw.isNotEmpty)
          ? requestedByRaw
          : null,
      aliasOf: (aliasRaw is String && aliasRaw.isNotEmpty) ? aliasRaw : null,
      filename: json['filename'] as String?,
      file: json['file'] as String?,
      contentHash: json['contentHash'] as String?,
      mime: json['mime'] as String?,
      size: (json['size'] as num?)?.toInt() ?? 0,
      sealed: json['sealed'] == true,
      sealedValue: json['sealedValue'] as String? ?? '',
      sealedVersion: (json['sealedVersion'] as num?)?.toInt() ?? 0,
      keyEpoch: (json['keyEpoch'] as num?)?.toInt() ?? 0,
      keyWrap: json['keyWrap'] as String? ?? '',
      writtenBy: json['writtenBy'] as String? ?? '',
      writtenByName: json['writtenByName'] as String? ?? '',
      audienceKind: audienceKindFrom(json['audienceKind']),
      audienceGroups:
          (json['audienceGroups'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      editing: json['editing'] == 'audience' ? 'audience' : 'owner',
    );
  }

  Record _copy({
    String? value,
    String? label,
    String? type,
    String? format,
    bool? opened,
    bool? unsealedElsewhere,
    String? filename,
    String? mime,
    int? size,
    Uint8List? fileKey,
  }) => Record(
    id: id,
    key: key,
    value: value ?? this.value,
    label: label ?? this.label,
    type: type ?? this.type,
    format: format ?? this.format,
    user: user,
    workspace: workspace,
    created: created,
    updated: updated,
    requestedBy: requestedBy,
    aliasOf: aliasOf,
    filename: filename ?? this.filename,
    file: file,
    contentHash: contentHash,
    mime: mime ?? this.mime,
    size: size ?? this.size,
    sealed: sealed,
    sealedValue: sealedValue,
    sealedVersion: sealedVersion,
    keyEpoch: keyEpoch,
    keyWrap: keyWrap,
    opened: opened ?? this.opened,
    unsealedElsewhere: unsealedElsewhere ?? this.unsealedElsewhere,
    fileKey: fileKey ?? this.fileKey,
    writtenBy: writtenBy,
    writtenByName: writtenByName,
    audienceKind: audienceKind,
    audienceGroups: audienceGroups,
    editing: editing,
  );

  /// This record as decrypted. The label, type and format come from inside the
  /// ciphertext: the copies on the row are for the server, which could swap them
  /// and show a real secret under the wrong name.
  /// For an encrypted file, its name, media type, exact size and key come
  /// from there too; the row only describes the blob.
  Record withOpened({
    required String value,
    required String label,
    required String type,
    required String format,
    String? filename,
    String? mime,
    int? size,
    Uint8List? fileKey,
  }) => _copy(
    value: value,
    label: label,
    type: type,
    format: format,
    opened: true,
    filename: filename,
    mime: mime,
    size: size,
    fileKey: fileKey,
  );

  /// An encrypted file this device can open.
  bool get isSealedFile => sealed && isFile && fileKey != null;

  Record markedUnsealedElsewhere(bool flag) => _copy(unsealedElsewhere: flag);

  bool get isHidden => format == 'hidden';
  bool get isRequested => requestedBy != null && requestedBy!.isNotEmpty;
  bool get isAlias => aliasOf != null && aliasOf!.isNotEmpty;
  bool get isFile => type == 'file';

  /// Written by a connected tool or an API key rather than by the owner.
  bool get isWrittenByTool => writtenBy.isNotEmpty;

  /// What to call whoever wrote it, when that was not the owner.
  /// The name of the tool or key that wrote it; its ID goes in a chip.
  String get writerName => writtenByName.isNotEmpty
      ? writtenByName
      : Connection.shortIdOf(writtenBy);

  /// Encrypted, and this device can't read it.
  bool get isLocked => sealed && !opened;

  /// What a reader should see this file called.
  String get displayName =>
      (filename?.isNotEmpty ?? false) ? filename! : (file ?? '');
}
