import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/utils/pkce.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_consent_layout.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';

/// Keeps choices prominent and explanations secondary. Shared by connection
/// consent, proposals and settings.
class ToolPermissions extends StatelessWidget {
  final String name;

  /// Extra choices and requester context supplied by the flow using this view.
  final List<Widget> leading;
  final List<Widget> information;
  final Widget? requester;
  final bool useColumns;

  /// The owner's choices, and how to change them; a null callback shows the
  /// choice without letting it be changed.
  final bool allowRevoke;
  final bool allowHandOver;
  final ValueChanged<bool>? onAllowRevoke;
  final ValueChanged<bool>? onAllowHandOver;

  /// Whether to offer reading the whole vault at all: only when the tool
  /// asked for it, or still has it. Off unless the owner ticks it.
  final bool showVault;
  final bool allowVaultRead;
  final ValueChanged<bool>? onAllowVaultRead;

  /// Permissions from the served catalogue to decide on, and the keys of
  /// those given. The vault keys are decided in the section group, and
  /// receiving links stands for viewing shares, so only what the tool does
  /// on its own is listed here.
  final List<InvitePermission> permissions;
  final Set<String> granted;
  final void Function(String key, bool on)? onPermission;

  /// Whether to offer the tool a section of its own, and whether it has one.
  final bool showSection;
  final bool ownSection;
  final ValueChanged<bool>? onOwnSection;

  /// The section's name, and whether connecting creates it.
  final String sectionName;
  final bool sectionIsNew;

  /// Names of enabled sections when managing an existing connection.
  final List<String> reachedSectionNames;

  /// Whether the tool may add records to its section, not only read it.
  final bool sectionWrite;
  final ValueChanged<bool>? onSectionWrite;

  /// Why the tool asks, in its own words.
  final ToolReasons reasons;

  const ToolPermissions({
    super.key,
    required this.name,
    this.leading = const [],
    this.information = const [],
    this.requester,
    this.useColumns = true,
    required this.allowRevoke,
    required this.allowHandOver,
    required this.onAllowRevoke,
    required this.onAllowHandOver,
    this.showVault = false,
    this.allowVaultRead = false,
    this.onAllowVaultRead,
    this.permissions = const [],
    this.granted = const {},
    this.onPermission,
    this.showSection = false,
    this.ownSection = false,
    this.onOwnSection,
    this.sectionName = '',
    this.sectionIsNew = false,
    this.reachedSectionNames = const [],
    this.sectionWrite = true,
    this.onSectionWrite,
    this.reasons = const ToolReasons(),
  });

  /// What a tool can do with these can't be taken back, or reaches other
  /// people in the owner's name: a link handed out, a request sent.
  static const sensitive = {'shares:manage', 'requests:manage'};

  /// The keys a tool acts on by itself, in the order they are offered.
  static const onItsOwn = [
    'shares:manage',
    'requests:manage',
    'attestations:issue',
  ];

  String get _section => sectionName.isEmpty ? name : sectionName;

  String get _source {
    if (showVault && allowVaultRead) {
      return 'unencrypted records across your vault';
    }
    if (reachedSectionNames.isNotEmpty) {
      return 'records in ${reachedSectionNames.map((section) => '“$section”').join(', ')}';
    }
    if (ownSection) return 'records in “$_section”';
    return 'no selected vault records';
  }

  (IconData, String, String) _detail(InvitePermission p) => switch (p.key) {
    'shares:manage' => (
      AppIcons.share,
      'Create and manage sharing links',
      'Create, change or delete links for $_source without asking each time.',
    ),
    'requests:manage' => (
      AppIcons.askFor,
      'Create and manage requests',
      'Ask other people for information on your behalf without asking each time.',
    ),
    'attestations:issue' => (
      AppIcons.shieldCheck,
      'Issue attestations it proposes',
      'Issue its proposed attestations on your behalf.',
    ),
    _ => (AppIcons.shieldCheck, p.label, p.description),
  };

  String get _noAccess {
    if (showVault && allowVaultRead) {
      return 'Existing links from elsewhere and account settings stay inaccessible.';
    }
    if (ownSection || reachedSectionNames.isNotEmpty) {
      return 'The rest of your vault, links from elsewhere and account settings stay inaccessible.';
    }
    return 'Your vault, links from elsewhere and account settings stay inaccessible.';
  }

