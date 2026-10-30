import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/attestation_check.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_qr_code.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/attestations/claim_text.dart';
import 'package:revoked_app/features/attestations/view/verdict_badge.dart';

/// Asks someone to show an attestation: what kind, from which attesters,
/// which claims. Once made, the same sheet shows the code to scan, waits for
/// the answer, and shows what was shown.
Future<void> openAttestationCheckSheet(BuildContext context) async {
  Stores.attestationChecks.resetForm();
  await showAppSheet(context: context, builder: (_) => const _CheckSheet());
  Stores.attestationChecks.closePending();
}

class _CheckSheet extends StatelessWidget {
  const _CheckSheet();

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final store = Stores.attestationChecks;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxs,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: store.pending == null
                ? const _Form()
                : _HandOver(check: store.pending!, link: store.pendingLink),
          ),
        );
      },
    );
  }
}

class _Form extends StatelessWidget {
  const _Form();

  Future<void> _create(BuildContext context) async {
    final primary = Stores.identities.primaryIdentity;
    await Stores.attestationChecks.create(
      identityId: primary == null || primary.isRevoked ? null : primary.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.attestationChecks;
    final error = store.createError;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('See someone\'s attestation').header,
        AppSpacing.gapXxs,
        const Text(
          'Ask someone to show you an attestation, like a membership. They '
          'choose what you see. You get a checked answer.',
        ).muted.small,
        AppSpacing.gapLg,
        AppTextField(
          controller: store.typeController,
          label: 'What kind (optional)',
          hint: 'e.g. membership',
          mono: true,
        ),
        AppSpacing.gapSm,
        AppTextField(
          controller: store.issuersController,
          label: 'Confirmed by (optional)',
          hint: 'e.g. chess-club.org',
          mono: true,
        ),
        AppSpacing.gapSm,
        AppTextField(
          controller: store.claimsController,
          label: 'Details you need (optional)',
          hint: 'e.g. member_since, board',
          mono: true,
        ),
        if (error != null) ...[
          AppSpacing.gapMd,
          AppAlert(
            destructive: true,
            title: Text(error.title),
            content: Text(error.description).small,
          ),
        ],
        AppSpacing.gapLg,
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Cancel',
                style: AppButtonStyle.accent,
                onTap: store.isCreating
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
            ),
            AppSpacing.gapMd,
            Expanded(
              child: AppButton(
                icon: AppIcons.qrCode,
                label: 'Create check',
                busy: store.isCreating,
                onTap: store.isCreating ? null : () => _create(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HandOver extends StatelessWidget {
  final AttestationCheck check;
  final String? link;

  const _HandOver({required this.check, required this.link});

  @override
  Widget build(BuildContext context) {
    final answered = check.isAnswered;
    final waiting = check.isWaiting(DateTime.now());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          answered
              ? 'What they showed'
              : waiting
              ? 'Show this to them'
              : 'No answer in time',
        ).header,
        AppSpacing.gapXxs,
        if (answered)
          const Text(
            'Checked the moment it arrived. This is how it stood then.',
          ).muted.small
        else if (waiting) ...[
          const Text(
            'They scan it with Revoked or open the link. It works once, for '
            'ten minutes.',
          ).muted.small,
          AppSpacing.gapLg,
          if (link != null) Center(child: AppQrCode(data: link!, size: 220)),
          AppSpacing.gapMd,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppSpinner(),
              AppSpacing.gapSm,
              Flexible(
                child: Text(
                  'Waiting for an answer until '
                  '${momentText(check.expiresAt).split(' ').last}',
                ).muted.small,
              ),
            ],
          ),
        ] else
          const Text(
            'No one answered within ten minutes. Create a new check to try '
            'again.',
          ).muted.small,
        if (answered) ...[AppSpacing.gapLg, CheckResultView(check: check)],
        AppSpacing.gapLg,
        Row(
          children: [
            if (waiting && link != null) ...[
              Expanded(
                child: AppButton(
                  icon: AppIcons.copy,
                  label: 'Copy link',
                  style: AppButtonStyle.accent,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: link!));
                    AppToast.success(context, 'Link copied');
                  },
                ),
              ),
              AppSpacing.gapMd,
            ],
            Expanded(
              child: AppButton(
                icon: waiting ? null : AppIcons.check,
                label: waiting ? 'Stop waiting' : 'Done',
                style: waiting ? AppButtonStyle.accent : AppButtonStyle.primary,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What an answered check found: the verdict as a pill, who attested what,
/// the claims shown, and how many were withheld.
class CheckResultView extends StatelessWidget {
  final AttestationCheck check;

  const CheckResultView({super.key, required this.check});

  @override
  Widget build(BuildContext context) {
    final result = check.result!;
    final verdict = result.verdict;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListCard(
          children: [
            AppDetailRow(
              icon: AppIcons.shieldCheck,
              label: 'Status',
              badge: verdictBadge(context, verdict),
            ),
            AppDetailRow(
              icon: AppIcons.tag,
              label: 'What',
              value: result.type.isEmpty ? check.title : result.type,
            ),
            AppDetailRow(
              icon: AppIcons.attestation,
              label: 'Confirmed by',
              value: result.issuer.isEmpty ? '—' : result.issuer,
            ),
            AppDetailRow(
              icon: AppIcons.personBoundingBox,
              label: 'Shown by',
              value: result.shownBy,
            ),
            AppDetailRow(
              icon: AppIcons.clock,
              label: 'Checked',
              value: momentText(check.answeredAt),
            ),
          ],
        ),
        if (verdict.reason.isNotEmpty) ...[
          AppSpacing.gapSm,
          Text(verdict.reason).muted.small,
        ],
        AppSpacing.gapMd,
        const Text('What they showed'),
        AppSpacing.gapSm,
        AppListCard(
          children: [
            if (result.claims.isEmpty)
              const AppDetailRow(
                icon: AppIcons.info,
                label: 'Nothing beyond what kind it is.',
              )
            else
              for (final e in result.claims.entries)
                AppDetailRow(label: e.key, value: claimText(e.value)),
            if (result.withheld > 0)
              AppDetailRow(
                icon: AppIcons.eyeSlash,
                label: 'Withheld',
                value: result.withheld == 1
                    ? '1 detail'
                    : '${result.withheld} details',
              ),
          ],
        ),
      ],
    );
  }
}
