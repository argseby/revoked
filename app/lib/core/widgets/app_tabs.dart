import 'package:flutter/material.dart';

/// A labelled tab strip over its pages. Tab styling lives here rather than in
/// whichever screen happened to need tabs first.
class AppTabs extends StatelessWidget {
  final List<String> labels;
  final List<Widget> views;

  const AppTabs({super.key, required this.labels, required this.views})
    : assert(labels.length == views.length, 'one view per tab');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: labels.length,
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
