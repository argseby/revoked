import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/attestation_check.dart';
import 'package:revoked_app/core/models/credential.dart';
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
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/attestations/claim_text.dart';
import 'package:revoked_app/features/attestations/view/ask_attestation_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_check_sheet.dart';
import 'package:revoked_app/features/attestations/view/attestation_create_sheet.dart';
import 'package:revoked_app/features/attestations/view/verdict_badge.dart';

/// A tab's list: one line on what it holds, then its rows. The tab names it,
/// so it carries no heading of its own. While there is nothing to list, the
/// tab shows [empty] instead, as every other list in the app does.
class _TabList extends StatelessWidget {
  final String intro;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final Widget empty;
  final List<Widget> children;

  const _TabList({
    required this.intro,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.empty,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      if (loading) return const Center(child: AppSpinner(large: true));
      if (error != null) {
        return AppLoadError(
          title: 'Couldn’t load this list',
          message: error!,
          onRetry: onRetry,
        );
      }
      return empty;
    }
    return AppPageBody(
      children: [
        Text(intro).muted.small,
        AppSpacing.gapMd,
        AppListCard(children: children),
      ],
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
            'What others confirmed about you. Nobody sees one unless you '
            'choose to show it, detail by detail.',
        loading: store.isLoading,
        error: store.errorMessage,
        onRetry: store.load,
        empty: AppEmptyState(
          icon: AppIcons.attestation,
          title: 'Prove what others confirm about you',
          subtitle:
              'Get a club, an employer or a verification service to confirm '
              'something about you. Keep it here. Show only the details you '
              'choose.',
          example: const AppEmptyExample(
            title: 'membership',
            detail: 'From chess-club.org · member_since: 2021',
            badge: 'Verified',
          ),
          steps: const [
            AppEmptyStep(
              'Ask for one',
              'New → Attestation about you gives you a link to send',
            ),
            AppEmptyStep('Accept their offer', 'It belongs to your identity'),
            AppEmptyStep(
              'Show it when asked',
              'You choose which details they see',
            ),
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
              onTap: () => showAppSheet(
                context: context,
                dismissible: true,
                builder: (_) => _CredentialSheet(
                  credential: c,
                  identityName: _identityName(c),
                ),
              ),
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
          'It disappears from your list. ${credential.issuer} still stands '
          'behind it and can offer it again.',
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
        'Couldn’t remove it',
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
                const Text('What it confirms'),
                AppSpacing.gapSm,
                AppListCard(
                  children: [
                    if (claims.isEmpty)
                      const AppDetailRow(
                        icon: AppIcons.info,
                        label: 'Nothing beyond what kind it is.',
                      )
                    else
                      for (final d in claims)
                        AppDetailRow(label: d.name, value: claimText(d.value)),
                  ],
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

  String _subtitle(Attestation a) {
    if (a.isRevoked) {
      return a.subject.isEmpty
          ? 'Withdrawn before anyone accepted it'
          : 'Revoked · ${a.subject}';
    }
    if (a.isOffered) {
      return 'Offered · open until ${dayText(a.offerExpiresAt)}';
    }
    return 'Held by ${a.subject}';
  }

  Future<void> _revoke(BuildContext context, Attestation a) async {
    final confirmed = await showAppDialog(
      context: context,
      title: a.isOffered ? 'Withdraw this offer?' : 'Revoke ${a.title}?',
      message: a.isOffered
          ? 'Its link stops working. Nobody has accepted it yet.'
          : 'You stop standing behind it. Anyone who checks it learns this '
                'within minutes.\n\n'
                'You can’t undo this. You can issue a new one instead.',
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
        'Couldn’t revoke it',
        subtitle: Stores.attestations.error?.description,
      );
    }
  }

  Future<void> _delete(BuildContext context, Attestation a) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete ${a.title}?',
      message: a.isActive
          ? 'It leaves your list and is revoked too, so nobody can keep '
                'using it.'
          : 'It leaves your list.',
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
      'Couldn’t delete it',
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

  Widget? _badge(Attestation a) {
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

  @override
  Widget build(BuildContext context) {
    final store = Stores.attestations;
    return Observer(
      builder: (_) {
        final off = store.issuingAllowed == false;
        final error = store.error;
        return _TabList(
          intro:
              'What this workspace confirmed about others, in your domain\'s '
              'name. Anyone who trusts your domain can trust these.',
          loading: store.isLoading,
          error: error?.description,
          onRetry: store.load,
          empty: off
              ? const AppEmptyState(
                  icon: AppIcons.attestation,
                  title: 'This server doesn’t issue attestations',
                  subtitle:
                      'Whoever runs it has turned this off. You can still '
                      'keep and show attestations from others.',
                )
              : AppEmptyState(
                  icon: AppIcons.attestation,
                  title: 'Vouch for the people you know',
                  subtitle:
                      'Confirm a membership, a role or a fact about someone, '
                      'in your domain\'s name. They keep it and show it '
                      'wherever they need it.',
                  example: const AppEmptyExample(
                    title: 'Membership 2026 — Ada',
                    detail: 'membership · member_since: 2021',
                    badge: 'Issued',
                  ),
                  steps: const [
                    AppEmptyStep(
                      'Write what you confirm',
                      'A kind and its details, such as member_since',
                    ),
                    AppEmptyStep(
                      'Send them the offer',
                      'A code to scan or a link. You see it once',
                    ),
                    AppEmptyStep(
                      'Revoke it if it stops being true',
                      'Anyone who checks it learns within minutes',
                    ),
                  ],
                  action: AppButton(
                    icon: AppIcons.attestation,
                    label: 'Confirm something',
                    onTap: () => showAttestationCreateSheet(context),
                  ),
                ),
          children: [
            if (!off)
              for (final a in store.attestations)
                AppListRow(
                  icon: AppIcons.shieldLock,
                  title: a.title,
                  subtitle: _subtitle(a),
                  trailing: _badge(a),
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

  String _subtitle(AttestationCheck c) {
    if (c.isAnswered) {
      return 'Shown by ${c.result!.shownBy} · ${momentText(c.answeredAt)}';
    }
    if (c.isWaiting(DateTime.now())) {
      return 'Waiting for an answer until ${momentText(c.expiresAt)}';
    }
    return 'Not answered · ${momentText(c.created)}';
  }

  Widget? _badge(BuildContext context, AttestationCheck c) {
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
                  ? 'Checked the moment it arrived. This is how it stood '
                        'then.'
                  : 'Nobody answered this check.',
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
            'What people showed you when you asked. Each answer is how it '
            'stood at that moment.',
        loading: store.isLoading,
        error: store.errorMessage,
        onRetry: store.load,
        empty: AppEmptyState(
          icon: AppIcons.shieldCheck,
          title: 'Check what others say about themselves',
          subtitle:
              'Ask someone to show you what a club or an employer confirmed '
              'about them. You see right away whether it holds up.',
          example: const AppEmptyExample(
            title: 'membership',
            detail: 'Shown by 3fa2c1… · member_since: 2021',
            badge: 'Verified',
          ),
          steps: const [
            AppEmptyStep(
              'Ask them to show one',
              'New → See someone\'s attestation gives you a code to scan',
            ),
            AppEmptyStep(
              'They choose what to show',
              'Detail by detail, on their own device',
            ),
            AppEmptyStep(
              'You get a checked answer',
              'Who confirmed it, whether it still holds, and that it\'s theirs',
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
              subtitle: _subtitle(c),
              trailing: _badge(context, c),
              onTap: () => _open(context, c),
            ),
        ],
      ),
    );
  }
}
