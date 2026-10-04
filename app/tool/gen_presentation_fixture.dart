// Presents the fixture credential with the app's own code and writes the
// result where the Go tests read it, so the server's verifier is checked
// against bytes the app actually produced.
//
// Takes the file holding the holder's private key, which the Go generator
// wrote and which is not kept. Run through tool/gen_sd_jwt_fixture.sh.
import 'dart:convert';
import 'dart:io';

import 'package:revoked_app/core/utils/sd_jwt.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: gen_presentation_fixture.dart <file with the holder key>',
    );
    exit(64);
  }
  final fixture =
      jsonDecode(File('test/fixtures/sd_jwt.json').readAsStringSync())
          as Map<String, dynamic>;
  final presentedAt = (fixture['issuedAtUnix'] as int) + 3600;

  final presentation = presentSdJwt(
    credential: fixture['credential'] as String,
    disclose: (fixture['disclose'] as List).cast<String>(),
    audience: fixture['audience'] as String,
    nonce: fixture['nonce'] as String,
    privateKeyPem: File(args.first).readAsStringSync(),
    now: DateTime.fromMillisecondsSinceEpoch(presentedAt * 1000),
  );

  const encoder = JsonEncoder.withIndent('  ');
  File('test/fixtures/app_presentation.json').writeAsStringSync(
    '${encoder.convert({'presentation': presentation, 'presentedAtUnix': presentedAt})}\n',
  );
  stdout.writeln('wrote test/fixtures/app_presentation.json');
}
