import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';

/// The same item actions on touch, mouse and keyboard. A normal tap keeps
/// opening the item; context gestures never trigger that navigation.
class AppContextMenu extends StatefulWidget {
  final String title;
  final FutureOr<List<AppSheetAction>> Function() actions;
  final Widget child;

  const AppContextMenu({
    super.key,
    required this.title,
    required this.actions,
    required this.child,
  });

  @override
  State<AppContextMenu> createState() => _AppContextMenuState();
}

class _AppContextMenuState extends State<AppContextMenu> {
  bool _opening = false;

  Future<void> _open({Offset? position}) async {
    if (_opening) return;
    _opening = true;
    try {
      final actions = await widget.actions();
      if (!mounted || actions.isEmpty) return;
      if (position == null) {
        await showAppOptionsSheet(
          context: context,
          title: widget.title,
          actions: actions,
        );
        return;
      }
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final point = overlay.globalToLocal(position);
      final scheme = Theme.of(context).colorScheme;
      var previousDestructive = false;
      var hasAction = false;
      final entries = <PopupMenuEntry<AppSheetAction>>[
        PopupMenuItem(
          enabled: false,
          child: AppText(
            widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ).small.bold.muted,
        ),
        const PopupMenuDivider(),
      ];
      for (final action in actions) {
        if (hasAction && action.destructive && !previousDestructive) {
          entries.add(const PopupMenuDivider());
        }
        previousDestructive = action.destructive;
        hasAction = true;
        entries.add(
          PopupMenuItem<AppSheetAction>(
            value: action,
            enabled: action.enabled,
            textStyle: TextStyle(
              color: action.destructive ? scheme.error : scheme.onSurface,
            ),
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: 18,
                  color: action.destructive ? scheme.error : null,
                ),
                AppSpacing.gapMd,
                Expanded(child: AppText(action.label).small),
              ],
            ),
          ),
        );
      }
      final chosen = await showMenu<AppSheetAction>(
        context: context,
        position: RelativeRect.fromSize(
          Rect.fromLTWH(point.dx, point.dy, 0, 0),
          overlay.size,
        ),
        items: entries,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allLg,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(
          minWidth: 220,
          maxWidth: 320,
          maxHeight: overlay.size.height - AppSpacing.xxl * 2,
        ),
      );
      if (mounted && chosen != null) chosen.onTap();
    } finally {
      _opening = false;
    }
  }

  void _keyboard() {
    final box = context.findRenderObject()! as RenderBox;
    _open(position: box.localToGlobal(box.size.center(Offset.zero)));
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.contextMenu): _keyboard,
      const SingleActivator(LogicalKeyboardKey.f10, shift: true): _keyboard,
    },
    child: Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Show options'): () => _open(),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _open(),
        onSecondaryTapDown: (details) =>
            _open(position: details.globalPosition),
        child: widget.child,
      ),
    ),
  );
}
