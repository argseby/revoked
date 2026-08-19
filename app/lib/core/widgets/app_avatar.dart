import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/text_styles.dart';

enum AppAvatarSize { small, normal, large }

/// A circular initial. The one place the app turns an email or a workspace
/// name into a face, so every list, menu and profile card renders the same
/// letter the same way.
class AppAvatar extends StatelessWidget {
  /// The text to take an initial from — an email or a name, not a pre-cut
  /// letter, so the trimming rule lives here and not at each call site.
  final String source;
  final AppAvatarSize size;

  /// Renders on the primary container instead of the secondary one, for the
  /// single "this is you" avatar on the account card.
  final bool emphasized;

  const AppAvatar({
    super.key,
    required this.source,
    this.size = AppAvatarSize.normal,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = source.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final radius = switch (size) {
      AppAvatarSize.small => 16.0,
      AppAvatarSize.normal => 20.0,
      AppAvatarSize.large => 26.0,
    };
    final text = AppText(initial);
    return CircleAvatar(
      radius: radius,
      backgroundColor: emphasized
          ? scheme.primaryContainer
          : scheme.secondaryContainer,
      foregroundColor: emphasized
          ? scheme.onPrimaryContainer
          : scheme.onSecondaryContainer,
      child: size == AppAvatarSize.large ? text.header : text,
    );
  }
}
