import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_avatar.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';

/// One entry in an [AppMenuButton]'s menu. A null [onSelected] disables it.
class AppMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback? onSelected;

  /// Renders in the error color — deletes and revokes.
  final bool destructive;

  /// Shows a leading tick, for menus that pick one of several values.
  final bool checked;

  const AppMenuItem({
    required this.label,
    this.onSelected,
    this.icon,
    this.destructive = false,
    this.checked = false,
  });
}

/// A button that opens a menu. The trigger is a real [AppButton], so its ink
/// is clipped to the button's own radius — a hand-built `child:` under a
/// [PopupMenuButton] gets an unclipped rectangular ripple painted behind it.
class AppMenuButton extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final String tooltip;
  final AppButtonStyle style;
  final AppButtonSize size;

  /// Rendered above the items as non-interactive context, e.g. which account
  /// is signed in.
  final Widget? header;

  /// A null entry renders a divider.
  final List<AppMenuItem?> items;

  /// Set instead of [icon]/[label] to trigger from a circular avatar.
  final String? avatarSource;

  /// Runs before the menu opens, for triggers that lazily load their contents.
  final VoidCallback? onOpen;

  const AppMenuButton({
    super.key,
    required this.tooltip,
    required this.items,
    this.icon,
    this.label,
    this.style = AppButtonStyle.accent,
    this.size = AppButtonSize.normal,
    this.header,
    this.onOpen,
  }) : avatarSource = null,
       assert(icon != null || label != null, 'a trigger needs a label or icon');

  const AppMenuButton.avatar({
    super.key,
    required String this.avatarSource,
    required this.tooltip,
    required this.items,
    this.header,
    this.onOpen,
  }) : icon = null,
       label = null,
       style = AppButtonStyle.accent,
       size = AppButtonSize.normal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      alignmentOffset: const Offset(0, AppSpacing.xxs),
      style: MenuStyle(
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.allMd),
        ),
      ),
      menuChildren: [
        if (header != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: header,
          ),
          const AppDivider(),
        ],
        for (final item in items)
          if (item == null)
            const AppDivider()
          else
            MenuItemButton(
              onPressed: item.onSelected,
              leadingIcon: Icon(
                item.checked ? AppIcons.check : item.icon,
                size: 18,
                color: item.destructive ? scheme.error : null,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: item.destructive ? scheme.error : null),
                child: Text(item.label),
              ),
            ),
      ],
      builder: (context, controller, _) {
        void toggle() {
          if (controller.isOpen) {
            controller.close();
          } else {
            onOpen?.call();
            controller.open();
          }
        }

        if (avatarSource != null) {
          return Tooltip(
            message: tooltip,
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: toggle,
                customBorder: const CircleBorder(),
                child: AppAvatar(source: avatarSource!),
              ),
            ),
          );
        }

        return AppButton(
          icon: icon,
          label: label,
          trailingIcon: AppIcons.chevronDown,
          tooltip: tooltip,
          style: style,
          size: size,
          onTap: toggle,
        );
      },
    );
  }
}
