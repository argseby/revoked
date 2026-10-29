import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/config/server_blocklist.dart';

void main() {
  final list = ServerBlocklist.parse(
    File('../blocked-domains.txt').readAsStringSync(),
  );

  test('the name under another top-level domain is blocked', () {
    for (final host in [
      'revoked.app',
      'REVOKED.io',
      'api.revoked.app',
      'revoked.co.uk',
      'revoked.com.br',
      'rev0ked.link',
      'revoked-link.com',
    ]) {
      expect(list.blocks(host), isTrue, reason: host);
    }
  });

  test('the official domain is never blocked', () {
    final hostile = ServerBlocklist.parse('revoked.*\nrevoked.link\n*');
    for (final host in [
      'revoked.link',
      'api.revoked.link',
      'docs.revoked.link',
    ]) {
      expect(hostile.blocks(host), isFalse, reason: host);
    }
  });

  test('self-hosted servers stay allowed', () {
    for (final host in [
      'revoked.example.com',
      'api.example.com',
      'localhost',
      '192.168.178.74',
      'myrevoked.app',
      '',
    ]) {
      expect(list.blocks(host), isFalse, reason: host);
    }
  });

  test('comments and blank lines are not rules', () {
    final parsed = ServerBlocklist.parse('# revoked.app\n\n  \nfake.example\n');
    expect(parsed.blocks('revoked.app'), isFalse);
    expect(parsed.blocks('fake.example'), isTrue);
    expect(parsed.blocks('www.fake.example'), isTrue);
  });
}
