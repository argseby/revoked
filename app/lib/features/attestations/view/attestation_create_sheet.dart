import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/attestation_ask.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/widgets/tool_proposal_alert.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/qr_sheet.dart';
import 'package:revoked_app/features/attestations/store/attestations_store.dart';
import 'package:revoked_app/features/vault/view/record_composer.dart';

/// Writes a new attestation: what kind of statement it is, what it states,
/// and optionally for whom and for how long.
///
/// Creating it signs nothing yet. It makes an offer with a one-time link; the
/// credential is issued when its subject accepts the offer and proves the
/// identity it is issued to.
///
/// Opened from someone's ask, it starts filled in from that ask.
Future<void> showAttestationCreateSheet(
  BuildContext context, {
  AttestationAsk? ask,
}) {
  return showAppSheet(
    context: context,
    panelWidth: vaultComposerWidth,
    builder: (_) => _AttestationCreateSheet(ask: ask),
  );
}

class _AttestationCreateSheet extends StatefulWidget {
  final AttestationAsk? ask;

  const _AttestationCreateSheet({this.ask});

  @override
  State<_AttestationCreateSheet> createState() =>
      _AttestationCreateSheetState();
}

class _AttestationCreateSheetState extends State<_AttestationCreateSheet> {
  AttestationsStore get _store => Stores.attestations;

  @override
  void initState() {
    super.initState();
    _store.resetDraft(ask: widget.ask);
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
      AppToast.error(
        context,
        'The offer was created, but its link was not returned. Withdraw it '
        'and create a new one.',
      );
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
        maxHeight: composerMaxHeight(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VaultComposerHeader(
            title: 'Issue an attestation',
            area: 'Attestations',
            areaIcon: AppIcons.attestation,
            subtitle:
                'Issued in the name of this workspace’s domain. The '
                'recipient reviews every detail before accepting.',
            onClose: _store.isCreating
                ? null
                : () => Navigator.of(context).pop(),
          ),
          if (_store.draftAsk case final ask? when !ask.proposer.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                0,
                AppSpacing.xxl,
                AppSpacing.md,
              ),
              child: ToolProposalAlert(proposer: ask.proposer),
            )
          else if (_store.draftAsk != null)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                0,
                AppSpacing.xxl,
                AppSpacing.md,
              ),
              child: AppAlert(
                leading: Icon(AppIcons.askFor),
                title: Text('Filled in from a request'),
                content: Text(
                  'Verify who sent the request. Enter only values that '
                  'can be confirmed.',
                ),
              ),
            ),
          const AppDivider(),
          Flexible(
            child: AppComposerSections(
              enabled: !_store.isCreating,
              sections: [
                AppComposerSection(
                  title: 'Attestation',
                  icon: AppIcons.attestation,
                  children: [
                    AppComposerField(
                      label: 'Label (optional)',
                      child: AppTextField(
                        controller: _store.labelController,
                        hint: 'Membership 2026 — Ada',
                      ),
                    ),
                    AppComposerField(
                      label: 'Kind',
                      explanation: 'What kind of statement this is',
                      child: AppTextField(
                        controller: _store.typeController,
                        hint: 'membership',
                        mono: true,
                      ),
                    ),
                  ],
                ),
                AppComposerSection(
                  title: 'Details',
                  icon: AppIcons.cardList,
                  children: [
                    for (final claim in _store.draftClaims)
                      _ClaimRow(
                        key: ObjectKey(claim),
                        claim: claim,
                        onRemove: () => _store.removeClaim(claim),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxl,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AppButton(
                          icon: AppIcons.plus,
                          label: 'Add detail',
                          style: AppButtonStyle.ghost,
                          size: AppButtonSize.small,
                          onTap: _store.addClaim,
                        ),
                      ),
                    ),
                  ],
                ),
                AppComposerSection(
                  title: 'Recipient',
                  icon: AppIcons.person,
                  children: [
                    AppComposerField(
                      label: 'Recipient fingerprint (optional)',
                      explanation:
                          'Without a fingerprint, the first identity to open '
                          'the link can accept it. With one, only that '
                          'identity can.',
                      child: AppTextField(
                        controller: _store.subjectController,
                        hint: '64-character fingerprint',
                        mono: true,
                      ),
                    ),
                    AppComposerField(
                      label: 'Validity in days (optional)',
                      child: AppTextField(
                        controller: _store.validDaysController,
                        hint: 'Empty means valid until revoked',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                AppComposerSection(
                  title: 'Access',
                  icon: AppIcons.group,
                  children: [
                    AppComposerVisibility(
                      field: VisibleToField(
                        showLabel: false,
                        value: _store.draftVisibility,
                        suggestedByTool:
                            (_store.draftAsk?.visibility ?? '').isNotEmpty,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.md,
                AppSpacing.xxl,
                0,
              ),
              child: AppAlert(
                destructive: true,
                title: Text(error.title),
                content: Text(error.description).small,
              ),
            ),
          const AppDivider(),
          AppComposerFooter(
            label: 'Create offer',
            icon: AppIcons.arrowRight,
            busy: _store.isCreating,
            onSubmit: _store.isCreating ? null : _submit,
            onCancel: _store.isCreating
                ? null
                : () => Navigator.of(context).pop(),
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
      builder: (_) => AppComposerCard(
        title: 'Detail',
        trailing: AppButton(
          icon: AppIcons.x,
          tooltip: 'Remove detail',
          style: AppButtonStyle.ghost,
          size: AppButtonSize.small,
          onTap: onRemove,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppComposerSubLabel('Name'),
            AppTextField(
              controller: claim.name,
              hint: 'age_over_18',
              mono: true,
            ),
            AppSpacing.gapMd,
            const AppComposerSubLabel('Value'),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppSegmented<ClaimKind>(
                value: claim.kind,
                items: [
                  for (final kind in ClaimKind.values)
                    AppSegmentedItem(value: kind, label: kind.label),
                ],
                onChanged: (kind) => claim.kind = kind,
              ),
            ),
            AppSpacing.gapSm,
            claim.kind == ClaimKind.yesNo
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
                    hint: claim.kind == ClaimKind.number ? 'A number' : 'Value',
                    keyboardType: claim.kind == ClaimKind.number
                        ? const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          )
                        : null,
                  ),
          ],
        ),
      ),
    );
  }
}

/// The offer's link is shown once. The server keeps only a hash of its token,
/// so a link that is not passed on here cannot be recovered — the offer is
/// withdrawn and made again instead.
Future<void> _showLinkDialog(BuildContext context, String token) {
  return showQrSheet(
    context: context,
    title: 'Offer created',
    link: DeepLinks.attestation(token, origin: Stores.api.originAuthority),
    message:
        'The code can be scanned or the link sent. It is shown once and '
        'cannot be retrieved later.',
    dismissible: false,
  );
}
