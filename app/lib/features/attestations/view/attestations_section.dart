import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/attestation_check.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/state/load_state.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/attestations/claim_text.dart';
import 'package:revoked_app/features/attestations/view/ask_attestation_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_check_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_create_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_share_sheet.dart';
import 'package:revoked_app/features/attestations/view/verdict_badge.dart';

/// A tab's list: one line on what it holds, then its rows. The tab names it,
/// so it carries no heading of its own. While there is nothing to list, the
/// tab shows [empty] instead, as every other list in the app does.
class _TabList extends StatelessWidget {
  final String intro;
  final LoadState state;
  final VoidCallback onRetry;
  final Widget empty;
  final List<Widget> children;

  const _TabList({
    required this.intro,
    required this.state,
    required this.onRetry,
    required this.empty,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return AppLoadFade(
      loading: () => children.isEmpty && state.isFirstLoad,
      skeleton: AppListSkeleton(
        intro: intro,
        rows: const [
          AppSkeletonRow(
            'Membership',
            'From a club',
            icon: AppIcons.shieldCheck,
            badge: 'Verified',
          ),
          AppSkeletonRow(
            'Employment',
            'From a company',
            icon: AppIcons.shieldCheck,
            badge: 'Verified',
          ),
        ],
      ),
      builder: (_) {
        final failure = state.error;
        if (children.isEmpty) {
          if (failure != null) {
            return AppLoadError(
              title: 'The list could not be loaded',
              message: failure,
              onRetry: onRetry,
            );
          }
          return empty;
        }
        return AppPageBody(
          children: [
            if (failure != null) ...[
              AppRefreshFailed(onRetry: onRetry),
              AppSpacing.gapLg,
            ],
            Text(intro).muted.small,
            AppSpacing.gapMd,
            AppListCard(children: children),
          ],
        );
      },
    );
  }
}

/// The credentials this person holds, each with what it states.
class HeldAttestations extends StatelessWidget {
  const HeldAttestations({super.key});

  String _identityName(Credential c) =>
      Stores.identities.byId(c.identity)?.name ?? 'an identity';

