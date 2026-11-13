import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/features/vault/views/builtin_views.dart';
import 'package:revoked_app/features/vault/views/view_data.dart';
import 'package:revoked_app/features/vault/views/view_renderer.dart';
import 'package:revoked_app/features/vault/views/view_spec.dart';

/// A section shown as the thing it describes rather than as a list of
/// records: the first view whose keys the section holds. The records stay as
/// they are; a view only reads them.
class SectionView {
  final ViewSpec spec;
  final ViewData data;
  const SectionView(this.spec, this.data);

  /// The view for [section], reading its own records from [records] and the
  /// rest of the owner's [vault]; null for the plain list.
  ///
  /// The view comes from, in turn: the section itself, when one is saved on
  /// it; a template whose keys the section holds, the most specific first;
  /// the views bundled with the app, for a server whose templates carry
  /// none yet.
  static SectionView? of(
    Section section,
    List<models.Record> records, {
    List<models.Record> vault = const [],
    List<Template> templates = const [],
  }) {
    final own = [
      for (final r in records)
        if (section.records.contains(r.id)) r,
    ];
    if (own.isEmpty && section.view == null) return null;
    final data = ViewData(section: own, vault: vault);
    if (section.view case final json?) {
      if (ViewSpec.parse(json) case final spec?) return SectionView(spec, data);
    }
    final fromTemplates = [
      for (final t in templates)
        if (t.schema['view'] case final Map<String, dynamic> json)
          ?ViewSpec.parse(json),
    ]..sort((a, b) => b.match.length.compareTo(a.match.length));
    for (final spec in [...fromTemplates, ...builtinViews]) {
      if (data.matches(spec)) return SectionView(spec, data);
    }
    return null;
  }
}

/// The views an editor offers to start from: every template's, then the
/// bundled ones, each once.
List<Map<String, dynamic>> viewExamples(List<Template> templates) {
  final seen = <String>{};
  return [
    for (final json in [
      for (final t in templates)
        if (t.schema['view'] case final Map<String, dynamic> v) v,
      ...builtinViewJson,
    ])
      if (json['id'] is String && seen.add(json['id'] as String)) json,
  ];
}

/// A shared section's view, as a recipient sees it: drawn from that
/// section's shared records alone. Only a view saved on the section shows;
/// the recipient's own templates say nothing about someone else's data.
SectionView? sharedSectionView(
  Map<String, dynamic> section,
  Map<String, Map<String, dynamic>> recordsById,
) {
  final json = section['view'];
  if (json is! Map<String, dynamic>) return null;
  final spec = ViewSpec.parse(json);
  if (spec == null) return null;
  String str(Map<String, dynamic> r, String k) =>
      r[k] is String ? r[k] as String : '';
  final own = [
    for (final id in (section['records'] as List? ?? const []))
      if (recordsById[id] case final r?)
        models.Record(
          id: str(r, 'id'),
          key: str(r, 'key'),
          value: r['sealed'] == true ? '' : str(r, 'value'),
          label: str(r, 'label'),
          type: str(r, 'type').isEmpty ? 'text' : str(r, 'type'),
          format: str(r, 'format').isEmpty ? 'default' : str(r, 'format'),
          user: '',
          workspace: '',
        ),
  ];
  return SectionView(spec, ViewData(section: own));
}

/// [view] drawn above the section's records.
class SectionViewCard extends StatelessWidget {
  final SectionView view;
  const SectionViewCard({super.key, required this.view});

  @override
  Widget build(BuildContext context) =>
      ViewRenderer(spec: view.spec, data: view.data);
}
