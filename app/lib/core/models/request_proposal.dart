import 'package:revoked_app/core/models/tool_client.dart';

/// A request a tool asks the owner to create, carried by a
/// `revoked://pr?template=…&label=…` link.
///
/// The tool names a template and the request's settings. The owner picks the
/// identity, checks the rest and creates it; the request's link and its
/// answers go to the owner alone.
class RequestProposal {
  /// A template, by name, saying what the request asks for.
  final String template;

  /// The request's title; empty to use the template's name.
  final String label;

  /// Days until the request closes; null for no end.
  final int? days;

  final ToolProposer proposer;

  /// Who in the owner's workspace the tool suggests should see the request
  /// and its answers: `private`, `workspace`, or empty for no suggestion.
  /// Only pre-fills the choice; the owner confirms (VISIBILITY.md §7).
  final String visibility;

  const RequestProposal({
    required this.template,
    this.label = '',
    this.days,
    this.proposer = ToolProposer.none,
    this.visibility = '',
  });

  static const maxLabel = 120;
  static const maxTemplate = 80;
  static const maxDays = 365;

  static String? _line(String? raw, int max) {
    final s = (raw ?? '')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s.length > max ? null : s;
  }

  /// Reads a proposal from a link's query, or null when any part is invalid.
  static RequestProposal? fromQuery(Map<String, String> query) {
    final template = _line(query['template'], maxTemplate);
    if (template == null || template.isEmpty) return null;
    final label = _line(query['label'], maxLabel);
    if (label == null) return null;
    int? days;
    final rawDays = query['days'] ?? '';
    if (rawDays.isNotEmpty) {
      days = int.tryParse(rawDays);
      if (days == null || days < 1 || days > maxDays) return null;
    }
    final proposer = ToolProposer.fromQuery(query);
    if (proposer == null) return null;
    final visibility = query['visibility'] ?? '';
    if (visibility.isNotEmpty &&
        visibility != 'private' &&
        visibility != 'workspace') {
      return null;
    }
    return RequestProposal(
      template: template,
      label: label,
      days: days,
      proposer: proposer,
      visibility: visibility,
    );
  }

  Map<String, String> toQuery() => {
    'template': template,
    if (label.isNotEmpty) 'label': label,
    if (days != null) 'days': '$days',
    ...proposer.toQuery(),
    if (visibility.isNotEmpty) 'visibility': visibility,
  };
}
