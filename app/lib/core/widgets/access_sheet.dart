import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// What the access sheet says about one kind of item: a section, a share or
/// a request. The words differ; the choice is the same (VISIBILITY.md).
class AccessArea {
  /// The server's collection, for GET /api/access/{collection}/{id}.
  final String collection;

  /// "Seen by every member who can …" for the workspace option.
  final String workspaceHint;

  /// The label of the editing option that opens it to the audience.
  final String audienceEditLabel;

  /// What owner-only editing leaves the others.
  final String ownerEditHint;

  /// What audience editing allows them.
  final String audienceEditHint;

  const AccessArea({
    required this.collection,
    required this.workspaceHint,
    required this.audienceEditLabel,
    required this.ownerEditHint,
    required this.audienceEditHint,
  });

  static const sections = AccessArea(
    collection: 'sections',
    workspaceHint:
        'Seen by every member who can read the vault, with current values. '
        'Encrypted records open only for members given access to encryption.',
    audienceEditLabel: 'Members who manage the vault',
    ownerEditHint: 'Others can open its records but not change them.',
    audienceEditHint:
        'Members who see it and may manage the vault can change its records '
        'and the section.',
  );

  static const shares = AccessArea(
    collection: 'links',
    workspaceHint:
        'Seen by every member who can view shares. Whoever sees a share can '
        'open its link, and with it everything the link holds.',
    audienceEditLabel: 'Members who manage shares',
    ownerEditHint: 'Others can see it but not pause, revoke or change it.',
    audienceEditHint:
        'Members who see it and may manage shares can pause, revoke and '
        'change it.',
  );

  static const templates = AccessArea(
    collection: 'templates',
    workspaceHint: 'Seen by every member, who can ask with it.',
    audienceEditLabel: 'Members who manage templates',
    ownerEditHint: 'Others can use it but not change or delete it.',
    audienceEditHint:
        'Members who see it and may manage templates can change and delete '
        'it.',
  );

  static const contacts = AccessArea(
    collection: 'contacts',
    workspaceHint: 'Seen by every member, who can send to it and ask from it.',
    audienceEditLabel: 'Members who manage contacts',
    ownerEditHint: 'Others can use it but not rename or remove it.',
    audienceEditHint:
        'Members who see it and may manage contacts can rename and remove it.',
  );

  static const attestations = AccessArea(
    collection: 'attestations',
    workspaceHint: 'Seen by every member who can view attestations.',
    audienceEditLabel: 'Members who issue attestations',
    ownerEditHint:
        'Others can see it but not revoke it. Revoking also takes the '
        'permission to issue, for the owner too.',
    audienceEditHint:
        'Members who see it and may issue attestations can revoke it.',
  );

  static const requests = AccessArea(
    collection: 'requests',
    workspaceHint:
        'Seen by every member who can view requests. Its answers are shown '
        'to those of them who may read collected data.',
    audienceEditLabel: 'Members who manage requests',
    ownerEditHint: 'Others can see it but not close or change it.',
    audienceEditHint:
        'Members who see it and may manage requests can close and change it.',
  );
}

/// Opens who sees and who edits one of this person's items. [save] sends the
/// chosen audience and editing; the summary underneath is the server's
/// answer, never worked out here.
Future<void> openAccessSheet(
  BuildContext context, {
  required AccessArea area,
  required String id,
  required String name,
  required String audienceKind,
  required String editing,
  required Future<bool> Function(
    String kind,
    String editing,
    List<String> groups,
  )
  save,
  required String? Function() saveError,
}) => showAppSheet<void>(
  context: context,
  dismissible: true,
  builder: (_) => _AccessSheet(
    area: area,
    id: id,
    name: name,
    audienceKind: audienceKind,
    editing: editing,
    save: save,
    saveError: saveError,
  ),
);

class _AccessSheet extends StatefulWidget {
  final AccessArea area;
  final String id;
  final String name;
  final String audienceKind;
  final String editing;
  final Future<bool> Function(String kind, String editing, List<String> groups)
  save;
  final String? Function() saveError;

  const _AccessSheet({
    required this.area,
    required this.id,
    required this.name,
    required this.audienceKind,
    required this.editing,
    required this.save,
    required this.saveError,
  });

  @override
  State<_AccessSheet> createState() => _AccessSheetState();
}

class _AccessSheetState extends State<_AccessSheet> {
  late final Local<String> _kind = Local(
    widget.audienceKind == 'workspace' || widget.audienceKind == 'groups'
        ? widget.audienceKind
        : 'private',
  );

