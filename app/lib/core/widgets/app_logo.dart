import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:revoked_app/core/design/radius.dart';

/// The Revoked logo, in the variant that matches the active theme.
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final asset = Theme.of(context).brightness == Brightness.dark
        ? 'assets/icon/revoced-mark-redacted-white-on-black.svg'
        : 'assets/icon/revoced-mark-redacted-black-on-white.svg';
    return ClipRRect(
      borderRadius: AppRadius.allLg,
      child: SvgPicture.asset(
        asset,
        width: size,
        height: size,
        semanticsLabel: 'Revoked',
      ),
    );
  }
}