  @override
  Widget build(BuildContext context) {
    final store = Stores.credentials;
    return Observer(
      builder: (_) => _TabList(
        intro:
            'Attestations confirmed by others. Nothing is shown unless '
            'selected, detail by detail.',
        state: store.loadState,
        onRetry: store.load,
        empty: AppEmptyState(
          icon: AppIcons.attestation,
          title: 'No attestations held',
          subtitle:
              'Facts confirmed by a club, an employer or a verification '
              'service. Only selected details are ever shown.',
          example: const AppEmptyExample(
            title: 'membership',
            detail: 'From chess-club.org · member_since: 2021',
            badge: 'Verified',
          ),
          steps: const [
            AppEmptyStep('Request', 'A link from New → Attestation about you'),
            AppEmptyStep('Acceptance', 'Bound to one identity'),
            AppEmptyStep('Presentation', 'Selected details only'),
          ],
          action: AppButton(
            icon: AppIcons.askFor,
            label: 'Ask for one',
            onTap: () => openAskAttestationSheet(context),
          ),
        ),
        children: [
          for (final c in store.credentials)
            AppListRow(
              icon: AppIcons.shieldCheck,
              title: c.type,
              subtitleWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'From ${c.issuer} · held by ${_identityName(c)}',
                  ).muted.small,
                  if (c.disclosures.isNotEmpty)
                    Text(
                      [
                        for (final d in c.disclosures)
                          '${d.name}: ${claimText(d.value)}',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ).small,
                ],
              ),
              trailing: verdictBadge(context, store.verdicts[c.id]),
              onTap: () {
                store.loadShares(c.id);
                showAppSheet(
                  context: context,
                  dismissible: true,
                  builder: (_) => _CredentialSheet(
                    credential: c,
                    identityName: _identityName(c),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Everything one credential says, and the way to remove it.
class _CredentialSheet extends StatelessWidget {
  final Credential credential;
  final String identityName;

  const _CredentialSheet({
    required this.credential,
    required this.identityName,
  });

  Future<void> _remove(BuildContext context) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Remove this attestation?',
      message:
          'It is removed from this list. ${credential.issuer} has not revoked '
          'it and can offer it again.',
      confirmLabel: 'Remove',
      confirmIcon: AppIcons.trash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await Stores.credentials.remove(credential.id);
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      AppToast.success(context, 'Attestation removed');
    } else {
      AppToast.error(
        context,
        'The attestation could not be removed',
        subtitle: Stores.credentials.errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final verdict = Stores.credentials.verdicts[credential.id];
        final claims = credential.disclosures;
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(credential.type).header,
                AppSpacing.gapXxs,
                Text('Confirmed by ${credential.issuer}').muted.small,
                AppSpacing.gapMd,
                AppListCard(
                  children: [
                    AppDetailRow(
                      icon: AppIcons.shieldCheck,
                      label: 'Status',
                      value: verdict == null ? 'Checking…' : '',
                      badge: verdictBadge(context, verdict),
                    ),
                    AppDetailRow(
                      icon: AppIcons.personBoundingBox,
                      label: 'For',
                      value: identityName,
                    ),
                    AppDetailRow(
                      icon: AppIcons.calendar,
                      label: 'Issued',
                      value: dayText(credential.issuedAt),
                    ),
                    AppDetailRow(
                      icon: AppIcons.clock,
                      label: 'Valid until',
                      value: credential.expiresAt == null
                          ? 'Until revoked'
                          : dayText(credential.expiresAt),
                    ),
                  ],
                ),
                if (verdict != null && verdict.reason.isNotEmpty) ...[
                  AppSpacing.gapSm,
                  Text(verdict.reason).muted.small,
                ],
                AppSpacing.gapMd,
                const Text('Details'),
                AppSpacing.gapSm,
                AppListCard(
                  children: [
                    if (claims.isEmpty)
                      const AppDetailRow(
                        icon: AppIcons.info,
                        label: 'No details beyond the kind.',
                      )
                    else
                      for (final d in claims)
                        AppDetailRow(label: d.name, value: claimText(d.value)),
                  ],
                ),
                AppSpacing.gapMd,
                const Text('Links'),
                AppSpacing.gapSm,
                const Text(
                  'A link shows this attestation, with the details picked, to '
                  'whoever opens it, in the app or a browser. It proves what '
                  'the issuer attests. It does not prove that whoever passes '
                  'the link on is the holder: for that, the other person '
                  'makes a check under New → See someone\'s attestation.',
                ).muted.small,
                AppSpacing.gapSm,
                AttestationShareList(credential: credential),
                AppSpacing.gapSm,
                AppButton(
                  icon: AppIcons.link,
                  label: 'Share link',
                  style: AppButtonStyle.accent,
                  onTap: verdict == null || !verdict.isUnusable
                      ? () => openAttestationShareSheet(context, credential)
                      : null,
                ),
                AppSpacing.gapLg,
                AppButton(
                  icon: AppIcons.trash,
                  label: 'Remove attestation',
                  style: AppButtonStyle.destructive,
                  onTap: () => _remove(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The attestations this workspace issued.
class IssuedAttestations extends StatelessWidget {
  const IssuedAttestations({super.key});

  Future<void> _revoke(BuildContext context, Attestation a) async {
    final confirmed = await showAppDialog(
      context: context,
      title: a.isOffered ? 'Withdraw this offer?' : 'Revoke ${a.title}?',
      message: a.isOffered
          ? 'The link stops working. The offer has not been accepted.'
          : 'Anyone who checks it sees the revocation within minutes.\n\nThis '
                'cannot be undone. A new attestation can be issued instead.',
      confirmLabel: a.isOffered ? 'Withdraw' : 'Revoke',
      confirmIcon: AppIcons.xCircle,
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await Stores.attestations.revoke(a.id);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(
        context,
        a.isOffered ? 'Offer withdrawn' : 'Attestation revoked',
      );
    } else {
      AppToast.error(
        context,
        'The attestation could not be revoked',
        subtitle: Stores.attestations.error?.description,
      );
    }
  }

  Future<void> _delete(BuildContext context, Attestation a) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete ${a.title}?',
      message: a.isActive
          ? 'It is removed from this list and revoked, so it can no longer be '
                'used.'
          : 'It is removed from this list.',
      confirmLabel: 'Delete',
      confirmIcon: AppIcons.trash,
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await Stores.attestations.remove(a.id);
    if (!context.mounted || ok) return;
    AppToast.error(
      context,
      'The attestation could not be deleted',
      subtitle: Stores.attestations.error?.description,
    );
  }

  void _options(BuildContext context, Attestation a) {
    showAppOptionsSheet(
      context: context,
      title: a.title,
      subtitle: [
        a.type,
        for (final e in a.claims.entries) '${e.key}: ${claimText(e.value)}',
      ].join(' · '),
      actions: [
        if (!a.isRevoked)
          AppSheetAction(
            icon: AppIcons.shieldSlash,
            label: a.isOffered ? 'Withdraw offer' : 'Revoke',
            destructive: true,
            onTap: () => _revoke(context, a),
          ),
        AppSheetAction(
          icon: AppIcons.trash,
          label: 'Delete',
          destructive: true,
          onTap: () => _delete(context, a),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.attestations;
    return Observer(
      builder: (_) {
        final off = store.issuingAllowed == false;
        return _TabList(
          intro:
              'Attestations issued by this workspace in its domain’s name. '
              'Anyone who trusts the domain can rely on them.',
          state: store.loadState,
          onRetry: store.load,
          empty: off
              ? const AppEmptyState(
                  icon: AppIcons.attestation,
                  title: 'This server does not issue attestations',
                  subtitle:
                      'Issuing has been turned off by the operator. '
                      'Attestations from other issuers can still be held and '
                      'shown.',
                )
              : AppEmptyState(
                  icon: AppIcons.attestation,
                  title: 'No attestations issued',
                  subtitle:
                      'A membership, a role or another fact about someone, '
                      'confirmed in the domain’s name. The recipient holds it '
                      'and can show it anywhere.',
                  example: const AppEmptyExample(
                    title: 'Membership 2026 — Ada',
                    detail: 'membership · member_since: 2021',
                    badge: 'Issued',
                  ),
                  steps: const [
                    AppEmptyStep(
                      'Details',
                      'A kind and its details, such as member_since',
                    ),
                    AppEmptyStep('Offer', 'A code or a link, shown once'),
                    AppEmptyStep(
                      'Revocation',
                      'Visible to every check within minutes',
                    ),
                  ],
                  action: AppButton(
                    icon: AppIcons.attestation,
                    label: 'Issue attestation',
                    onTap: () => showAttestationCreateSheet(context),
                  ),
                ),
          children: [
            if (!off)
              for (final a in store.attestations)
                AppListRow(
                  icon: AppIcons.shieldLock,
                  title: a.title,
                  subtitle: issuedAttestationSubtitle(a),
                  trailing: issuedAttestationBadge(a),
                  onTap: () => _options(context, a),
                ),
          ],
        );
      },
    );
  }
}

/// The people this person asked to show an attestation, and what they
/// showed.
class CheckedAttestations extends StatelessWidget {
  const CheckedAttestations({super.key});

  void _open(BuildContext context, AttestationCheck c) {
    showAppSheet(
      context: context,
      dismissible: true,
      builder: (sheetContext) => SingleChildScrollView(
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
            Text(c.title).header,
            AppSpacing.gapXxs,
            Text(
              c.isAnswered
                  ? 'Verified on arrival. Reflects the state at that time.'
                  : 'This check was not answered.',
            ).muted.small,
            if (c.isAnswered) ...[AppSpacing.gapLg, CheckResultView(check: c)],
            AppSpacing.gapLg,
            AppButton(
              icon: AppIcons.trash,
              label: 'Delete check',
              style: AppButtonStyle.destructive,
              onTap: () async {
                final ok = await Stores.attestationChecks.remove(c.id);
                if (!sheetContext.mounted) return;
                if (ok) Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.attestationChecks;
    return Observer(
      builder: (_) => _TabList(
        intro:
            'Attestations shown by others in answer to a check. Each answer '
            'reflects the state at that moment.',
        state: store.loadState,
        onRetry: store.load,
        empty: AppEmptyState(
          icon: AppIcons.shieldCheck,
          title: 'No checks',
          subtitle:
              'A check asks someone to show an attestation from a club or an '
              'employer. The answer is verified on arrival.',
          example: const AppEmptyExample(
            title: 'membership',
            detail: 'Shown by 3fa2c1… · member_since: 2021',
            badge: 'Verified',
          ),
          steps: const [
            AppEmptyStep(
              'Request',
              'A code from New → See someone\'s attestation',
            ),
            AppEmptyStep('Selection', 'Made by the holder on their own device'),
            AppEmptyStep(
              'Verified answer',
              'Issuer, current validity and proof of ownership',
            ),
          ],
          action: AppButton(
            icon: AppIcons.shieldCheck,
            label: 'See someone\'s attestation',
            onTap: () => openAttestationCheckSheet(context),
          ),
        ),
        children: [
          for (final c in store.checks)
            AppListRow(
              icon: AppIcons.shieldCheck,
              title: c.title,
              subtitle: checkSubtitle(c),
              trailing: checkBadge(context, c),
              onTap: () => _open(context, c),
            ),
        ],
      ),
    );
  }
}

/// An issued attestation's one line in a list.
String issuedAttestationSubtitle(Attestation a) {
  if (a.isRevoked) {
    return a.subject.isEmpty
        ? 'Withdrawn before acceptance'
        : 'Revoked · ${a.subject}';
  }
  if (a.isOffered) {
    return 'Offered · open until ${dayText(a.offerExpiresAt)}';
  }
  return 'Held by ${a.subject}';
}

Widget? issuedAttestationBadge(Attestation a) {
  if (a.isRevoked) {
    return const AppBadge(icon: AppIcons.shieldSlash, label: 'Revoked');
  }
  if (a.isOffered) {
    return const AppBadge(
      icon: AppIcons.hourglass,
      label: 'Offered',
      variant: AppBadgeVariant.outline,
    );
  }
  return const AppBadge(icon: AppIcons.shieldCheck, label: 'Issued');
}

/// A check's one line in a list.
String checkSubtitle(AttestationCheck c) {
  if (c.isAnswered) {
    return 'Shown by ${c.result!.shownBy} · ${momentText(c.answeredAt)}';
  }
  if (c.isWaiting(DateTime.now())) {
    return 'Waiting for an answer until ${momentText(c.expiresAt)}';
  }
  return 'Not answered · ${momentText(c.created)}';
}

Widget? checkBadge(BuildContext context, AttestationCheck c) {
  if (c.isAnswered) return verdictBadge(context, c.result!.verdict);
  if (c.isWaiting(DateTime.now())) {
    return const AppBadge(
      icon: AppIcons.hourglass,
      label: 'Waiting',
      variant: AppBadgeVariant.outline,
    );
  }
  return const AppBadge(
    icon: AppIcons.clock,
    label: 'Not answered',
    variant: AppBadgeVariant.outline,
  );
}
