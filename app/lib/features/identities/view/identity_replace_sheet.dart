import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_create_sheet.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/features/identities/store/identity_replacement_store.dart';

/// Opens the replacement of [identity]: another identity takes its place,
/// its attestations move there, and it is revoked.
Future<void> openIdentityReplaceSheet(
  BuildContext context,
  Identity identity,
) => showAppCreateSheet(
  context,
  label: 'Replace identity',
  onOpen: () => Stores.identityReplacement.begin(identity),
  form: (close) => _ReplaceIdentitySheet(onClose: close),
);

/// The select's value for "a new identity", which has no id yet.
const _newIdentity = '';

String _attestations(int n) => n == 1 ? '1 attestation' : '$n attestations';

class _ReplaceIdentitySheet extends StatelessWidget {
  final VoidCallback onClose;

  const _ReplaceIdentitySheet({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final store = Stores.identityReplacement;
    final old = store.from;
    if (old == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Replace ${old.name}').header,
          const SizedBox(height: AppSpacing.xs),
          if (store.stage == ReplacementStage.choosing)
            ..._choosing(store, old)
          else
            ..._progress(context, store, old),
        ],
      ),
    );
  }

  List<Widget> _choosing(IdentityReplacementStore store, Identity old) {
    final bound = store.bound.length;
    return [
      Text(
        'Another identity takes its place. Each attestation bound to '
        '${old.name} is issued again for it, with ${old.name}\'s key on this '
        'device vouching for the new one, and ${old.name} is then revoked. '
        'No issuer has to do anything.',
      ).muted.small,
      const SizedBox(height: AppSpacing.sm),
      Text(
        bound == 0
            ? 'No attestations are bound to ${old.name}.'
            : '${_attestations(bound)} will move.',
      ).small,
      const SizedBox(height: AppSpacing.lg),
      if (store.targets.isNotEmpty) ...[
        const Text('Replaced by').small,
        const SizedBox(height: AppSpacing.xs),
        AppSelect<String>(
          value: store.targetId ?? _newIdentity,
          items: [
            const AppSelectItem(_newIdentity, Text('A new identity')),
            for (final t in store.targets)
              AppSelectItem(t.id, Text('${t.name} · ${t.shortFingerprint}')),
          ],
          onChanged: (v) =>
              store.chooseTarget(v == null || v == _newIdentity ? null : v),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (store.targetId == null) ...[
        Row(
          children: [
            Flexible(child: const Text('Name of the new identity').small),
            if (store.nameController.text.trim().isEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              const AppRequiredBadge(),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        AppTextField(
          controller: store.nameController,
          hint: 'e.g. Personal, New laptop',
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      if (store.errorMessage != null) ...[
        AppErrorText(store.errorMessage!),
        const SizedBox(height: AppSpacing.md),
      ],
      Row(
        children: [
          Expanded(
            child: AppButton(
              label: 'Cancel',
              style: AppButtonStyle.accent,
              onTap: onClose,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AppButton(
              icon: AppIcons.arrowRepeat,
              label: 'Replace',
              onTap: store.problem == null ? store.start : null,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _progress(
    BuildContext context,
    IdentityReplacementStore store,
    Identity old,
  ) {
    final next = store.to?.name ?? 'the new identity';
    final total =
        store.moved.length + store.failed.length + store.pending.length;
    final String status;
    switch (store.stage) {
      case ReplacementStage.moving:
        status = 'Moving attestations to $next…';
      case ReplacementStage.review when store.failed.isNotEmpty:
        status =
            '${_attestations(store.failed.length)} of $total stayed on '
            '${old.name}. Retrying moves them once their issuer answers. '
            'Revoking ${old.name} now ends them. Leaving it for now keeps '
            '${old.name} standing, and replacing it with $next later moves '
            'the rest.';
      case ReplacementStage.review:
        status =
            'Every attestation moved to $next, but ${old.name} is not '
            'revoked yet.';
      case ReplacementStage.done:
        status = store.moved.isEmpty
            ? '${old.name} is revoked; $next takes its place.'
            : '${old.name} is revoked, and ${_attestations(store.moved.length)} '
                  'now belong to $next.';
      case ReplacementStage.choosing:
        status = '';
    }
    return [
      Text(status).muted.small,
      const SizedBox(height: AppSpacing.md),
      if (total > 0)
        AppListGroup(
          title: 'Attestations',
          children: [
            for (final c in store.moved)
              AppListRow(
                icon: AppIcons.checkCircle,
                title: _title(c),
                subtitle: 'Moved · ${c.issuer}',
                showChevron: false,
              ),
            for (final f in store.failed)
              AppListRow(
                icon: AppIcons.exclamationTriangle,
                title: _title(f.credential),
                subtitle: '${f.credential.issuer} · ${f.reason}',
                showChevron: false,
              ),
            for (final c in store.pending)
              AppListRow(
                icon: AppIcons.hourglass,
                title: _title(c),
                subtitle: c.issuer,
                trailing: const AppSpinner(),
                showChevron: false,
              ),
          ],
        ),
      if (store.errorMessage != null) ...[
        AppErrorText(store.errorMessage!),
        const SizedBox(height: AppSpacing.md),
      ],
      const SizedBox(height: AppSpacing.md),
      ..._actions(context, store, old),
    ];
  }

  List<Widget> _actions(
    BuildContext context,
    IdentityReplacementStore store,
    Identity old,
  ) {
    switch (store.stage) {
      case ReplacementStage.moving:
        return [
          const AppButton(
            icon: AppIcons.arrowRepeat,
            label: 'Moving attestations',
            busy: true,
            onTap: null,
          ),
        ];
      case ReplacementStage.review:
        final left = store.failed.length;
        return [
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Not now',
                  style: AppButtonStyle.accent,
                  onTap: onClose,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  icon: AppIcons.shieldSlash,
                  label: left == 0 ? 'Revoke' : 'Revoke anyway',
                  style: AppButtonStyle.destructive,
                  onTap: () => _confirmRevoke(context, store, old, left),
                ),
              ),
              if (left > 0) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    icon: AppIcons.arrowClockwise,
                    label: 'Retry',
                    onTap: store.retry,
                  ),
                ),
              ],
            ],
          ),
        ];
      case ReplacementStage.done:
        return [AppButton(icon: AppIcons.check, label: 'Done', onTap: onClose)];
      case ReplacementStage.choosing:
        return const [];
    }
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    IdentityReplacementStore store,
    Identity old,
    int left,
  ) async {
    if (left > 0) {
      final confirmed = await showAppDialog(
        context: context,
        title: 'Revoke ${old.name} anyway?',
        message:
            'The ${_attestations(left)} that did not move stop being valid '
            'with it. Each would have to be asked for again from its issuer.\n\n'
            'This cannot be undone.',
        confirmLabel: 'Revoke',
        confirmIcon: AppIcons.shieldSlash,
        destructive: true,
      );
      if (!confirmed) return;
    }
    await store.revokeAnyway();
  }

  static String _title(Credential c) => c.type.isEmpty ? 'Attestation' : c.type;
}
