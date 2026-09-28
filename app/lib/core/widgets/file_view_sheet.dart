import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';

/// Raster formats Flutter decodes on every platform. SVG is left out on
/// purpose: it is a document that can carry scripts and links, not a picture.
const _imageTypes = {
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'image/bmp',
};

const _textTypes = {
  'application/json',
  'application/xml',
  'application/yaml',
  'application/x-yaml',
  'application/toml',
};

/// Uploads often arrive typed application/octet-stream, so a text file is
/// also recognised by its name.
const _textExtensions = {
  'txt', 'md', 'csv', 'tsv', 'json', 'log', 'xml', 'yaml', 'yml', 'toml', //
  'ini', 'conf', 'cfg', 'env', 'pem', 'crt', 'key', 'pub', 'asc',
};

/// Past this, a text file goes to an external app instead: one enormous
/// widget stalls the frame.
const _maxInAppTextBytes = 1024 * 1024;

enum _Kind { image, text }

_Kind? _kindOf(String? mime, String filename, int size) {
  final type = (mime ?? '').split(';').first.trim().toLowerCase();
  if (_imageTypes.contains(type)) return _Kind.image;
  if (size > _maxInAppTextBytes) return null;
  if (type.startsWith('text/') || _textTypes.contains(type)) return _Kind.text;
  final dot = filename.lastIndexOf('.');
  if (dot > 0 &&
      _textExtensions.contains(filename.substring(dot + 1).toLowerCase())) {
    return _Kind.text;
  }
  return null;
}

/// Whether [showFileViewSheet] can show this file inside the app.
bool canViewInApp({
  String? mime,
  required String filename,
  required int size,
}) => _kindOf(mime, filename, size) != null;

/// Shows an image or a text file from memory; nothing is written to disk.
Future<void> showFileViewSheet(
  BuildContext context, {
  required Uint8List bytes,
  required String filename,
  String? mime,
  VoidCallback? onOpenExternally,
}) {
  final kind = _kindOf(mime, filename, bytes.length);
  return showAppSheet(
    context: context,
    builder: (sheetCtx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(sheetCtx).size.height * 0.9,
      ),
      child: Padding(
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).header,
                ),
                if (onOpenExternally != null) ...[
                  AppSpacing.gapSm,
                  AppButton(
                    icon: AppIcons.boxArrowUpRight,
                    tooltip: 'Open in another app',
                    style: AppButtonStyle.accent,
                    size: AppButtonSize.small,
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      onOpenExternally();
                    },
                  ),
                ],
              ],
            ),
            AppSpacing.gapLg,
            Flexible(
              child: switch (kind) {
                _Kind.image => ClipRRect(
                  borderRadius: AppRadius.allMd,
                  child: InteractiveViewer(
                    maxScale: 8,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const _Unreadable(),
                    ),
                  ),
                ),
                _Kind.text => _TextBox(
                  text: utf8.decode(bytes, allowMalformed: true),
                ),
                null => const _Unreadable(),
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _TextBox extends StatelessWidget {
  final String text;

  const _TextBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.allMd,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          width: double.infinity,
          child: text.isEmpty
              ? const Text('This file is empty.').muted.small
              : Text(text).mono.small.selectable,
        ),
      ),
    );
  }
}

class _Unreadable extends StatelessWidget {
  const _Unreadable();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: const Text('This file could not be displayed.').muted.small,
    );
  }
}
