import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_trust_badge.dart';

/// Everything a person needs to judge an invite before accepting it, in one
/// place so both screens that show an invite say the same thing.
///
/// Anyone can stand up this server and put any address in an invite, so the
/// address is worth exactly what the domain behind it is worth. That is why
/// the wording below is conditioned on the verdict rather than stated flat:
/// "this address is on bmw.com" is reassurance on a DNS-verified server and
/// misdirection on an unverified one, and it is the same sentence either way.
class InviteTrustSummary extends StatelessWidget {
  final InvitePreview preview;

  const InviteTrustSummary({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final verdict = Stores.invites.inviteTrustVerdict;
        final checking = Stores.invites.isVerifyingInviteTrust;

        if (checking && verdict == null) {
          return const AppCard(
            child: Row(
              children: [
                AppSpinner(),
                SizedBox(width: AppSpacing.sm),
                Text('Checking this server\'s domain…'),
              ],
            ),
          );
        }

        final inviter = preview.inviter;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (verdict != null) AppTrustBadge(verdict: verdict),
            if (inviter != null) ...[
              AppSpacing.gapSm,
              _InviterLine(inviter: inviter, verdict: verdict),
            ],
            if (inviter != null && !inviter.canStillInvite) ...[
              AppSpacing.gapSm,
              AppAlert(
                destructive: true,
                leading: const Icon(AppIcons.shieldSlash, size: 18),
                title: const Text('The inviter lost this authority'),
                content: const Text(
                  'Whoever created this invite can no longer invite people to '
                  'this workspace, so the server will refuse it.',
                ).small,
              ),
            ],
            if (inviter?.identityRevoked ?? false) ...[
              AppSpacing.gapSm,
              AppAlert(
                destructive: true,
                leading: const Icon(AppIcons.shieldSlash, size: 18),
                title: const Text('The inviter\'s identity was revoked'),
                content: const Text(
                  'The server that issued it has withdrawn it, so it no longer '
                  'speaks for this domain.',
                ).small,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _InviterLine extends StatelessWidget {
  final InviteInviter inviter;
  final TrustVerdict? verdict;

  const _InviterLine({required this.inviter, required this.verdict});

  /// The domain claim is only worth something once DNS proves it. Anything
  /// short of that and the address is a claim resting on another claim.
  bool get _domainProven => verdict?.state == TrustState.verified;

  String get _detail {
    final domain = inviter.serverDomain;

    if (!_domainProven) {
      return 'Nothing has verified that this server really is $domain, so '
          'this address is only what the server says it is. Anyone can run '
          'a server and claim any address on it.';
    }
    if (inviter.emailMatchesServer) {
      return 'This address is on $domain, and $domain is DNS-verified — '
          'whoever controls that domain controls its mail.';
    }
    if (inviter.emailDomain.isEmpty) {
      return '$domain is DNS-verified, but it cannot vouch for this address.';
    }
    return 'This address is at ${inviter.emailDomain}, not $domain. The '
        'server is DNS-verified, but it does not control '
        '${inviter.emailDomain} and cannot vouch for the address.';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Invited by ${inviter.email}').muted.small,
        AppSpacing.gapXxs,
        Text(_detail).muted.small,
      ],
    );
  }
}
