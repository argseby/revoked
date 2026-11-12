import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';

/// One page of an [AppTabs]: its name, icon, and a line on what it holds,
/// shown together on its context card.
class AppTab {
  final String label;
  final IconData icon;
  final String? description;
  final Widget view;

  const AppTab({
    required this.label,
    required this.icon,
    required this.view,
    this.description,
  });
}

/// Equal-height context cards above pages that retain their local state.
class AppTabs extends StatefulWidget {
  final List<AppTab> tabs;
  final String? title;

  /// Which tab opens first - lets a route deep-link into one.
  final int initialIndex;

  /// Where the content around the tabs starts, so the strip lines up with
  /// it. A screen's edge unless the tabs sit in a sheet.
  final double? inset;

  const AppTabs({
    super.key,
    required this.tabs,
    this.title,
    this.initialIndex = 0,
    this.inset,
  });

  @override
  State<AppTabs> createState() => _AppTabsState();
}

class _AppTabsState extends State<AppTabs> {
  late final _selected = Local<int>(
    widget.initialIndex.clamp(0, widget.tabs.length - 1),
  );

  @override
  Widget build(BuildContext context) {
    final inset = widget.inset ?? AppSpacing.screenH(context);
    return Observer(
      builder: (context) {
        final i = _selected.value.clamp(0, widget.tabs.length - 1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                inset,
                AppSpacing.lg,
                inset,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.title != null) ...[
                    AppText(widget.title!).title,
                    AppSpacing.gapXxl,
                  ],
                  ConstrainedBox(
                    // As wide as the list under it, so the tabs and its
                    // search line up edge to edge.
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.contentMaxWidth,
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final stackedIcon =
                            box.maxWidth / widget.tabs.length < 160 ||
                            MediaQuery.textScalerOf(context).scale(16) > 24;
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (k, t) in widget.tabs.indexed) ...[
                                if (k > 0) AppSpacing.gapMd,
                                Expanded(
                                  child: _ContextCard(
                                    tab: t,
                                    selected: i == k,
                                    stackedIcon: stackedIcon,
                                    onTap: () => _selected.value = k,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Every page stays built, so a list keeps its scroll position
            // and filters when the person switches back.
            Expanded(
              child: IndexedStack(
                index: i,
                children: [for (final t in widget.tabs) t.view],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ContextCard extends StatelessWidget {
  final AppTab tab;
  final bool selected;
  final bool stackedIcon;
  final VoidCallback onTap;

  const _ContextCard({
    required this.tab,
    required this.selected,
    required this.stackedIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: AppRadius.allLg,
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
      ),
    );
    final icon = Icon(
      tab.icon,
      size: 20,
      color: selected ? scheme.primary : scheme.onSurfaceVariant,
    );
    final label = AppText(tab.label).bold;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.secondaryContainer : scheme.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (stackedIcon) ...[
                  icon,
                  AppSpacing.gapSm,
                  label,
                ] else
                  Row(
                    children: [
                      icon,
                      AppSpacing.gapSm,
                      Expanded(child: label),
                    ],
                  ),
                if (tab.description != null) ...[
                  AppSpacing.gapSm,
                  AppText(tab.description!).small.muted,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
