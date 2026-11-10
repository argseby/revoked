import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/services/secure_storage.dart';
import 'package:revoked_app/features/shares/store/shared_link_reader.dart';

/// Device-local trust, scoped to the account, home server and complete share
/// identity. The queue preserves the highest version across concurrent reads.
class SavedLinkState {
  final FlutterSecureStorage storage;
  SavedLinkState({FlutterSecureStorage? storage})
    : storage = storage ?? createSecureStorage();
  static Future<void> _writes = Future.value();

  static String address(
    String user,
    String server,
    String origin,
    String slug,
  ) => SealedFormats.encode(
    Sealing.sha256(
      Sealing.context('revoked-saved-link-v1', [user, server, origin, slug]),
    ),
  );

  Future<Uint8List?> key(String address) async {
    final text = await storage.read(key: 'saved_link_key_$address');
    return text == null ? null : SealedFormats.parseLinkKey(text);
  }

  Future<void> saveKey(String address, Uint8List key) => storage.write(
    key: 'saved_link_key_$address',
    value: SealedFormats.linkKeyText(key),
  );
  Future<void> deleteKey(String address) =>
      storage.delete(key: 'saved_link_key_$address');

  Future<Map<String, dynamic>> checkRead(
    String address,
    Map<String, dynamic> served,
    Map<String, dynamic> opened,
  ) async {
    late Map<String, dynamic> result;
    final operation = _writes.then((_) async {
      final raw = await storage.read(key: 'saved_link_pins_$address');
      final pins = raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      final sources = served['records'] as List? ?? const [];
      final openedRows = opened['records'] as List? ?? const [];
      final counts = <String, int>{};
      for (final row in sources) {
        if (row is Map && row['id'] is String) {
          counts.update(row['id'] as String, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      final rows = <dynamic>[];
      for (final (index, r) in openedRows.indexed) {
        if (r is! Map<String, dynamic> || r['id'] is! String) {
          rows.add(r);
          continue;
        }
        final id = r['id'] as String;
        final rawSource = index < sources.length ? sources[index] : null;
        final source = rawSource is Map && rawSource['id'] == id
            ? rawSource
            : null;
        final ambiguous = (counts[id] ?? 0) > 1 || source == null;
        final pin = pins[id] as Map?;
        final authenticated =
            !ambiguous &&
            source['sealed'] == true &&
            r[SharedLinkReader.encryptedField] == true &&
            ClosedEntry.of(r) == null;
        var rollback = ambiguous || (pin != null && source['sealed'] != true);
        if (authenticated) {
          final version = source['sealedVersion'] as int;
          final hash = SealedFormats.encode(
            Sealing.sha256(
              SealedFormats.decode(source['sealedValue'] as String),
            ),
          );
          if (pin != null &&
              (version < (pin['version'] as int) ||
                  (version == pin['version'] && hash != pin['hash']))) {
            rollback = true;
          } else {
            pins[id] = {'version': version, 'hash': hash};
          }
        }
        rows.add(
          rollback
              ? {
                  for (final e in r.entries)
                    if (e.key != 'value' &&
                        e.key != SharedLinkReader.encryptedField)
                      e.key: e.value,
                  SharedLinkReader.closedField: ClosedEntry.rollback.name,
                }
              : r,
        );
      }
      await storage.write(
        key: 'saved_link_pins_$address',
        value: jsonEncode(pins),
      );
      result = {...opened, 'records': rows};
    });
    // A failed storage write fails this read closed without poisoning the queue.
    _writes = operation.then((_) {}, onError: (Object _) {});
    await operation;
    return result;
  }
}
