import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/attestation_ask.dart';
import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/models/group.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/request_proposal.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/share_proposal.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/models/workspace.dart';

/// Who sees an item (VISIBILITY.md), as each model reads it from the server.
void main() {
  test('vault, shares and requests read as private when nothing is said', () {
    final section = Section.fromJson({
      'id': 's1',
      'key': 'k',
      'name': 'n',
      'user': 'u1',
      'workspace': 'w1',
    });
    expect(section.audienceKind, 'private');
    expect(section.shared, isFalse);
    // An older server only says shared.
    expect(
      Section.fromJson({
        'id': 's1',
        'key': 'k',
        'name': 'n',
        'user': 'u1',
        'workspace': 'w1',
        'shared': true,
      }).audienceKind,
      'workspace',
    );
    final link = Link.fromJson({'id': 'l1', 'slug': 's', 'label': 'l'});
    expect(link.audienceKind, 'private');
    expect(link.copyWith(audienceKind: 'workspace').openToWorkspace, isTrue);
  });

  test('templates, contacts and attestations read as the workspace\'s', () {
    final template = Template.fromJson({'id': 't1', 'name': 'n'});
    expect(template.audienceKind, 'workspace');
    expect(template.editing, 'audience');
    expect(template.owner, '');

    final contact = Contact.fromJson({
      'id': 'c1',
      'name': 'Ada',
      'user': 'u-account',
      'createdBy': 'u-member',
      'audienceKind': 'private',
      'editing': 'owner',
    });
    // The account it points to is not who owns it.
    expect(contact.user, 'u-account');
    expect(contact.createdBy, 'u-member');
    expect(contact.audienceKind, 'private');
    expect(contact.editing, 'owner');

    final attestation = Attestation.fromJson({
      'id': 'a1',
      'type': 'membership',
      'user': 'u1',
      'audienceKind': 'nonsense',
    });
    expect(attestation.owner, 'u1');
    expect(attestation.audienceKind, 'private');
  });

  test('a workspace\'s defaults fall back to the built-in ones', () {
    final ws = Workspace.fromJson({
      'id': 'w1',
      'name': 'Acme',
      'slug': 'acme',
      'defaultAudience': {'links': 'workspace', 'contacts': 'nonsense'},
    });
    expect(ws.audienceFor('links'), 'workspace');
    // Unknown values are dropped, so the built-in default holds.
    expect(ws.audienceFor('contacts'), 'workspace');
    expect(ws.audienceFor('sections'), 'private');
    expect(ws.audienceFor('templates'), 'workspace');
  });

  test('a tool\'s visibility suggestion is carried, and only two values', () {
    final share = ShareProposal.fromQuery({
      'label': 'Flat',
      'keys': 'name',
      'visibility': 'workspace',
    });
    expect(share?.visibility, 'workspace');
    expect(share?.toQuery()['visibility'], 'workspace');
    expect(
      ShareProposal.fromQuery({
        'label': 'Flat',
        'keys': 'name',
        'visibility': 'everyone',
      }),
      isNull,
    );

    final request = RequestProposal.fromQuery({
      'template': 'Onboarding',
      'visibility': 'private',
    });
    expect(request?.visibility, 'private');
    expect(
      RequestProposal.fromQuery({'template': 'x', 'visibility': 'x'}),
      isNull,
    );

    final fp = 'a' * 64;
    final ask = AttestationAsk.fromQuery({
      'type': 'membership',
      'for': fp,
      'visibility': 'private',
    });
    expect(ask?.visibility, 'private');
    expect(ask?.toQuery()['visibility'], 'private');
  });

  test('a group reads its members', () {
    final g = WorkspaceGroup.fromJson({
      'id': 'g1',
      'key': 'hr',
      'name': 'HR',
      'members': [
        {'id': 'u1', 'email': 'ada@example.com'},
      ],
    });
    expect(g.contains('u1'), isTrue);
    expect(g.contains('u2'), isFalse);
    expect(g.members.single.email, 'ada@example.com');
  });
}
