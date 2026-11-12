import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/group.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';

/// Who sees an item beside its owner (VISIBILITY.md): `private`, `workspace`
/// or `groups`, with the group ids for the last.
@immutable
class Audience {
  final String kind;
  final List<String> groups;

  const Audience(this.kind, [this.groups = const []]);

  static const private = Audience('private');

  /// Everyone [audiences] reach together: a vault record is seen by its own
  /// audience and by each section's holding it. The workspace covers every
  /// group; otherwise the groups add up; with neither it stays private.
  factory Audience.combined(Iterable<Audience> audiences) {
    final groups = <String>{};
    for (final a in audiences) {
      switch (a.effectiveKind) {
        case 'workspace':
          return const Audience('workspace');
        case 'groups':
          groups.addAll(a.groups);
      }
    }
    return groups.isEmpty ? private : Audience('groups', groups.toList());
  }

  /// A `groups` audience that names no group reaches nobody but the owner,
  /// so it reads as private.
  String get effectiveKind => kind == 'workspace'
      ? 'workspace'
      : kind == 'groups' && groups.isNotEmpty
      ? 'groups'
      : 'private';

  bool get isPrivate => effectiveKind == 'private';

  /// The ids a "Visible to" filter knows this audience by: `private`,
  /// `workspace`, or `group:<id>` for each group.
  Set<String> get filterIds => switch (effectiveKind) {
    'workspace' => const {'workspace'},
    'groups' => {for (final g in groups) 'group:$g'},
    _ => const {'private'},
  };
}

/// Whether audiences are worth showing at all: in a workspace of one, every
/// item is private and a tag on each row would only repeat it.
bool audiencesShown() => Stores.invites.members.length > 1;

/// Whether an item passes a "Visible to" filter: nothing ticked lets all
/// through, otherwise any of [audiences] (an item and, in the vault, the
/// sections holding it) has to match a ticked one.
bool audienceMatches(Set<String> selected, Iterable<Audience> audiences) =>
    selected.isEmpty ||
    audiences.any((a) => a.filterIds.any(selected.contains));

/// The "Visible to" section of a list's Filter: Private, Workspace and each
/// group of the workspace, with how many of [items] each lets through. An
/// item may count under several (two groups, or a record and its section).
/// Null in a workspace of one where every item is private, so the Filter
/// does not offer a choice that changes nothing.
AppChecklistSection? audienceFilterSection({
  required List<Iterable<Audience>> items,
  required Set<String> selected,
  required void Function(String id, bool on) onToggle,
}) {
  final anyShared = items.any((a) => a.any((x) => !x.isPrivate));
  if (!audiencesShown() && !anyShared && selected.isEmpty) return null;
  int count(String id) =>
      items.where((a) => a.any((x) => x.filterIds.contains(id))).length;
  return AppChecklistSection(
    title: 'Visible to',
    selected: selected,
    onToggle: onToggle,
    items: [
      AppChecklistItem(
        id: 'private',
        label: 'Private',
        count: count('private'),
      ),
      AppChecklistItem(
        id: 'workspace',
        label: 'Workspace',
        count: count('workspace'),
      ),
      for (final g in Stores.settings.groups)
        AppChecklistItem(
          id: 'group:${g.id}',
          label: g.name,
          count: count('group:${g.id}'),
        ),
    ],
  );
}

/// Asks the [AudienceTag]s below for their icon only, where the place they
/// sit in is narrow though the window is not: a list beside an open page.
class AudienceCompact extends InheritedWidget {
  final bool compact;

  const AudienceCompact({
    super.key,
    required this.compact,
    required super.child,
  });

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AudienceCompact>()?.compact ??
      false;

  @override
  bool updateShouldNotify(AudienceCompact old) => old.compact != compact;
}

/// Who sees an item, as a tag at the end of its row: a dashed outline and a
/// lock for Private, a filled tag for Workspace, and each group's name with
/// its own color dot. The three read apart without color; the dots tell
/// groups apart from each other. A tooltip and the screen reader say how many
/// people that is.
///
/// A Private tag is hidden in a workspace of one (see [audiencesShown]),
/// unless [always]: nobody else could see the item anyway. An item open to
/// others always says so, even before the members have loaded.
class AudienceTag extends StatelessWidget {
  final Audience audience;

  /// The tag on its own, without the single-member check — for a page about
  /// the item itself.
  final bool always;

  /// Only the icon, for a narrow place such as the vault's section pane.
  /// Below [AppSpacing.narrowWidth] the tag is always this.
  final bool compact;

  const AudienceTag(
    this.audience, {
    super.key,
    this.always = false,
    this.compact = false,
  });

