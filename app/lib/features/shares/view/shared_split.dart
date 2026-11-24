import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/features/shares/view/shares_screen.dart';

/// Shared on every width: the links list and the selected link.
///
/// Wide windows keep a stable list and detail layout across selections.
/// Narrow windows show one pane at a time.
///
/// [child] is the nested route's navigator — the selected link, or the
/// [SharedPlaceholder] while none is.
class SharedSplit extends StatefulWidget {
  final String? selectedId;
  final String? recipient;
  final Widget child;

  /// The list's tab to open on: 1 for Received.
  final int initialTab;

  const SharedSplit({
    super.key,
    required this.selectedId,
    required this.recipient,
    required this.child,
    this.initialTab = 0,
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
      recipient: widget.recipient,
      selectedId: wide ? widget.selectedId : null,
      initialTab: widget.initialTab,
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
  Widget build(BuildContext context) => const AppEmptyState(
    icon: AppIcons.link,
    title: 'Select a sent share',
    subtitle:
        'Review what the link shares, who can open it, and when it expires.',
  );
}
