import 'package:flutter/widgets.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/attestations/view/ask_attestation_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_check_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_create_sheet.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';
import 'package:revoked_app/features/shell/view/link_search_sheet.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

/// Where a new thing goes, which is what the picker groups by.
enum NewGroup {
  vault('In your vault'),
  give('Give to someone'),
  ask('Ask someone'),
  received('Received a link?');

  const NewGroup(this.title);
  final String title;
}

/// Everything the one "New" button can start, in the order it is listed.
enum NewKind {
  record(
    NewGroup.vault,
    AppIcons.key,
    'Record',
    'A single detail, like a name or an IBAN.',
    'r',
  ),
  file(
    NewGroup.vault,
    AppIcons.fileEarmark,
    'File',
    'A document, like an ID card or a payslip.',
    'f',
  ),
  template(
    NewGroup.vault,
    AppIcons.cardList,
    'From a template',
    'Fill in several records at once.',
    't',
  ),
  section(
    NewGroup.vault,
    AppIcons.folder,
    'Section',
    'Group records you always share together.',
    's',
  ),
  link(
    NewGroup.give,
    AppIcons.link,
    'Share link',
    'Let someone see your records until you revoke it.',
    'l',
  ),
  attestation(
    NewGroup.give,
    AppIcons.attestation,
    'Attestation',
    'Confirm something about someone, in this server\'s name.',
    'a',
  ),
  request(
    NewGroup.ask,
    AppIcons.inboxFill,
    'Request',
    'Ask someone to fill in their details.',
    'q',
  ),
  askAttestation(
    NewGroup.ask,
    AppIcons.askFor,
    'Attestation about you',
    'Ask a club or an employer to confirm something about you.',
    'k',
  ),
  checkAttestation(
    NewGroup.ask,
    AppIcons.shieldCheck,
    'See someone\'s attestation',
    'Ask to see one, like a membership, and check it.',
    'c',
  ),
  openLink(
    NewGroup.received,
    AppIcons.qrCode,
    'Open or scan a link',
    'Paste or scan what someone sent you. We check the sender first.',
    'o',
  );

  const NewKind(this.group, this.icon, this.label, this.description, this.key);

  final NewGroup group;
  final IconData icon;
  final String label;
  final String description;

  /// Pressed while the picker is open, picks this row.
  final String key;

  /// The row the picker starts on for the shell destination it was opened
  /// from (index into `AppRoutes.destinations`). The list itself never
  /// reorders, so each row stays where people learned it.
  static NewKind firstFor(int? destination) => switch (destination) {
    2 => NewKind.link,
    3 => NewKind.request,
    4 => NewKind.attestation,
    _ => NewKind.record,
  };
}

/// Opens the form that already exists for [kind].
Future<void> startNew(BuildContext context, NewKind kind) async {
  switch (kind) {
    case NewKind.record:
      openVaultCreateSheet(context);
    case NewKind.file:
      openVaultCreateSheet(context, recordType: 'file');
    case NewKind.template:
      openVaultCreateSheet(context, initialTab: VaultCreateTab.template);
    case NewKind.section:
      openVaultCreateSheet(context, initialTab: VaultCreateTab.section);
    case NewKind.link:
      openShareCreateSheet(context: context);
    case NewKind.request:
      openRequestCreateSheet(
        context: context,
        store: Stores.requests,
        authStore: Stores.auth,
      );
    case NewKind.attestation:
      await showAttestationCreateSheet(context);
    case NewKind.askAttestation:
      await openAskAttestationSheet(context);
    case NewKind.checkAttestation:
      await openAttestationCheckSheet(context);
    case NewKind.openLink:
      await openLinkSearchSheet(context);
  }
}
