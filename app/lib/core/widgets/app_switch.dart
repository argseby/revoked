import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/design/app_icons.dart';

/// The app's only switch. Exists so the toggle inside a settings row and the
/// toggle sitting inline in a table are the same control at the same density.
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showCheckIcon;

  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.showCheckIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      thumbIcon: showCheckIcon
          ? WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Icon(AppIcons.check, size: 16)
                  : null,
            )
          : null,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