  /// At most this many group names before "+n".
  static const _maxGroups = 2;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final kind = audience.effectiveKind;
        if (!always && kind == 'private' && !audiencesShown()) {
          return const SizedBox.shrink();
        }
        final known = {for (final g in Stores.settings.groups) g.id: g};
        final groups = [for (final id in audience.groups) ?known[id]];
        final description = _describe(kind, groups);

        // On a phone the row's title needs the width; the icon still tells
        // the three apart, and the tooltip names the groups.
        final iconOnly =
            compact ||
            AudienceCompact.of(context) ||
            MediaQuery.sizeOf(context).width < AppSpacing.narrowWidth;
        final Widget tag;
        if (iconOnly) {
          tag = Icon(
            _icon(kind),
            size: 14,
            color: kind == 'private'
                ? scheme.onSurfaceVariant
                : scheme.onSurface,
          );
        } else if (kind == 'groups') {
          final shown = groups.take(_maxGroups).toList();
          final more = audience.groups.length - shown.length;
          tag = Wrap(
            spacing: AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            children: [
              if (shown.isEmpty) _Pill(icon: AppIcons.group, label: 'Groups'),
              for (final g in shown)
                _Pill(dot: groupColor(g.id, scheme), label: g.name),
              if (more > 0) _Pill(label: '+$more'),
            ],
          );
        } else if (kind == 'workspace') {
          tag = const _Pill(
            icon: AppIcons.building,
            label: 'Workspace',
            filled: true,
          );
        } else {
          tag = const _Pill(
            icon: AppIcons.lock,
            label: 'Private',
            dashed: true,
          );
        }

        // The description replaces the visible words for a screen reader,
        // so the tooltip stays out of the semantics, not said twice.
        return Tooltip(
          message: description,
          excludeFromSemantics: true,
          child: Semantics(
            label: description,
            excludeSemantics: true,
            child: tag,
          ),
        );
      },
    );
  }

  static IconData _icon(String kind) => switch (kind) {
    'workspace' => AppIcons.building,
    'groups' => AppIcons.group,
    _ => AppIcons.lock,
  };

  /// "Visible to HR and Service · 11 people"
  String _describe(String kind, List<WorkspaceGroup> groups) {
    switch (kind) {
      case 'workspace':
        final n = Stores.invites.members.length;
        return n > 1
            ? 'Visible to the workspace · $n people'
            : 'Visible to the workspace';
      case 'groups':
        final names = groups.map((g) => g.name).toList();
        final people = {
          for (final g in groups)
            for (final m in g.members) m.id,
        }.length;
        final who = names.isEmpty
            ? 'groups'
            : names.length == 1
            ? names.single
            : '${names.sublist(0, names.length - 1).join(', ')} and '
                  '${names.last}';
        return people > 0
            ? 'Visible to $who · $people ${people == 1 ? 'person' : 'people'}'
            : 'Visible to $who';
    }
    return 'Private · visible to the owner only';
  }
}

/// A group's color, the same on every row and in every session: picked from
/// its id, from a set that reads on both light and dark surfaces.
Color groupColor(String id, ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  final palette = dark ? _darkGroupColors : _lightGroupColors;
  var hash = 0;
  for (final c in id.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

const _lightGroupColors = [
  Color(0xFF534AB7),
  Color(0xFF0F6E56),
  Color(0xFF993C1D),
  Color(0xFF993556),
  Color(0xFF185FA5),
  Color(0xFF3B6D11),
];

const _darkGroupColors = [
  Color(0xFFAFA9EC),
  Color(0xFF5DCAA5),
  Color(0xFFF0997B),
  Color(0xFFED93B1),
  Color(0xFF85B7EB),
  Color(0xFF97C459),
];

class _Pill extends StatelessWidget {
  final IconData? icon;
  final Color? dot;
  final String label;
  final bool filled;
  final bool dashed;

  const _Pill({
    this.icon,
    this.dot,
    required this.label,
    this.filled = false,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = filled ? scheme.onSurface : scheme.onSurfaceVariant;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            AppSpacing.gapXxs,
          ] else if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            AppSpacing.gapXxs,
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: AppTextSize.small,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    if (dashed) {
      return CustomPaint(
        painter: _DashedBorder(scheme.outline),
        child: content,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? scheme.surfaceContainerHighest : Colors.transparent,
        borderRadius: AppRadius.allMd,
        border: Border.all(
          color: dot ?? (filled ? scheme.outline : scheme.outlineVariant),
        ),
      ),
      child: content,
    );
  }
}

/// The Private tag's outline: dashed, so it reads as "not shared" even
/// without color.
class _DashedBorder extends CustomPainter {
  final Color color;

  _DashedBorder(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = AppRadius.allMd.toRRect(Offset.zero & size).deflate(0.5);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