  /// The groups chosen, once the summary says which the item names now.
  final Local<Set<String>> _groups = Local(const {});
  Set<String> _initialGroups = const {};
  late final Local<String> _editing = Local(widget.editing);
  final Local<Map<String, dynamic>?> _summary = Local(null);
  final Local<String?> _summaryError = Local(null);
  final Local<bool> _saving = Local(false);

  @override
  void initState() {
    super.initState();
    _loadSummary();
    Stores.settings.loadGroups();
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await Stores.vault.loadAccess(
        widget.area.collection,
        widget.id,
      );
      final named = <String>{
        for (final g
            in ((summary['audience'] as Map?)?['groups'] as List?) ?? const [])
          if (g is Map && g['id'] is String) g['id'] as String,
      };
      _initialGroups = named;
      _groups.value = named;
      _summary.value = summary;
    } catch (e) {
      _summaryError.value = describeError(e);
    }
  }

  bool get _changed =>
      _kind.value != widget.audienceKind ||
      (_kind.value != 'private' && _editing.value != widget.editing) ||
      (_kind.value == 'groups' &&
          (_groups.value.length != _initialGroups.length ||
              !_groups.value.containsAll(_initialGroups)));

  /// A groups audience needs at least one group.
  bool get _complete => _kind.value != 'groups' || _groups.value.isNotEmpty;

  Future<void> _save() async {
    _saving.value = true;
    final done = await widget.save(
      _kind.value,
      _kind.value == 'private' ? 'owner' : _editing.value,
      _kind.value == 'groups' ? _groups.value.toList() : const [],
    );
    if (!mounted) return;
    _saving.value = false;
    if (done) {
      AppToast.success(context, 'Visibility saved');
      Navigator.of(context).pop();
    } else {
      AppToast.error(
        context,
        'The visibility could not be saved',
        subtitle: widget.saveError(),
      );
    }
  }

  String _summaryLine() {
    final summary = _summary.value;
    if (summary == null) return _summaryError.value ?? 'Loading who sees it…';
    final readers = (summary['readers'] as Map?)?['count'] as int? ?? 1;
    final editors = (summary['editors'] as Map?)?['count'] as int? ?? 1;
    final seen = readers <= 1
        ? 'Seen by the owner only'
        : 'Seen by $readers members';
    final edited = editors <= 1
        ? 'changed by the owner only'
        : 'changed by $editors members';
    return '$seen · $edited.';
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.area;
    return Observer(
      builder: (_) {
        final kind = _kind.value;
        final editing = _editing.value;
        final saving = _saving.value;
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
              Text('Visibility of "${widget.name}"').header,
              const SizedBox(height: AppSpacing.lg),
              const Text('Visible to').small.muted,
              const SizedBox(height: AppSpacing.xs),
              AppSegmented<String>(
                value: kind,
                expand: true,
                items: [
                  const AppSegmentedItem(
                    value: 'private',
                    label: 'Private',
                    icon: AppIcons.lock,
                  ),
                  const AppSegmentedItem(
                    value: 'workspace',
                    label: 'Workspace',
                    icon: AppIcons.building,
                  ),
                  // Offered once the workspace has groups to name.
                  if (Stores.settings.groups.isNotEmpty || kind == 'groups')
                    const AppSegmentedItem(
                      value: 'groups',
                      label: 'Groups',
                      icon: AppIcons.person,
                    ),
                ],
                onChanged: (v) => _kind.value = v,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(switch (kind) {
                'private' => 'Seen by the owner only.',
                'groups' =>
                  'Seen by the members of the groups ticked below, with the '
                      'same permissions as for the workspace.',
                _ => area.workspaceHint,
              }).small.muted,
              if (kind == 'groups')
                for (final g in Stores.settings.groups)
                  Row(
                    children: [
                      AppCheckbox(
                        value: _groups.value.contains(g.id),
                        onChanged: (on) => _groups.value = on == true
                            ? {..._groups.value, g.id}
                            : ({..._groups.value}..remove(g.id)),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: Text(g.name)),
                      Text(
                        '${g.members.length} '
                        '${g.members.length == 1 ? 'member' : 'members'}',
                      ).small.muted,
                    ],
                  ),
              if (kind != 'private') ...[
                const SizedBox(height: AppSpacing.lg),
                const Text('Editing').small.muted,
                const SizedBox(height: AppSpacing.xs),
                AppSegmented<String>(
                  value: editing,
                  expand: true,
                  items: [
                    const AppSegmentedItem(
                      value: 'owner',
                      label: 'Owner only',
                      icon: AppIcons.person,
                    ),
                    AppSegmentedItem(
                      value: 'audience',
                      label: area.audienceEditLabel,
                      icon: AppIcons.pen,
                    ),
                  ],
                  onChanged: (v) => _editing.value = v,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  editing == 'owner'
                      ? area.ownerEditHint
                      : area.audienceEditHint,
                ).small.muted,
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(_summaryLine()).small.muted,
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  icon: AppIcons.check,
                  label: 'Save visibility',
                  style: AppButtonStyle.accent,
                  busy: saving,
                  onTap: _changed && _complete && !saving ? _save : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Visible to" in a create sheet: Private or Workspace, pre-filled from a
/// tool's suggestion, the workspace's default, or the area's built-in
/// default. [value] is the sheet's own state; [suggestedByTool] adds the line
/// saying where the choice came from.
class VisibleToField extends StatelessWidget {
  final Local<String> value;
  final bool suggestedByTool;

  const VisibleToField({
    super.key,
    required this.value,
    this.suggestedByTool = false,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Visible to').small.muted,
          const SizedBox(height: AppSpacing.xs),
          AppSegmented<String>(
            value: value.value == 'workspace' ? 'workspace' : 'private',
            expand: true,
            items: const [
              AppSegmentedItem(
                value: 'private',
                label: 'Private',
                icon: AppIcons.lock,
              ),
              AppSegmentedItem(
                value: 'workspace',
                label: 'Workspace',
                icon: AppIcons.building,
              ),
            ],
            onChanged: (v) => value.value = v,
          ),
          if (suggestedByTool) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text('Suggested by the tool.').small.muted,
          ],
        ],
      ),
    );
  }
}

/// Opens who sees new items of each area in a workspace (VISIBILITY.md §4.4).
Future<void> openDefaultVisibilitySheet(
  BuildContext context, {
  required String workspaceId,
  required Map<String, String> current,
  required Future<bool> Function(Map<String, String> defaults) save,
  required String? Function() saveError,
}) => showAppSheet<void>(
  context: context,
  dismissible: true,
  builder: (_) => _DefaultVisibilitySheet(
    current: current,
    save: save,
    saveError: saveError,
  ),
);

class _DefaultVisibilitySheet extends StatefulWidget {
  final Map<String, String> current;
  final Future<bool> Function(Map<String, String> defaults) save;
  final String? Function() saveError;

  const _DefaultVisibilitySheet({
    required this.current,
    required this.save,
    required this.saveError,
  });

  @override
  State<_DefaultVisibilitySheet> createState() =>
      _DefaultVisibilitySheetState();
}

class _DefaultVisibilitySheetState extends State<_DefaultVisibilitySheet> {
  static const _areas = [
    ('sections', 'Vault sections'),
    ('links', 'Shares'),
    ('requests', 'Requests and answers'),
    ('templates', 'Templates'),
    ('contacts', 'Contacts'),
    ('attestations', 'Attestations'),
  ];

  late final Map<String, Local<String>> _values = {
    for (final (key, _) in _areas) key: Local(widget.current[key]!),
  };
  final Local<bool> _saving = Local(false);

  Future<void> _save() async {
    _saving.value = true;
    final done = await widget.save({
      for (final e in _values.entries) e.key: e.value.value,
    });
    if (!mounted) return;
    _saving.value = false;
    if (done) {
      AppToast.success(context, 'Defaults saved');
      Navigator.of(context).pop();
    } else {
      AppToast.error(
        context,
        'The defaults could not be saved',
        subtitle: widget.saveError(),
      );
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
          const Text('Default visibility for new items').header,
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            'New items start with these settings and can be changed when '
            'created. Existing items keep theirs.',
          ).small.muted,
          for (final (key, label) in _areas) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(label).small.muted,
            const SizedBox(height: AppSpacing.xs),
            Observer(
              builder: (_) => AppSegmented<String>(
                value: _values[key]!.value,
                expand: true,
                items: const [
                  AppSegmentedItem(
                    value: 'private',
                    label: 'Private',
                    icon: AppIcons.lock,
                  ),
                  AppSegmentedItem(
                    value: 'workspace',
                    label: 'Workspace',
                    icon: AppIcons.building,
                  ),
                ],
                onChanged: (v) => _values[key]!.value = v,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: Observer(
              builder: (_) => AppButton(
                icon: AppIcons.check,
                label: 'Save defaults',
                style: AppButtonStyle.accent,
                busy: _saving.value,
                onTap: _saving.value ? null : _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
