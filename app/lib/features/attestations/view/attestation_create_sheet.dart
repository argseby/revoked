import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/attestations/store/attestations_store.dart';

/// Writes a new attestation: what kind of statement it is, what it states,
/// and optionally for whom and for how long.
///
/// Creating it signs nothing yet. It makes an offer with a one-time link; the
/// credential is issued when its subject accepts the offer and proves the
/// identity it is issued to.
Future<void> showAttestationCreateSheet(BuildContext context) {
  return showAppSheet(
    context: context,
    builder: (_) => const _AttestationCreateSheet(),
  );
}

class _AttestationCreateSheet extends StatefulWidget {
  const _AttestationCreateSheet();

  @override
  State<_AttestationCreateSheet> createState() =>
      _AttestationCreateSheetState();
}

class _AttestationCreateSheetState extends State<_AttestationCreateSheet> {
  AttestationsStore get _store => Stores.attestations;

  @override
  void initState() {
    super.initState();
    _store.resetDraft();
  }

  Future<void> _submit() async {
    final problem = _store.draftProblem;
    if (problem != null) {
      AppToast.error(context, problem);
      return;
    }
    final ok = await _store.create();
    if (!mounted || !ok) return;

    final token = _store.lastCreatedToken;
    if (token == null || token.isEmpty) {
      AppToast.error(context, 'The offer was created but no link came back.');
      return;
    }
    final navigator = Navigator.of(context);
    final root = navigator.context;
    navigator.pop();
    if (root.mounted) await _showLinkDialog(root, token);
  }

  @override
  Widget build(BuildContext context) {
    // Every keystroke can change whether the draft can be issued.
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final error = _store.createError;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxs,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Attest something').header,
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  'A statement about someone\'s identity, signed in the name '
                  'of this server\'s domain. Its subject sees every claim '
                  'before accepting it.',
                ).muted.small,
              ],
            ),
          ),
          const AppDivider(),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppFormSectionHeader('What kind of statement'),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenH(context),
                    ),
                    child: Column(
                      children: [
                        AppTextField(
                          controller: _store.typeController,
                          label: 'Type',
                          hint: 'e.g. membership',
                          mono: true,
                        ),
                        AppSpacing.gapSm,
                        AppTextField(
                          controller: _store.labelController,
                          label: 'Name in your list (optional)',
                          hint: 'e.g. Membership 2026 — Ada',
                        ),
                      ],
                    ),
                  ),
                  const AppFormSectionHeader('What it states'),
                  for (final claim in _store.draftClaims)
                    _ClaimRow(
                      key: ObjectKey(claim),
                      claim: claim,
                      onRemove: () => _store.removeClaim(claim),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenH(context),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        icon: AppIcons.plus,
                        label: 'Another claim',
                        style: AppButtonStyle.ghost,
                        size: AppButtonSize.small,
                        onTap: _store.addClaim,
                      ),
                    ),
                  ),
                  const AppFormSectionHeader('For whom, and how long'),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenH(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextField(
                          controller: _store.subjectController,
                          label: 'Only for this identity (optional)',
                          hint: 'Fingerprint, 64 hexadecimal characters',
                          mono: true,
                        ),
                        AppSpacing.gapXs,
                        const Text(
                          'Left empty, whoever opens the link first accepts '
                          'it with an identity of theirs. With a fingerprint '
                          '— from a request someone answered with a proven '
                          'identity — only that identity can.',
                        ).muted.small,
                        AppSpacing.gapSm,
                        AppTextField(
                          controller: _store.validDaysController,
                          label: 'Valid for, in days (optional)',
                          hint: 'Left empty, it is valid until revoked',
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.md,
                        AppSpacing.xl,
                        0,
                      ),
                      child: AppAlert(
                        destructive: true,
                        title: Text(error.title),
                        content: Text(error.description).small,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
          const AppDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    style: AppButtonStyle.accent,
                    onTap: _store.isCreating
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    icon: AppIcons.plus,
                    label: 'Create offer',
                    busy: _store.isCreating,
                    onTap: _store.isCreating ? null : _submit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One claim of the draft: its name, what kind of value it is, and the value.
class _ClaimRow extends StatelessWidget {
  final ClaimDraft claim;
  final VoidCallback onRemove;

  const _ClaimRow({super.key, required this.claim, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenH(context),
          0,
          AppSpacing.screenH(context),
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: claim.name,
                    label: 'Claim',
                    hint: 'e.g. age_over_18',
                    mono: true,
                  ),
                ),
                AppSpacing.gapSm,
                AppButton(
                  icon: AppIcons.x,
                  tooltip: 'Remove this claim',
                  style: AppButtonStyle.ghost,
                  size: AppButtonSize.small,
                  onTap: onRemove,
                ),
              ],
            ),
            AppSpacing.gapXs,
            Row(
              children: [
                AppSegmented<ClaimKind>(
                  value: claim.kind,
                  items: [
                    for (final kind in ClaimKind.values)
                      AppSegmentedItem(value: kind, label: kind.label),
                  ],
                  onChanged: (kind) => claim.kind = kind,
                ),
                AppSpacing.gapSm,
                Expanded(
                  child: claim.kind == ClaimKind.yesNo
                      ? Row(
                          children: [
                            AppSwitch(
                              value: claim.yes,
                              onChanged: (v) => claim.yes = v,
                            ),
                            AppSpacing.gapSm,
                            Text(claim.yes ? 'Yes' : 'No'),
                          ],
                        )
                      : AppTextField(
                          controller: claim.value,
                          hint: claim.kind == ClaimKind.number
                              ? 'A number'
                              : 'The value',
                          keyboardType: claim.kind == ClaimKind.number
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                )
                              : null,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The offer's link is shown once. The server keeps only a hash of its token,
/// so a link that is not copied here cannot be recovered — the offer is
/// withdrawn and made again instead.
Future<void> _showLinkDialog(BuildContext context, String token) async {
  final link = DeepLinks.attestation(token, origin: Stores.api.originAuthority);
  final copy = await showAppDialog(
    context: context,
    title: 'Send this link to its subject',
    message:
        'It is shown once and cannot be retrieved later. Whoever opens it '
        'sees what would be attested and accepts it with an identity of '
        'their own.',
    content: SelectableText(link),
    confirmLabel: 'Copy link',
    confirmIcon: AppIcons.copy,
    cancelLabel: 'Done',
  );
  if (copy) await Clipboard.setData(ClipboardData(text: link));
}
