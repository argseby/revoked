import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_card.dart';

/// A named, collapsible group in a list of cards — a folder the reader opens.
///
/// The header row shows [icon], [title] and how many children it holds;
/// tapping it toggles. Children render below the header, indented, keeping
/// whatever card shape they have elsewhere in the app. Starts collapsed: a
/// group exists to keep a long list short.
class AppCollapsibleGroup extends StatefulWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const AppCollapsibleGroup({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  State<AppCollapsibleGroup> createState() => _AppCollapsibleGroupState();
}

class _AppCollapsibleGroupState extends State<AppCollapsibleGroup> {
  final Local<bool> _expanded = Local(false);

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = _expanded.value;

    return AnimatedSize(
      duration: AppMotion.duration,
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.md,
            ),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            onTap: () => _expanded.value = !expanded,
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: scheme.onSurfaceVariant),
                AppSpacing.gapSm,
                Expanded(child: Text(widget.title)),
                AppBadge(label: '${widget.children.length}'),
                AppSpacing.gapSm,
                Icon(
                  expanded ? AppIcons.chevronUp : AppIcons.chevronDown,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}
