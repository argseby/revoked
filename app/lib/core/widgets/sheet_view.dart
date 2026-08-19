import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// One column in a [SheetView].
class SheetColumn {
  final String label;
  final double width;

  /// Right-aligns the cell text and sorts the column numerically.
  final bool numeric;

  const SheetColumn(this.label, {this.width = 150, this.numeric = false});
}

/// One cell value in a [SheetView] row.
class SheetCell {
  final String text;
  final bool mono;
  final Color? color;

  /// Optional leading widget (e.g. a verified shield) rendered before the text.
  final Widget? leading;

  /// Optional tap handler. When set it overrides the default copy-on-tap (e.g.
  /// to open a per-value drawer); otherwise tapping copies the text.
  final VoidCallback? onTap;

  const SheetCell(
    this.text, {
    this.mono = false,
    this.color,
    this.leading,
    this.onTap,
  });

  static const empty = SheetCell('');
}

/// A lightweight, zero-dependency spreadsheet grid: a vertically-pinned header
/// row over a two-axis-scrollable body. Tapping a header sorts by that column
/// (toggling asc/desc); tapping a cell copies its text. Built from native
/// widgets so the body and header share one horizontal scroll for free — the
/// horizontal scroll view wraps both, while only the body scrolls vertically.
class SheetView extends StatefulWidget {
  final List<SheetColumn> columns;
  final List<List<SheetCell>> rows;

  /// Row height in logical pixels.
  final double rowHeight;

  const SheetView({
    super.key,
    required this.columns,
    required this.rows,
    this.rowHeight = 44,
  });

  @override
  State<SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<SheetView> {
  int? _sortCol;
  bool _asc = true;

  final _hController = ScrollController();
  final _vController = ScrollController();

  @override
  void dispose() {
    _hController.dispose();
    _vController.dispose();
    super.dispose();
  }

  List<List<SheetCell>> get _sortedRows {
    final col = _sortCol;
    if (col == null) return widget.rows;
    final numeric = widget.columns[col].numeric;
    final rows = [...widget.rows];
    rows.sort((a, b) {
      final av = col < a.length ? a[col].text : '';
      final bv = col < b.length ? b[col].text : '';
      int cmp;
      if (numeric) {
        cmp = (double.tryParse(av) ?? double.negativeInfinity).compareTo(
          double.tryParse(bv) ?? double.negativeInfinity,
        );
      } else {
        cmp = av.toLowerCase().compareTo(bv.toLowerCase());
      }
      return _asc ? cmp : -cmp;
    });
    return rows;
  }

  void _onHeaderTap(int col) {
    setState(() {
      if (_sortCol == col) {
        _asc = !_asc;
      } else {
        _sortCol = col;
        _asc = true;
      }
    });
  }

  double get _totalWidth => widget.columns.fold(0.0, (sum, c) => sum + c.width);

  @override
  Widget build(BuildContext context) {
    final rows = _sortedRows;
    return Scrollbar(
      controller: _hController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _hController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _totalWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              Expanded(
                child: Scrollbar(
                  controller: _vController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _vController,
                    itemCount: rows.length,
                    itemExtent: widget.rowHeight,
                    itemBuilder: (context, r) =>
                        _buildRow(context, rows[r], r.isEven),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: widget.rowHeight,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          for (var c = 0; c < widget.columns.length; c++)
            _headerCell(context, c),
        ],
      ),
    );
  }

  Widget _headerCell(BuildContext context, int c) {
    final scheme = Theme.of(context).colorScheme;
    final col = widget.columns[c];
    final sorted = _sortCol == c;
    return InkWell(
      onTap: () => _onHeaderTap(c),
      borderRadius: AppRadius.allSm,
      child: Container(
        width: col.width,
        height: widget.rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: col.numeric
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                col.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ).small,
            ),
            if (sorted)
              Icon(
                _asc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 13,
                color: scheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, List<SheetCell> cells, bool even) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: even
            ? null
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          for (var c = 0; c < widget.columns.length; c++)
            _dataCell(
              context,
              widget.columns[c],
              c < cells.length ? cells[c] : SheetCell.empty,
            ),
        ],
      ),
    );
  }

  Widget _dataCell(BuildContext context, SheetColumn col, SheetCell cell) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = cell.text.isNotEmpty;
    return InkWell(
      borderRadius: AppRadius.allSm,
      onTap:
          cell.onTap ??
          (hasText
              ? () {
                  Clipboard.setData(ClipboardData(text: cell.text));
                  AppToast.success(context, 'Copied to clipboard');
                }
              : null),
      child: Container(
        width: col.width,
        height: widget.rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: col.numeric
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (cell.leading != null) ...[cell.leading!, AppSpacing.gapXs],
            Flexible(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color:
                      cell.color ??
                      (hasText
                          ? null
                          : scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                ),
                child: AppText(
                  hasText ? cell.text : '—',
                  small: true,
                  mono: cell.mono,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
