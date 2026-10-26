import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';

/// The app's only QR code: black modules on a white tile, whatever the theme.
class AppQrCode extends StatelessWidget {
  final String data;
  final double size;

  const AppQrCode({super.key, required this.data, this.size = 200});

  @override
  Widget build(BuildContext context) {
    // A camera needs dark-on-light; the one place a fixed color is the point.
    const ink = Color(0xFF000000);
    const paper = Color(0xFFFFFFFF);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: AppRadius.allMd,
      ),
      child: QrImageView(
        data: data,
        version: QrVersions.auto,
        size: size,
        backgroundColor: paper,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: ink),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: ink,
        ),
      ),
    );
  }
}
