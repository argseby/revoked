import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_brand_mark.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';

/// Shown while the stored session is checked against the server. It exists so
/// the first frame does not wait on a network call — an unreachable server
/// used to mean a blank window for as long as the request took.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBrandMark(),
            SizedBox(height: AppSpacing.xxl),
            AppSpinner(large: true),
            SizedBox(height: AppSpacing.lg),
            Text('Restoring your session…'),
          ],
        ),
      ),
    );
  }
}
