import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/utils/pkce.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';

/// What a connected tool may do, as one list of switches — the same on the
/// connect screen, on a proposal that connects, and under Connected tools, so
/// what the owner agreed to is what they later read. The tool's own reasons
/// and what it can never reach sit under the list.
class ToolPermissions extends StatelessWidget {
  final String name;

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

  /// Whether the tool may add records to its section, not only read it.
  final bool sectionWrite;
  final ValueChanged<bool>? onSectionWrite;

  /// Why the tool asks, in its own words.
  final ToolReasons reasons;

  const ToolPermissions({
    super.key,
    required this.name,
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

  /// The icon, label and line for a permission, said for a tool rather than
  /// a member. The label falls back to the catalogue's own name for a key
  /// the catalogue hasn't served yet, never the raw key.
  (IconData, String, String) _detail(InvitePermission p) {
    String label(String fallback) => p.label == p.key ? fallback : p.label;
    return switch (p.key) {
      'shares:manage' => (
        AppIcons.share,
        label('Manage shares'),
        showVault && allowVaultRead
            ? 'Within your vault'
            : 'Within its section',
      ),
      'requests:manage' => (
        AppIcons.askFor,
        label('Manage requests'),
        'In your name',
      ),
      'attestations:issue' => (
        AppIcons.shieldCheck,
        label('Issue attestations'),
        'Attestations it proposed',
      ),
      _ => (AppIcons.shieldCheck, p.label, p.description),
    };
  }

  String get _noAccess {
    if (showVault && allowVaultRead) {
      return 'No access to your links or your account.';
    }
    if (showSection && ownSection) {
      return 'No access to the rest of your vault, your links or your account.';
    }
    return 'No access to your vault, your links or your account.';
  }

  @override
  Widget build(BuildContext context) {
    Widget toggle({
      required IconData icon,
      required String label,
      required String subtitle,
      required bool value,
      required ValueChanged<bool>? onChanged,
      bool sensitive = false,
    }) => AppFormToggleRow(
      icon: icon,
      label: label,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
      badge: sensitive ? 'Sensitive' : null,
      badgeVariant: AppBadgeVariant.destructive,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    );
    final own = [
      for (final key in onItsOwn)
        for (final p in permissions)
          if (p.key == key) p,
    ];
    final said = [
      reasons.section,
      reasons.permissions,
      reasons.revoke,
      reasons.links,
      if (showVault) reasons.vault,
    ].where((r) => r.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListGroup(
          title: 'Permissions',
          trailing: const SizedBox.shrink(),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final reason in said) ...[
                Text('$name says: “$reason”').muted.small.italic,
                AppSpacing.gapXs,
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(AppIcons.lock, size: 16),
                  AppSpacing.gapSm,
                  Expanded(child: Text(_noAccess)),
                ],
              ),
              AppSpacing.gapXs,
              const Text(
                'The connection ends after 90 days unless you connect again.',
              ),
            ],
          ),
          children: [
            if (showSection) ...[
              toggle(
                icon: sectionIsNew ? AppIcons.folderPlus : AppIcons.folder,
                label: 'Vault section',
                subtitle: sectionIsNew ? '$sectionName · new' : sectionName,
                value: ownSection,
                onChanged: onOwnSection,
              ),
              if (ownSection)
                Padding(
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
                        value: sectionWrite,
                        items: const [
                          AppSegmentedItem(
                            value: false,
                            icon: AppIcons.eye,
                            label: 'Read',
                          ),
                          AppSegmentedItem(
                            value: true,
                            icon: AppIcons.pencil,
                            label: 'Manage',
                          ),
                        ],
                        onChanged: (v) => onSectionWrite?.call(v),
                      ),
                      AppSpacing.gapSm,
                      Text(
                        sectionWrite
                            ? 'It can add records here, and change or delete '
                                  'the ones it added. Records you add stay '
                                  'as they are.'
                            : 'It sees what you put here. It can’t add, '
                                  'change or delete anything.',
                      ).muted.small,
                    ],
                  ),
                ),
            ],
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
            toggle(
              icon: AppIcons.linkSlash,
              label: 'Revoke its links',
              subtitle: 'Links and requests it proposed',
              value: allowRevoke,
              onChanged: onAllowRevoke,
            ),
            toggle(
              icon: AppIcons.send,
              label: 'Receive links',
              subtitle: 'Links it proposed, once created',
              value: allowHandOver,
              onChanged: onAllowHandOver,
            ),
            if (showVault)
              toggle(
                icon: AppIcons.safe,
                label: 'Read vault',
                subtitle: 'Every record except encrypted ones',
                value: allowVaultRead,
                sensitive: true,
                onChanged: onAllowVaultRead,
              ),
          ],
        ),
        if (showVault) ...[VaultReadNotice(name: name), AppSpacing.gapLg],
      ],
    );
  }
}

/// What letting a tool read the vault means, said before the owner decides.
/// Once a value leaves, nothing in Revoked can call it back.
class VaultReadNotice extends StatelessWidget {
  final String name;

  const VaultReadNotice({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return AppAlert(
      tone: AppAlertTone.warning,
      leading: const Icon(AppIcons.exclamationTriangle),
      title: const Text('What reading your vault means'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$name sees the value of any record it opens.'),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'What it sees leaves Revoked. Revoking or disconnecting later '
            'can’t take it back.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'If it’s an AI assistant, the company that runs the AI gets what '
            'it sees, too.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Only allow this for an assistant you started yourself, on this '
            'device.',
          ),
        ],
      ),
    );
  }
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
        'Must match the code on the $name page. If it doesn’t, or you didn’t '
        'just ask for this in a browser, decline.',
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
