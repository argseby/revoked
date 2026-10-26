import 'package:revoked_app/core/models/link.dart';

/// Links grouped by who holds them. A recipient is a link's label, compared
/// trimmed and without case, so "Property manager" given two links is one
/// recipient. Labels are what the owner typed, not verified identities.
List<List<Link>> groupByRecipient(Iterable<Link> links) {
  final groups = <String, List<Link>>{};
  for (final l in links) {
    groups.putIfAbsent(l.label.trim().toLowerCase(), () => []).add(l);
  }
  return groups.values.toList();
}

/// Whether a recipient can still open any of their links: an active or a
/// paused one, which can be activated again.
bool recipientHasAccess(List<Link> links) =>
    links.any((l) => l.status == 'active' || l.status == 'paused');

/// The status that says the most about a recipient: active if any link is,
/// then paused, then whatever ended the first one.
String recipientStatus(List<Link> links) {
  if (links.any((l) => l.status == 'active')) return 'active';
  if (links.any((l) => l.status == 'paused')) return 'paused';
  return links.first.status;
}

/// "2 links · 5 records · 1 section"
String recipientSummary(List<Link> links) {
  final records = {for (final l in links) ...l.records}.length;
  final sections = {for (final l in links) ...l.sections}.length;
  return [
    '${links.length} ${links.length == 1 ? 'link' : 'links'}',
    if (records > 0) '$records ${records == 1 ? 'record' : 'records'}',
    if (sections > 0) '$sections ${sections == 1 ? 'section' : 'sections'}',
  ].join(' · ');
}
