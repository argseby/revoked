import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/utils/pkce.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';

/// What a connected tool may do — the same groups on the connect screen, on a
/// proposal that connects, and under Connected tools, so what the owner agreed
/// to is what they later read:
///
///  * what every connected tool can do (nothing to choose),
///  * its own section of the vault, and whether it may add there,
///  * what it may do with what it suggested,
///  * what it may do on its own, without asking each time,
///  * the whole vault, only when the tool asked for it,
///  * what no tool can ever do.
///
/// Each choice carries the tool's own reason in italics.
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

  /// The keys a tool acts on by itself, in the order they are offered.
  static const onItsOwn = [
    'shares:manage',
    'requests:manage',
    'attestations:issue',
  ];

  /// What each of those means for a tool, in place of the catalogue's words,
  /// which are about a member.
  static (IconData, String, String) _wording(InvitePermission p) =>
      switch (p.key) {
        'shares:manage' => (
          AppIcons.share,
          'Share what it can read',
          'You see every share in the app, and can stop it.',
        ),
        'requests:manage' => (
          AppIcons.askFor,
          'Ask people for data in your name',
          'You see every request in the app. Only when you confirm on this '
              'device, never with a code.',
        ),
        _ => (AppIcons.shieldCheck, p.label, p.description),
      };

  String? _reason(String reason) =>
      reason.isEmpty ? null : '$name says: “$reason”';

  Widget _sectionDetail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!ownSection) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: const Text(
          'Nothing in your vault is shared with it.',
        ).muted.small,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sectionIsNew ? AppIcons.folderPlus : AppIcons.folder,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              AppSpacing.gapSm,
              Expanded(
                child: Text(
                  sectionIsNew
                      ? 'New section: $sectionName'
                      : 'Section: $sectionName',
                ).small,
              ),
            ],
          ),
          AppSpacing.gapSm,
          AppSegmented<bool>(
            value: sectionWrite,
            items: const [
              AppSegmentedItem(value: false, label: 'It can read'),
              AppSegmentedItem(value: true, label: 'Read and add'),
            ],
            onChanged: (v) => onSectionWrite?.call(v),
          ),
          AppSpacing.gapXs,
          Text(
            sectionWrite
                ? 'It adds records and changes only the ones it added. What '
                      'you put in the section stays yours.'
                : 'It only reads what is in the section. You add the records.',
          ).muted.small,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(IconData icon, String text, {bool allowed = true}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: allowed ? scheme.primary : scheme.onSurfaceVariant,
          ),
          AppSpacing.gapMd,
          Expanded(child: allowed ? Text(text) : Text(text).muted),
        ],
      ),
    );
    Widget choice(AppCheckRow check) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: check,
    );
    const quiet = SizedBox.shrink();
    final own = [
      for (final key in onItsOwn)
        for (final p in permissions)
          if (p.key == key) p,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListGroup(
          title: '$name can',
          trailing: quiet,
          children: [
            row(
              AppIcons.check,
              'Suggest links, requests and attestations for you to confirm',
            ),
            row(
              AppIcons.check,
              'See how what it suggested is going, and what people showed '
              'for its checks',
            ),
          ],
        ),
        if (showSection)
          AppListGroup(
            title: 'Its own section in your vault',
            trailing: quiet,
            children: [
              choice(
                AppCheckRow(
                  icon: AppIcons.folderPlus,
                  label: 'Give it a section',
                  subtitle:
                      'It keeps what it saves for you there. It can’t see the '
                      'rest of your vault.',
                  note: _reason(reasons.section),
                  value: ownSection,
                  onChanged: onOwnSection,
                ),
              ),
              _sectionDetail(context),
            ],
          ),
        AppListGroup(
          title: 'What it suggests',
          trailing: quiet,
          children: [
            choice(
              AppCheckRow(
                icon: AppIcons.xCircle,
                label: 'Let it end what it suggested',
                subtitle:
                    'It can turn off a share or request that came from it, '
                    'like when you throw away the printed card.',
                note: _reason(reasons.revoke),
                value: allowRevoke,
                onChanged: onAllowRevoke,
              ),
            ),
            choice(
              AppCheckRow(
                icon: AppIcons.send,
                label: 'Send it the finished link',
                subtitle:
                    'When you create a share it suggested, the tool gets the '
                    'link, so you don’t copy it over. Links with files or '
                    'hidden values you always send yourself.',
                note: _reason(reasons.links),
                value: allowHandOver,
                onChanged: onAllowHandOver,
              ),
            ),
          ],
        ),
        if (own.isNotEmpty)
          AppListGroup(
            title: 'On its own, without asking you',
            trailing: quiet,
            children: [
              for (final (i, p) in own.indexed)
                choice(
                  AppCheckRow(
                    icon: _wording(p).$1,
                    label: _wording(p).$2,
                    subtitle: _wording(p).$3,
                    note: i == 0 ? _reason(reasons.permissions) : null,
                    value: granted.contains(p.key),
                    onChanged: onPermission == null
                        ? null
                        : (v) => onPermission!(p.key, v),
                  ),
                ),
            ],
          ),
        if (showVault) ...[
          AppListGroup(
            title: 'Your whole vault',
            trailing: quiet,
            children: [
              choice(
                AppCheckRow(
                  icon: AppIcons.safe,
                  label: 'Read your vault',
                  subtitle:
                      'See the values of your records, to answer your '
                      'questions. Encrypted records stay hidden.',
                  note: _reason(reasons.vault),
                  value: allowVaultRead,
                  onChanged: onAllowVaultRead,
                ),
              ),
            ],
          ),
          VaultReadNotice(name: name),
          AppSpacing.gapLg,
        ],
        AppListGroup(
          title: '$name can never',
          trailing: quiet,
          footer: const Text(
            'The connection ends after 90 days unless you connect again.',
          ),
          children: [
            if (!(showVault && allowVaultRead))
              row(AppIcons.x, 'See the rest of your vault', allowed: false),
            row(
              AppIcons.x,
              ownSection || (showVault && allowVaultRead)
                  ? 'Change records you added'
                  : 'Change your vault',
              allowed: false,
            ),
            row(
              AppIcons.x,
              'See your other links or your account',
              allowed: false,
            ),
            if (!granted.contains('shares:manage'))
              row(
                AppIcons.x,
                'Publish a link without your consent',
                allowed: false,
              ),
          ],
        ),
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
    final scheme = Theme.of(context).colorScheme;
    return AppListGroup(
      title: 'Check the code',
      trailing: const SizedBox.shrink(),
      footer: const Text(
        'Only continue if both codes match. If you didn’t just ask for this '
        'in a browser, decline.',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(AppIcons.shieldCheck, size: 20, color: scheme.primary),
              AppSpacing.gapMd,
              Expanded(
                child: Text(
                  'The $name page you came from shows this code',
                ).muted.small,
              ),
              AppSpacing.gapMd,
              DefaultTextStyle.merge(
                style: const TextStyle(letterSpacing: 1.5),
                child: Text(Pkce.checkCode(challenge)).header.mono,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