  @override
  Widget build(BuildContext context) {
    Widget reason(String text) => AppConsentDetails(
      title: 'Why $name asks',
      children: [Text('“$text”').muted.small],
    );

    Widget toggle({
      required IconData icon,
      required String label,
      required String subtitle,
      required bool value,
      required ValueChanged<bool>? onChanged,
      String why = '',
      Widget? choice,
      bool sensitive = false,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFormToggleRow(
          icon: icon,
          label: label,
          subtitle: subtitle,
          value: value,
          onChanged: onChanged,
          badge: sensitive ? 'Sensitive' : null,
          badgeVariant: AppBadgeVariant.destructive,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
        ?choice,
        if (why.isNotEmpty) reason(why),
      ],
    );

    final own = [
      for (final key in onItsOwn)
        for (final p in permissions)
          if (p.key == key) p,
    ];

    final decisions = <Widget>[
      ...leading,
      if (showSection)
        AppListGroup(
          title: 'Records in your vault',
          trailing: const SizedBox.shrink(),
          children: [
            toggle(
              icon: sectionIsNew ? AppIcons.folderPlus : AppIcons.folder,
              label: 'Keep records in “$_section”',
              subtitle: sectionIsNew
                  ? 'Creates “$_section” in your vault when connected.'
                  : 'Use the “$_section” section in your vault.',
              value: ownSection,
              onChanged: onOwnSection,
              choice: ownSection
                  ? SectionAccessChoice(
                      write: sectionWrite,
                      onChanged: onSectionWrite,
                    )
                  : null,
              why: reasons.section,
            ),
          ],
        ),
      if (own.isNotEmpty)
        AppListGroup(
          title: 'Actions $name can take',
          trailing: const SizedBox.shrink(),
          footer: reasons.permissions.isEmpty
              ? null
              : reason(reasons.permissions),
          children: [
            for (final p in own)
              toggle(
                icon: _detail(p).$1,
                label: _detail(p).$2,
                subtitle: _detail(p).$3,
                value: granted.contains(p.key),
                sensitive: sensitive.contains(p.key),
                onChanged: onPermission == null
                    ? null
                    : (v) => onPermission!(p.key, v),
              ),
          ],
        ),
      AppListGroup(
        title: 'Links $name proposes',
        trailing: const SizedBox.shrink(),
        children: [
          toggle(
            icon: AppIcons.send,
            label: 'Get the links you approve',
            subtitle: 'Show, open or copy links you approve for this tool.',
            why: reasons.links,
            value: allowHandOver,
            onChanged: onAllowHandOver,
          ),
          toggle(
            icon: AppIcons.linkSlash,
            label: 'Turn off its links and requests',
            subtitle: 'Revoke links and requests that $name proposed.',
            why: reasons.revoke,
            value: allowRevoke,
            onChanged: onAllowRevoke,
          ),
        ],
      ),
      if (showVault)
        AppListGroup(
          title: 'Access across your vault',
          trailing: const SizedBox.shrink(),
          children: [
            toggle(
              icon: AppIcons.safe,
              label: 'Read unencrypted vault records',
              subtitle: 'Read every unencrypted record, including records outside its sections.',
              why: reasons.vault,
              value: allowVaultRead,
              sensitive: true,
              onChanged: onAllowVaultRead,
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: VaultReadNotice(name: name),
            ),
          ],
        ),
    ];
    final supporting = <Widget>[
      ...information,
      const AppListHeader(title: 'About this connection'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Text(_noAccess).small.muted,
      ),
      AppConsentDetails(
        title: 'Duration and disconnection',
        children: const [
          Text(
            'Connections expire after 90 days unless renewed. You can pause '
            'or disconnect this tool in Settings → Connected tools.',
          ),
        ],
      ),
    ];
    if (useColumns) {
      return AppConsentLayout(
        decisions: decisions,
        information: supporting,
        requester: requester,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...decisions, ...supporting],
    );
  }
}

/// Whether a tool only reads its own section or also keeps records there,
/// with what that lets it do said under the choice.
class SectionAccessChoice extends StatelessWidget {
  final bool write;
  final ValueChanged<bool>? onChanged;

  const SectionAccessChoice({super.key, required this.write, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSegmented<bool>(
            expand: true,
            value: write,
            items: const [
              AppSegmentedItem(
                value: false,
                icon: AppIcons.eye,
                label: 'Read only',
              ),
              AppSegmentedItem(
                value: true,
                icon: AppIcons.pencil,
                label: 'Read & add records',
              ),
            ],
            onChanged: (v) => onChanged?.call(v),
          ),
          AppSpacing.gapSm,
          Text(
            write
                ? 'Read all records here; add, edit or delete only its own.'
                : 'Read-only access to the records in this section.',
          ).muted.small,
        ],
      ),
    );
  }
}

/// What letting a tool read the vault means, said before the owner decides.
/// Once a value leaves, nothing in Revoked can call it back.
class VaultReadNotice extends StatelessWidget {
  final String name;

  const VaultReadNotice({super.key, required this.name});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppAlert(
        tone: AppAlertTone.warning,
        leading: const Icon(AppIcons.exclamationTriangle),
        title: const Text('Vault read access'),
        content: const Text(
          'Values this tool reads leave Revoked. Disconnecting '
          'cannot recall them.',
        ),
      ),
      AppConsentDetails(
        title: 'Who receives these values?',
        children: [
          Text(
            '$name can read unencrypted values across your vault. For an AI '
            'assistant, its model provider receives them too. Intended for '
            'an assistant you start on this device.',
          ),
        ],
      ),
    ],
  );
}

/// The code a page shows while it waits to collect the owner's answer itself,
/// derived from its challenge, for the owner to compare. It is what ties that
/// answer to the browser in front of them: a link someone else built has no
/// page of theirs showing it.
class ToolCheckCode extends StatelessWidget {
  final String name;
  final String challenge;

  const ToolCheckCode({super.key, required this.name, required this.challenge});

  @override
  Widget build(BuildContext context) {
    return AppListGroup(
      title: 'Check code',
      trailing: const SizedBox.shrink(),
      footer: Text(
        'Must match the code on the $name page. Decline if it differs, or '
        'if no request was just made in a browser.',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(
            child: DefaultTextStyle.merge(
              style: const TextStyle(letterSpacing: 3),
              child: Text(Pkce.checkCode(challenge)).header.mono.selectable,
            ),
          ),
        ),
      ],
    );
  }
}
