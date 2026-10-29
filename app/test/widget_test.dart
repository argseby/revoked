import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/utils/deep_links.dart';

/// Pure-logic tests. These need no device or running backend, which is what
/// makes them worth having first: they pin the parsing and URL handling that
/// every screen depends on.
void main() {
  group('DeepLinks', () {
    test('maps the canonical short hosts to router locations', () {
      expect(DeepLinks.locationFor(Uri.parse('revoked://s/abc')), '/s/abc');
      expect(DeepLinks.locationFor(Uri.parse('revoked://r/abc')), '/r/abc');
      expect(DeepLinks.locationFor(Uri.parse('revoked://i/tok')), '/i/tok');
    });

    test('still accepts the long hosts', () {
      expect(DeepLinks.locationFor(Uri.parse('revoked://share/abc')), '/s/abc');
      expect(
        DeepLinks.locationFor(Uri.parse('revoked://request/abc')),
        '/r/abc',
      );
      expect(
        DeepLinks.locationFor(Uri.parse('revoked://invite/tok')),
        '/i/tok',
      );
    });

    test('rejects anything that is not a revoked link', () {
      expect(
        DeepLinks.locationFor(Uri.parse('https://revoked.link/s/abc')),
        isNull,
      );
      expect(DeepLinks.locationFor(Uri.parse('revoked://unknown/abc')), isNull);
      expect(DeepLinks.locationFor(Uri.parse('revoked://s')), isNull);
    });

    test('builds links the parser accepts', () {
      final link = DeepLinks.invite('token123');
      expect(DeepLinks.locationFor(Uri.parse(link)), '/i/token123');
    });
  });

  group('ApiClient.normalizeServerUrl', () {
    test('adds a scheme to a bare host and strips a trailing slash', () {
      expect(
        ApiClient.normalizeServerUrl('192.168.1.5:3000/'),
        'http://192.168.1.5:3000',
      );
    });

    test('a bare public host gets https', () {
      for (final raw in [
        'api.revoked.link',
        'API.revoked.link/',
        'example.com:8443',
        '8.8.8.8:3000',
        '172.32.0.1',
      ]) {
        expect(
          ApiClient.normalizeServerUrl(raw),
          startsWith('https://'),
          reason: raw,
        );
      }
    });

    test('a bare local or private host keeps http', () {
      for (final raw in [
        'localhost:3000',
        'app.localhost:3000',
        '127.0.0.1:3000',
        '10.0.0.2',
        '172.16.4.1:3000',
        '192.168.178.74:3000',
        '169.254.1.1',
        '[::1]:3000',
        '[fd00::1]:3000',
        'devbox:3000',
        'nas.local',
      ]) {
        expect(
          ApiClient.normalizeServerUrl(raw),
          startsWith('http://'),
          reason: raw,
        );
      }
    });

    test('leaves an explicit scheme alone', () {
      expect(
        ApiClient.normalizeServerUrl('http://api.example.com'),
        'http://api.example.com',
      );
      expect(
        ApiClient.normalizeServerUrl('https://api.example.com'),
        'https://api.example.com',
      );
    });
  });

  group('Invite parsing', () {
    test('reads a probe into something the screen can render', () {
      final preview = InvitePreview.fromJson({
        'label': 'Accountant',
        'workspace': {'name': 'Acme', 'type': 'business'},
        'invitedBy': 'owner@acme.test',
        'requiresEmail': true,
        'permissions': [
          {
            'key': 'shares:read',
            'label': 'View shares',
            'description': 'See the shares this workspace has issued.',
            'destructive': false,
          },
          {
            'key': 'members:add',
            'label': 'Invite members',
            'description': 'Invite people into this workspace.',
            'destructive': true,
          },
        ],
      });

      expect(preview.workspaceName, 'Acme');
      expect(preview.invitedBy, 'owner@acme.test');
      expect(preview.permissions, hasLength(2));
      expect(preview.requiresEmail, isTrue);
      // Drives the warning shown before someone accepts control over access.
      expect(preview.grantsDestructive, isTrue);
    });

    test('survives a probe with nothing but permissions', () {
      final preview = InvitePreview.fromJson({'permissions': []});
      expect(preview.workspaceName, isNotEmpty);
      expect(preview.grantsDestructive, isFalse);
      expect(preview.invitedBy, isNull);
    });

    test('an invite carries its token only when one was returned', () {
      final created = Invite.fromJson({
        'id': 'a',
        'workspace': 'w',
        'permissions': [],
        'maxUses': 1,
      }, plainToken: 'secret');
      expect(created.plainToken, 'secret');
      expect(created.isSingleUse, isTrue);
      expect(created.usesLeft, 1);

      final listed = Invite.fromJson({
        'id': 'b',
        'workspace': 'w',
        'permissions': [],
      });
      expect(listed.plainToken, isNull);
      expect(listed.usesLeft, isNull, reason: 'unlimited invites have no cap');
    });
  });
}
