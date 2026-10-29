import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/core/design/text_styles.dart';

const double _searchHeight = 40;

/// The search box in the top bar of a list tab, bound to the list's
/// [TableStore]. A compact pill rather than a form field: it sits where the
/// screen's title used to, and its hint carries the count the title showed.
///
/// It shares the query with the filter drawer, so typing in either one shows
/// up in the other.
class AppSearchField<T> extends StatefulWidget {
  final TableStore<T> controller;
  final String hint;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
  });

  @override
  State<AppSearchField<T>> createState() => _AppSearchFieldState<T>();
}

class _AppSearchFieldState<T> extends State<AppSearchField<T>> {
  late final ObservableTextController _text = ObservableTextController(
    text: widget.controller.searchQuery,
  );
  late final ReactionDisposer _syncDisposer;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
    // Follows the query when the drawer changes or clears it; the guard stops
    // the two from echoing each other.
    _syncDisposer = reaction<String>((_) => widget.controller.searchQuery, (
      query,
    ) {
      if (_text.text != query) {
        _text.removeListener(_onChanged);
        _text.text = query;
        _text.addListener(_onChanged);
      }
    });
  }

  void _onChanged() {
    if (widget.controller.searchQuery != _text.text) {
      widget.controller.searchQuery = _text.text;
    }
  }

  @override
  void dispose() {
    _syncDisposer();
    _text.removeListener(_onChanged);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Observer(
      builder: (_) => SizedBox(
        height: _searchHeight,
        child: TextField(
          controller: _text,
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: AppTextSize.body),
          decoration: InputDecoration(
            hintText: widget.hint,
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            contentPadding: EdgeInsets.zero,
            border: const OutlineInputBorder(
              borderRadius: AppRadius.allPill,
              borderSide: BorderSide.none,
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: AppRadius.allPill,
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.allPill,
              borderSide: BorderSide(color: scheme.primary),
            ),
            prefixIcon: const Icon(AppIcons.search, size: 18),
            suffixIcon: _text.text.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: AppButton(
                      icon: AppIcons.x,
                      tooltip: 'Clear search',
                      style: AppButtonStyle.accent,
                      size: AppButtonSize.small,
                      onTap: _text.clear,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A search that opens somewhere else instead of filtering in place, such as
/// the shell's "Search or paste a link". Drawn exactly like [AppSearchField],
/// so the app has one search look wherever a search sits.
class AppSearchTrigger extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;
  final Widget? trailing;

  const AppSearchTrigger({
    super.key,
    required this.hint,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      child: AppFocusRing(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.allPill,
            child: Ink(
              height: _searchHeight,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: AppRadius.allPill,
              ),
              child: Row(
                children: [
                  // The width of a field's prefix icon, so the hint starts
                  // where [AppSearchField]'s does.
                  const SizedBox(
                    width: 48,
                    child: Icon(AppIcons.search, size: 18),
                  ),
                  Expanded(
                    child: AppText(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).muted,
                  ),
                  if (trailing != null) ...[
                    trailing!,
                    AppSpacing.gapSm,
                  ] else
                    AppSpacing.gapMd,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
