import 'package:flutter/material.dart';

/// The app's only switch. Exists so the toggle inside a settings row and the
/// toggle sitting inline in a table are the same control at the same density.
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
