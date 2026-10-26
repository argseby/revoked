import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/features/shares/view/shares_screen.dart';

/// Shared on every width: the links list and the selected link.
///
/// Wide, both stand side by side and the list stays put while links are
/// picked, keeping its search, filter and tab. Narrower, it is one or the
/// other, as before: the list, or the link with a way back to it.
///
/// [child] is the nested route's navigator — the selected link, or the
/// [SharedPlaceholder] while none is.
class SharedSplit extends StatefulWidget {
  final String? selectedId;
  final String? filterSlug;
  final Widget child;

  const SharedSplit({
    super.key,
    required this.selectedId,
    required this.filterSlug,
    required this.child,
  });

  /// The list's share of a split window, before the link takes the rest.
  static const double listWidth = 400;

  @override
  State<SharedSplit> createState() => _SharedSplitState();
}

class _SharedSplitState extends State<SharedSplit> {
  /// Keeps the list's state when the window crosses the breakpoint and the
  /// list moves between layouts.
  final GlobalKey _listKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppSpacing.wideWidth;
    final list = SharesScreen(
      key: _listKey,
      filterSlug: widget.filterSlug,
      selectedId: wide ? widget.selectedId : null,
      embedded: wide,
    );

    if (wide) {
      final scheme = Theme.of(context).colorScheme;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: SharedSplit.listWidth, child: list),
          VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
          Expanded(child: ShellSplitPane(child: widget.child)),
        ],
      );
    }
    if (widget.selectedId != null) return widget.child;
    // The navigator stays mounted, out of sight, so the route keeps its place.
    return Stack(
      children: [
        Offstage(child: widget.child),
        list,
      ],
    );
  }
}

/// The empty side of a split before a link is chosen.
class SharedPlaceholder extends StatelessWidget {
  const SharedPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.link, size: 32, color: scheme.onSurfaceVariant),
            AppSpacing.gapMd,
            const AppText('Choose a link', textAlign: TextAlign.center).header,
            AppSpacing.gapXs,
            const Text(
              'What it shares, how it is protected and who has opened it '
              'appear here.',
              textAlign: TextAlign.center,
            ).muted,
          ],
        ),
      ),
    );
  }
}
