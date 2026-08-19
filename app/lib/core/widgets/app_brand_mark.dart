import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// The app's mark: its initial on a filled square. Sign-in and sign-up both
/// show it, so it is defined once.
class AppBrandMark extends StatelessWidget {
  final double size;

  const AppBrandMark({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: AppRadius.allMd,
      ),
      child: Center(
        child: DefaultTextStyle.merge(
          style: TextStyle(color: scheme.onPrimary),
          child: const Text('R').header,
        ),
      ),
    );
  }
}
