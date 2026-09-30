import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/utils/pkce.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';

/// What a connected tool may do — the same three sections on the connect
/// screen, on a proposal that connects, and under Connected tools, so what the
/// owner agreed to is what they later read:
///
///  * what every connected tool can do (nothing to choose),
///  * what the owner decides, each with the tool's own reason in italics,
///  * what no tool can ever do.
class ToolPermissions extends StatelessWidget {
  final String name;

  /// The owner's choices, and how to change them; a null callback shows the
  /// choice without letting it be changed.
  final bool allowRevoke;
  final bool allowHandOver;
  final ValueChanged<bool>? onAllowRevoke;
  final ValueChanged<bool>? onAllowHandOver;

  /// Why the tool asks, in its own words.
  final ToolReasons reasons;

  const ToolPermissions({
    super.key,
    required this.name,
    required this.allowRevoke,
    required this.allowHandOver,
    required this.onAllowRevoke,
    required this.onAllowHandOver,
    this.reasons = const ToolReasons(),
  });

  String? _reason(String reason) =>
      reason.isEmpty ? null : '$name says: “$reason”';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListGroup(
          title: '$name can',
          trailing: quiet,
          children: [
            row(AppIcons.check, 'Propose links for you to confirm'),
            row(
              AppIcons.check,
              'See the status, opens and expiry of links it proposed',
            ),
          ],
        ),
        AppListGroup(
          title: 'You decide',
          trailing: quiet,
          children: [
            choice(
              AppCheckRow(
                label: 'Revoke links it proposed',
                subtitle: 'It can’t create links or see what they contain.',
                note: _reason(reasons.revoke),
                value: allowRevoke,
                onChanged: onAllowRevoke,
              ),
            ),
            choice(
              AppCheckRow(
                label: 'Receive the links it proposed',
                subtitle:
                    'Except links that contain documents or hidden values; '
                    'only you can send those.',
                note: _reason(reasons.links),
                value: allowHandOver,
                onChanged: onAllowHandOver,
              ),
            ),
          ],
        ),
        AppListGroup(
          title: '$name can never',
          trailing: quiet,
          footer: const Text(
            'The connection ends after 90 days unless you connect again.',
          ),
          children: [
            row(
              AppIcons.x,
              'Read your vault, your other links or your account',
              allowed: false,
            ),
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
