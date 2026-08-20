import 'package:flutter/material.dart';

/// A labelled tab strip over its pages. Tab styling lives here rather than in
/// whichever screen happened to need tabs first.
class AppTabs extends StatelessWidget {
  final List<String> labels;
  final List<Widget> views;

  /// Which tab opens first - lets a route deep-link into one.
  final int initialIndex;

  const AppTabs({
    super.key,
    required this.labels,
    required this.views,
    this.initialIndex = 0,
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
