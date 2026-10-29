import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';

/// A labelled tab strip over its pages. Tab styling lives here rather than in
/// whichever screen happened to need tabs first.
class AppTabs extends StatelessWidget {
  final List<String> labels;
  final List<Widget> views;

  /// Which tab opens first - lets a route deep-link into one.
  final int initialIndex;

  /// Where the content around the tabs starts, so the first label lines up
  /// with it. A screen's edge unless the tabs sit in a sheet.
  final double? inset;

  const AppTabs({
    super.key,
    required this.labels,
    required this.views,
    this.initialIndex = 0,
    this.inset,
  }) : assert(labels.length == views.length, 'one view per tab');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: labels.length,
      initialIndex: initialIndex.clamp(0, labels.length - 1),
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: EdgeInsetsDirectional.only(
              start:
                  (inset ?? AppSpacing.screenH(context)) -
                  kTabLabelPadding.left,
            ),
            dividerColor: scheme.outlineVariant,
            dividerHeight: 1,
            tabs: [for (final l in labels) Tab(text: l)],
          ),
          Expanded(child: TabBarView(children: views)),
        ],
      ),
    );
  }
}
