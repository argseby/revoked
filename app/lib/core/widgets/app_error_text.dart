import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/text_styles.dart';

/// One line of failure next to the thing that failed — a validation warning
/// under a field, a save error under a form. Owns the error color so views
/// never reach for it themselves.
class AppErrorText extends StatelessWidget {
  final String message;

  const AppErrorText(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: TextStyle(color: Theme.of(context).colorScheme.error),
      child: Text(message).small,
    );
  }
}
