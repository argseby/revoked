import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';

/// Asks before [record] goes into a section a connected tool can read: putting
/// it there hands it to the tool. True when nothing reads the section, or the
/// owner agreed.
Future<bool> confirmToolsReach(
  BuildContext context,
  Section section,
  models.Record record,
) async {
  final tools = await Stores.connections.toolsReaching(section.id);
  if (tools != null && tools.isEmpty) return true;
  if (!context.mounted) return false;
  final sectionName = section.name.isEmpty ? section.key : section.name;
  final recordName = record.label.isEmpty ? record.key : record.label;
  if (tools == null) {
    return showAppDialog(
      context: context,
      title: 'Add $recordName to $sectionName?',
      message:
          'We couldn’t check which connected tools can read $sectionName. '
          'Any that can will read this record too.',
      confirmLabel: 'Add to section',
      confirmIcon: AppIcons.plus,
    );
  }
  final named = [for (final t in tools) '${t.name} (${t.host})'];
  final who = named.length == 1
      ? named.first
      : '${named.sublist(0, named.length - 1).join(', ')} and ${named.last}';
  return showAppDialog(
    context: context,
    title: tools.length == 1
        ? 'Let ${tools.first.name} read $recordName?'
        : 'Let ${tools.length} tools read $recordName?',
    message:
        '$who can read every record in $sectionName. Remove the record from '
        'the section to stop that.',
    confirmLabel: 'Add to section',
    confirmIcon: AppIcons.plus,
  );
}
