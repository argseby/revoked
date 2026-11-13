import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';

/// One group of things that belong together in a composer: a bordered card
/// with a title, a line on what it is for, and its controls. Fields, choices
/// and previews all sit in one, so every create sheet reads the same way.
class AppComposerCard extends StatelessWidget {
  final String? title;
  final String? description;

  /// Beside the title: a switch or small button that acts on the card.
  final Widget? trailing;
  final Widget child;

  /// Off for a card placed in a container that already has its margins.
  final bool inset;

  /// A required field that is still empty: outlined in the primary color,
  /// with [AppRequiredBadge] after the title.
  final bool missing;

  const AppComposerCard({
    super.key,
    this.title,
    this.description,
    this.trailing,
    required this.child,
    this.inset = true,
    this.missing = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasHeading = title != null || trailing != null;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.allLg,
        border: missing
            ? Border.all(color: scheme.primary, width: 1.5)
            : Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasHeading)
              Row(
                children: [
                  Expanded(
                    child: title == null
                        ? const SizedBox.shrink()
                        : !missing
                        ? Semantics(header: true, child: AppText(title!).bold)
                        // Wraps under a long title rather than squeezing a
                        // trailing switch off the card.
                        : Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xxs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Semantics(
                                header: true,
                                child: AppText(title!).bold,
                              ),
                              const AppRequiredBadge(),
                            ],
                          ),
                  ),
                  if (trailing != null) ...[AppSpacing.gapSm, trailing!],
                ],
              ),
            if (description != null) ...[
              if (hasHeading) AppSpacing.gapXxs,
              Text(description!).small.muted,
            ],
            if (hasHeading || description != null) AppSpacing.gapMd,
            child,
          ],
        ),
      ),
    );
    if (!inset) return card;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.xs,
      ),
      child: card,
    );
  }
}

/// A label inside a card that holds several controls ("Clock", "Time
/// zone"): smaller than the card's title, so the card still reads as one.
class AppComposerSubLabel extends StatelessWidget {
  final String label;
  const AppComposerSubLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(label).small.bold,
  );
}

/// One input as a card: its label, what it is for, the input, and a note or
/// error below it.
class AppComposerField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? explanation;
  final String? error;
  final String? note;
  final Widget? action;
  final Widget? trailing;
  final bool inset;

  /// A required field that is still empty: outlined in the primary color,
  /// with [AppRequiredBadge] beside the label.
  final bool missing;

  const AppComposerField({
    super.key,
    required this.label,
    required this.child,
    this.explanation,
    this.error,
    this.note,
    this.action,
    this.trailing,
    this.inset = true,
    this.missing = false,
  });

  @override
  Widget build(BuildContext context) => AppComposerCard(
    title: label,
    description: explanation,
    trailing: trailing,
    inset: inset,
    missing: missing,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        if (error != null) ...[
          AppSpacing.gapXs,
          AppErrorText(error!),
        ] else if (note != null) ...[
          AppSpacing.gapXs,
          Text(note!).small.muted,
        ],
        if (action != null) ...[AppSpacing.gapSm, action!],
      ],
    ),
  );
}

/// A persistent navigation rail beside a scrollable editor, like record types.
/// At phone widths the choices sit above the editor in the same scroll view.
class AppComposerLayout extends StatelessWidget {
  final Widget rail;
  final Widget child;

  const AppComposerLayout({super.key, required this.rail, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale =
          MediaQuery.textScalerOf(context).scale(AppTextSize.body) /
          AppTextSize.body;
      if (box.maxWidth < AppSpacing.narrowWidth * scale) {
        return child;
      }
      final scheme = Theme.of(context).colorScheme;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 168,
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              border: BorderDirectional(
                end: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xxl,
              ),
              child: rail,
            ),
          ),
          Expanded(child: child),
        ],
      );
    },
  );
}

class AppComposerChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const AppComposerChoice({
    super.key,
    required this.label,
    required this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainer,
        borderRadius: AppRadius.allMd,
        child: ListTile(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMd),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          minLeadingWidth: 18,
          horizontalTitleGap: AppSpacing.sm,
          leading: Icon(icon, size: 18, color: color),
          title: DefaultTextStyle.merge(
            style: TextStyle(color: color),
            child: Text(label).small,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class AppComposerSection {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const AppComposerSection({
    required this.title,
    required this.icon,
    required this.children,
  });
}

/// Every group stays on one scrolling page. The rail beside it is a table of
/// contents: a tap scrolls to a group, and the group in view stays marked
/// while the page is scrolled by hand.
class AppComposerSections extends StatefulWidget {
  final List<AppComposerSection> sections;
  final bool enabled;

  /// Names the scrolling page, for tests and for keeping its offset.
  final Key? editorKey;

  const AppComposerSections({
    super.key,
    required this.sections,
    this.enabled = true,
    this.editorKey,
  });

  @override
  State<AppComposerSections> createState() => _AppComposerSectionsState();
}

class _AppComposerSectionsState extends State<AppComposerSections> {
  final Map<String, GlobalKey> _anchors = {};
  final _viewport = GlobalKey();
  final _scroll = ScrollController();
  final _selected = Local<String?>(null);

  /// Set while a rail tap scrolls, so the groups passed on the way do not
  /// flicker through the rail.
  String? _jumpingTo;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_track);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The marked group is the last one whose heading has reached the upper
  /// part of the page; at the very end, the last group.
  void _track() {
    if (_jumpingTo != null || !_scroll.hasClients) return;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final sections = widget.sections;
    if (sections.isEmpty) return;
    final position = _scroll.position;
    var current = sections.first.title;
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 1) {
      current = sections.last.title;
    } else {
      final line = (viewport.size.height * 0.25).clamp(24.0, 120.0);
      for (final section in sections) {
        final box = _anchors[section.title]?.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached) continue;
        final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        if (top > line) break;
        current = section.title;
      }
    }
    if (_selected.value != current) _selected.value = current;
  }

  Future<void> _jump(String title) async {
    _selected.value = title;
    final target = _anchors[title]?.currentContext;
    if (target == null) return;
    _jumpingTo = title;
    try {
      await Scrollable.ensureVisible(
        target,
        duration: AppMotion.of(context),
        curve: AppMotion.curve,
      );
    } finally {
      _jumpingTo = null;
    }
    // A short last group cannot reach the top; the tap still marks it.
    if (mounted) _selected.value = title;
  }

  @override
  Widget build(BuildContext context) =>
      Observer(builder: (_) => _build(context));

  Widget _build(BuildContext context) {
    final titles = {for (final s in widget.sections) s.title};
    _anchors.removeWhere((title, _) => !titles.contains(title));
    for (final title in titles) {
      _anchors.putIfAbsent(title, GlobalKey.new);
    }
    final selected = titles.contains(_selected.value)
        ? _selected.value
        : widget.sections.firstOrNull?.title;
    return ExcludeFocus(
      excluding: !widget.enabled,
      child: IgnorePointer(
        ignoring: !widget.enabled,
        child: AppComposerLayout(
          rail: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final section in widget.sections) ...[
                _AppComposerAnchor(
                  label: section.title,
                  icon: section.icon,
                  selected: selected == section.title,
                  onTap: () => _jump(section.title),
                ),
                AppSpacing.gapXxs,
              ],
            ],
          ),
          child: KeyedSubtree(
            key: widget.editorKey,
            child: SingleChildScrollView(
              key: _viewport,
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, section) in widget.sections.indexed)
                    Column(
                      key: _anchors[section.title],
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (index > 0)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.xxl,
                            ),
                            child: Divider(height: 1),
                          ),
                        _AppComposerHeading(section: section),
                        ...section.children,
                        AppSpacing.gapLg,
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppComposerHeading extends StatelessWidget {
  final AppComposerSection section;
  const _AppComposerHeading({required this.section});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xxl,
      AppSpacing.xl,
      AppSpacing.xxl,
      AppSpacing.xs,
    ),
    child: Semantics(
      header: true,
      child: Row(
        children: [
          Icon(
            section.icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          AppSpacing.gapSm,
          Expanded(child: Text(section.title).header),
        ],
      ),
    ),
  );
}

/// A rail entry that points into the page rather than choosing a value: a
/// quiet tint and an accent bar mark the group in view.
class _AppComposerAnchor extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AppComposerAnchor({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
        borderRadius: AppRadius.allMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTarget),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : Colors.transparent,
                    borderRadius: AppRadius.allMd,
                  ),
                ),
                AppSpacing.gapSm,
                Icon(icon, size: 18, color: selected ? scheme.primary : color),
                AppSpacing.gapSm,
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                    child: Text(label).small,
                  ),
                ),
                AppSpacing.gapSm,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The composer's footer, as in the record editor: Cancel and the primary
/// action at the end of one compact row.
class AppComposerFooter extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onSubmit;
  final VoidCallback? onCancel;

  const AppComposerFooter({
    super.key,
    required this.label,
    required this.icon,
    required this.onSubmit,
    required this.onCancel,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.md,
    ),
    child: Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Cancel',
            style: AppButtonStyle.ghost,
            onTap: onCancel,
          ),
          AppSpacing.gapSm,
          Flexible(
            child: AppButton(
              trailingIcon: icon,
              label: label,
              busy: busy,
              onTap: onSubmit,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Who may see what is being made, as a card. Every create sheet asks it
/// the same way.
class AppComposerVisibility extends StatelessWidget {
  final Widget field;
  const AppComposerVisibility({super.key, required this.field});

  @override
  Widget build(BuildContext context) => AppComposerCard(
    title: 'Visible to',
    description: 'Who in this workspace can see it.',
    child: field,
  );
}

/// The API request the form would send, as a card in the Developer section.
class AppComposerApiPreview extends StatelessWidget {
  final Widget preview;
  const AppComposerApiPreview({super.key, required this.preview});

  @override
  Widget build(BuildContext context) => AppComposerCard(
    description: 'The same action as an API request, for scripts and '
        'integrations.',
    child: preview,
  );
}

/// How tall a composer may grow. A phone's bottom sheet leaves a strip of
/// the page showing; the side panel is filled, so the footer sits on its
/// bottom edge instead of above an empty band.
double composerMaxHeight(BuildContext context) => AppSpacing.isNarrow(context)
    ? MediaQuery.sizeOf(context).height * 0.9
    : double.infinity;
