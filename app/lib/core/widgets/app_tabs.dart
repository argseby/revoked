import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';

/// One page of an [AppTabs]: its name, icon, and a line on what it holds,
/// read out by screen readers; the name alone says it on screen.
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

/// Pages behind a filled segmented strip. Thin underlined tabs went
/// unnoticed.
class AppTabs extends StatefulWidget {
  final List<AppTab> tabs;

  /// Which tab opens first - lets a route deep-link into one.
  final int initialIndex;

  /// Where the content around the tabs starts, so the strip lines up with
  /// it. A screen's edge unless the tabs sit in a sheet.
  final double? inset;

  const AppTabs({
    super.key,
    required this.tabs,
    this.initialIndex = 0,
    this.inset,
  });

  @override
  State<AppTabs> createState() => _AppTabsState();
}

/// How wide a segment grows at most, so the strip doesn't stretch across a
/// desktop window.
const double _segmentWidth = 160;

/// The narrowest segment that still fits an icon beside its name.
const double _iconRoom = 120;

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
        final description = widget.tabs[i].description;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                inset,
                AppSpacing.sm,
                inset,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _segmentWidth * widget.tabs.length,
                    ),
                    // One row: icon beside the name. A segment too narrow for
                    // both keeps the name whole and drops the icon.
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final icons =
                            box.maxWidth / widget.tabs.length >= _iconRoom;
                        final strip = AppSegmented<int>(
                          value: i,
                          expand: true,
                          items: [
                            for (final (k, t) in widget.tabs.indexed)
                              AppSegmentedItem(
                                value: k,
                                label: t.label,
                                icon: icons ? t.icon : null,
                              ),
                          ],
                          onChanged: (k) => _selected.value = k,
                        );
                        if (description == null) return strip;
                        return Semantics(hint: description, child: strip);
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
