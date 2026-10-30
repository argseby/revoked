import 'package:flutter/widgets.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/attestations/view/ask_attestation_sheet.dart';
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
    'One piece of information, such as a name or an IBAN.',
    'r',
  ),
  file(
    NewGroup.vault,
    AppIcons.fileEarmark,
    'File',
    'A document such as an ID card or a payslip.',
    'f',
  ),
  template(
    NewGroup.vault,
    AppIcons.cardList,
    'From a template',
    'Several records at once, ready to fill in.',
    't',
  ),
  section(
    NewGroup.vault,
    AppIcons.folder,
    'Section',
    'Records that belong together and are shared as one.',
    's',
  ),
  link(
    NewGroup.give,
    AppIcons.link,
    'Share link',
    'The current value of chosen records, until you revoke it.',
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
    'A form that asks someone for their data.',
    'q',
  ),
  askAttestation(
    NewGroup.ask,
    AppIcons.askFor,
    'Attestation about you',
    'Ask a club or an employer to confirm something about you.',
    'k',
  ),
  openLink(
    NewGroup.received,
    AppIcons.qrCode,
    'Open or scan a link',
    'A share, a request, or a service asking to see an attestation. The '
        'sender is checked first.',
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
    case NewKind.openLink:
      await openLinkSearchSheet(context);
  }
}
