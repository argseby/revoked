import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';

/// Marks the server the project itself runs, wherever its address is shown.
class OfficialServerBadge extends StatelessWidget {
  const OfficialServerBadge({super.key});

  @override
  Widget build(BuildContext context) => AppBadge(
    label: 'Official',
    icon: AppIcons.shieldCheck,
    accent: Theme.of(context).colorScheme.primary,
  );
}
