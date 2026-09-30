import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/utils/pkce.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';

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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: allowed ? scheme.primary : scheme.onSurfaceVariant,
          ),
          AppSpacing.gapSm,
          Expanded(child: allowed ? Text(text) : Text(text).muted),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$name can').small.muted,
        row(AppIcons.check, 'Propose links for you to confirm'),
        row(
          AppIcons.check,
          'See the status, opens and expiry of links it proposed',
        ),
        AppSpacing.gapMd,
        const Text('You decide').small.muted,
        AppCheckRow(
          label: 'Revoke links it proposed',
          subtitle: 'It cannot create links or see their contents.',
          note: _reason(reasons.revoke),
          value: allowRevoke,
          onChanged: onAllowRevoke,
        ),
        AppCheckRow(
          label: 'Receive the links it proposed',
          subtitle:
              'Except links with documents or hidden values; those only you '
              'can send.',
          note: _reason(reasons.links),
          value: allowHandOver,
          onChanged: onAllowHandOver,
        ),
        AppSpacing.gapMd,
        Text('$name can never').small.muted,
        row(
          AppIcons.x,
          'Read your vault, your other links or your account',
          allowed: false,
        ),
        row(AppIcons.x, 'Publish a link without your consent', allowed: false),
        AppSpacing.gapMd,
        const Text(
          'The connection ends after 90 days unless you connect again.',
        ).small.muted,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('The $name page you came from shows this code').small.muted,
        AppSpacing.gapXs,
        Text(Pkce.checkCode(challenge)).header,
        AppSpacing.gapXs,
        const Text(
          'Go on only if it does. If you did not just ask for this in a '
          'browser, decline.',
        ).small,
      ],
    );
  }
}
