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
  vault('Vault'),
  people('Contacts'),
  give('Sharing'),
  ask('Requests'),
  received('Received links');

  const NewGroup(this.title);
  final String title;
}

/// Everything the one "New" button can start, in the order it is listed.
enum NewKind {
  record(
    NewGroup.vault,
    AppIcons.key,
    'Record',
    'A single value, such as a name or an IBAN.',
    'r',
  ),
  file(
    NewGroup.vault,
    AppIcons.fileEarmark,
    'File',
    'A document, such as an ID card or a payslip.',
    'f',
  ),
  template(
    NewGroup.vault,
    AppIcons.cardList,
    'From a template',
    'Several records filled in at once.',
    't',
  ),
  section(
    NewGroup.vault,
    AppIcons.folder,
    'Section',
    'Records grouped to be shared together.',
    's',
  ),
  contact(
    NewGroup.people,
    AppIcons.personPlus,
    'Contact',
    'A recipient of records and requests.',
    'p',
    feature: Feature.contacts,
  ),
  link(
    NewGroup.give,
    AppIcons.link,
    'Share link',
    'Access to records until revoked.',
    'l',
    feature: Feature.sharing,
  ),
  attestation(
    NewGroup.give,
    AppIcons.attestation,
    'Attestation',
    'A confirmation about someone, issued in this server\'s name.',
    'a',
    feature: Feature.attestations,
  ),
  request(
    NewGroup.ask,
    AppIcons.inboxFill,
    'Request',
    'A form that collects details from others.',
    'q',
    feature: Feature.requests,
  ),
  askAttestation(
    NewGroup.ask,
    AppIcons.askFor,
    'Attestation about you',
    'A confirmation requested from a club or an employer.',
    'k',
    feature: Feature.attestations,
  ),
  checkAttestation(
    NewGroup.ask,
    AppIcons.shieldCheck,
    'See someone\'s attestation',
    'Verification of an attestation, such as a membership.',
    'c',
    feature: Feature.attestations,
  ),
  openLink(
    NewGroup.received,
    AppIcons.qrCode,
    'Open or scan a link',
    'A pasted or scanned link, opened after the sender is checked.',
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

/// A page's own create button: what it starts and what it says.
typedef PageAction = ({NewKind kind, String label});

/// The create button a destination shows beside the general New, or null on
/// a page that makes nothing of its own (the overview).
PageAction? pageActionFor(String? destination) {
  final PageAction? action = switch (destination) {
    AppRoutes.vault => (kind: NewKind.record, label: 'Add to vault'),
    AppRoutes.shared => (kind: NewKind.link, label: 'New link'),
    AppRoutes.requests => (kind: NewKind.request, label: 'New request'),
    AppRoutes.attestations => (
      kind: NewKind.attestation,
      label: 'New attestation',
    ),
    AppRoutes.contacts => (kind: NewKind.contact, label: 'New contact'),
    _ => null,
  };
  return action != null && action.kind.isAvailable ? action : null;
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
