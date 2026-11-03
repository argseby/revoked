import 'package:flutter/widgets.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/attestations/view/ask_attestation_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_check_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_create_sheet.dart';
import 'package:revoked_app/features/contacts/view/contact_create_sheet.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';
import 'package:revoked_app/features/shell/view/link_search_sheet.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

/// Where a new thing goes, which is what the picker groups by.
enum NewGroup {
  vault('In your vault'),
  people('People you deal with'),
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
  contact(
    NewGroup.people,
    AppIcons.personPlus,
    'Contact',
    'Someone to send things to, or ask things from.',
    'p',
    feature: Feature.contacts,
  ),
  link(
    NewGroup.give,
    AppIcons.link,
    'Share link',
    'Let someone see your records until you revoke it.',
    'l',
    feature: Feature.sharing,
  ),
  attestation(
    NewGroup.give,
    AppIcons.attestation,
    'Attestation',
    'Confirm something about someone, in this server\'s name.',
    'a',
    feature: Feature.attestations,
  ),
  request(
    NewGroup.ask,
    AppIcons.inboxFill,
    'Request',
    'Ask someone to fill in their details.',
    'q',
    feature: Feature.requests,
  ),
  askAttestation(
    NewGroup.ask,
    AppIcons.askFor,
    'Attestation about you',
    'Ask a club or an employer to confirm something about you.',
    'k',
    feature: Feature.attestations,
  ),
  checkAttestation(
    NewGroup.ask,
    AppIcons.shieldCheck,
    'See someone\'s attestation',
    'Ask to see one, like a membership, and check it.',
    'c',
    feature: Feature.attestations,
  ),
  openLink(
    NewGroup.received,
    AppIcons.qrCode,
    'Open or scan a link',
    'Paste or scan what someone sent you. We check the sender first.',
    'o',
  );

  const NewKind(
    this.group,
    this.icon,
    this.label,
    this.description,
    this.key, {
    this.feature,
  });

  final NewGroup group;
  final IconData icon;
  final String label;
  final String description;

  /// Pressed while the picker is open, picks this row.
  final String key;

  /// The feature this row belongs to; null for what every account has.
  final Feature? feature;

  /// Whether the person has this row's feature on and may use it.
  bool get isAvailable => feature == null || Stores.features.visible(feature!);

  /// The rows on offer right now, in their fixed order.
  static List<NewKind> get available => [
    for (final kind in values)
      if (kind.isAvailable) kind,
  ];

  /// The row the picker starts on for the shell destination it was opened
  /// from (a root of `AppRoutes.allDestinations`). The list itself never
  /// reorders, so each row stays where people learned it.
  static NewKind firstFor(String? destination) {
    final wanted = switch (destination) {
      AppRoutes.shared => NewKind.link,
      AppRoutes.requests => NewKind.request,
      AppRoutes.attestations => NewKind.attestation,
      AppRoutes.contacts => NewKind.contact,
      _ => NewKind.record,
    };
    return wanted.isAvailable ? wanted : NewKind.record;
  }
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
    case NewKind.contact:
      await openContactCreateSheet(context);
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
