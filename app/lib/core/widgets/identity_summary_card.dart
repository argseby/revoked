import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/trust_panel.dart';

/// Who is on the other end of a share or request: display name, key
/// fingerprint, and the domain that issued the identity — the last carrying
/// its proof state, never printed as bare fact.
class IdentitySummaryCard extends StatelessWidget {
  final String name;
  final String fingerprint;
  final String domain;
  final TrustCheckState domainState;

  const IdentitySummaryCard({
    super.key,
    required this.name,
    required this.fingerprint,
    required this.domain,
    required this.domainState,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: AppRadius.allMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            AppIcons.personBoundingBox,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Unnamed identity' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).small,
                if (fingerprint.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    fingerprint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).muted.mono.small,
                ],
                const SizedBox(height: AppSpacing.xs),
                if (domain.isEmpty)
                  const Text('No domain declared').muted.small
                else
                  TrustClaimText(domain: domain, state: domainState),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
