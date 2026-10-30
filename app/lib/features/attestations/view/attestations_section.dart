import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/attestations/claim_text.dart';

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(child: AppSpinner()),
    );
  }
}

/// A tab's list: one line on what it holds, then its rows. The tab names it,
/// so it carries no heading of its own.
class _TabList extends StatelessWidget {
  final String intro;
  final List<Widget> children;

  const _TabList({required this.intro, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            'Statements others signed about you. They are kept on your '
            'server and shown to a service only when you agree, claim by '
            'claim.',
        children: [
          if (store.isLoading && store.credentials.isEmpty)
            const _Loading()
          else if (store.credentials.isEmpty)
            AppDetailRow(
              icon: AppIcons.info,
              label:
                  store.errorMessage ??
                  'None yet. Ask for one with New → Attestation about you.',
            )
          else
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
                trailing: _verdictBadge(store.verdicts[c.id]),
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

Widget? _verdictBadge(CredentialVerdict? verdict) {
  if (verdict == null) return null;
  if (verdict.isVerified) {
    return AppBadge(icon: AppIcons.shieldCheck, label: verdict.label);
  }
  return AppBadge(
    icon: verdict.isUnusable ? AppIcons.shieldSlash : AppIcons.exclamation,
    label: verdict.label,
    variant: verdict.isUnusable
        ? AppBadgeVariant.destructive
        : AppBadgeVariant.outline,
  );
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
          'The credential is deleted from your server. That does not revoke '
          'it: ${credential.issuer} still stands behind what it attested, '
          'and may offer it again.',
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
        'Could not remove it',
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
                Text('Attested by ${credential.issuer}').muted.small,
                AppSpacing.gapMd,
                AppListCard(
                  children: [
                    AppDetailRow(
                      icon: AppIcons.shieldCheck,
                      label: 'Standing',
                      value: verdict?.label ?? 'Checking…',
                    ),
                    AppDetailRow(
                      icon: AppIcons.personBoundingBox,
                      label: 'Issued to',
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
                          ? 'Until it is revoked'
                          : dayText(credential.expiresAt),
                    ),
                  ],
                ),
                if (verdict != null && verdict.reason.isNotEmpty) ...[
                  AppSpacing.gapSm,
                  Text(verdict.reason).muted.small,
                ],
                AppSpacing.gapMd,
                const Text('What it states'),
                AppSpacing.gapSm,
                AppListCard(
                  children: [
                    if (claims.isEmpty)
                      const AppDetailRow(
                        icon: AppIcons.info,
                        label: 'Nothing beyond its type.',
                      )
                    else
                      for (final d in claims)
                        AppDetailRow(label: d.name, value: claimText(d.value)),
                  ],
                ),
                AppSpacing.gapLg,
                AppButton(
                  icon: AppIcons.trash,
                  label: 'Remove from my attestations',
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
          ? 'Withdrawn before it was accepted'
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
          ? 'Its link stops working. Nothing was issued yet.'
          : 'This server stops standing behind what it attested. Anyone '
                'who verifies the credential is told so within minutes.\n\n'
                'Revoking cannot be undone. A new attestation can be issued '
                'instead.',
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
        'Could not revoke it',
        subtitle: Stores.attestations.error?.description,
      );
    }
  }

  Future<void> _delete(BuildContext context, Attestation a) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete ${a.title}?',
      message: a.isActive
          ? 'The entry is removed from this list, and the credential it '
                'issued is revoked with it: a deleted attestation is not left '
                'standing with nobody able to withdraw it.'
          : 'The entry is removed from this list.',
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
      'Could not delete it',
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
              'Statements this workspace signed about others, in the name of '
              'this server\'s domain. Whoever trusts the domain trusts them.',
          children: [
            if (off)
              const AppDetailRow(
                icon: AppIcons.info,
                label:
                    'This server does not issue attestations. Its operator '
                    'decides whether it speaks for its domain.',
              )
            else if (store.isLoading && store.attestations.isEmpty)
              const _Loading()
            else if (error != null)
              AppDetailRow(icon: AppIcons.info, label: error.description)
            else if (store.attestations.isEmpty)
              const AppDetailRow(
                icon: AppIcons.info,
                label:
                    'Nothing attested yet. Start one with New → Attestation.',
              )
            else
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
