import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';

/// Camera scanner for `revoked://` QR codes. Mobile-only — the callers gate on
/// platform, since the scanner plugin has no Linux/Windows implementation.
///
/// [onCode] judges each scanned value (the drawer passes the store's
/// adoption, so normalization and verdict invalidation apply); returning
/// true closes the scanner. The sheet itself knows no stores - it reads a
/// camera, not state.
Future<void> openQrScanSheet(
  BuildContext context, {
  required bool Function(String) onCode,
}) {
  return showAppSheet(
    context: context,
    builder: (sheetContext) =>
        _QrScanSheet(sheetContext: sheetContext, onCode: onCode),
  );
}

class _QrScanSheet extends StatefulWidget {
  final BuildContext sheetContext;
  final bool Function(String) onCode;

  const _QrScanSheet({required this.sheetContext, required this.onCode});

  @override
  State<_QrScanSheet> createState() => _QrScanSheetState();
}

class _QrScanSheetState extends State<_QrScanSheet> {
  // Hardware lifecycle, like a ScrollController: created and disposed with
  // the view, never store state.
  final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _handled = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    // One hit only — detection fires repeatedly for a code in view.
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? '';
      if (raw.isEmpty) continue;
      if (widget.onCode(raw)) {
        _handled = true;
        Navigator.of(widget.sheetContext).pop();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Scan a link').header,
          const SizedBox(height: AppSpacing.xxs),
          const Text('Point the camera at a Revoked QR code.').muted.small,
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: MobileScanner(controller: _camera, onDetect: _onDetect),
            ),
          ),
        ],
      ),
    );
  }
}
