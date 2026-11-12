import 'package:material_ui/material_ui.dart';
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
          'Connected tools with access to $sectionName could not be checked. '
          'Any such tool will also read this record.',
      confirmLabel: 'Add to section',
      confirmIcon: AppIcons.plus,
    );
  }
  final named = [for (final t in tools) '${t.name} (${t.shortId}, ${t.host})'];
  final who = named.length == 1
      ? named.first
      : '${named.sublist(0, named.length - 1).join(', ')} and ${named.last}';
  return showAppDialog(
    context: context,
    title: tools.length == 1
        ? 'Allow ${tools.first.displayName} to read $recordName?'
        : 'Allow ${tools.length} tools to read $recordName?',
    message:
        '$who can read every record in $sectionName. Removing the record from '
        'the section ends that access.',
    confirmLabel: 'Add to section',
    confirmIcon: AppIcons.plus,
  );
}
