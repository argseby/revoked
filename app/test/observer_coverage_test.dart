import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A view that reads a store outside an `Observer` compiles, analyzes clean and
/// passes every other test — it simply never repaints. The public request
/// screen lost its wrapper this way and sat on "Retrieving request…" forever,
/// because the probe landed on a tree that no longer listened.
///
/// This is a shape check, not a proof: it requires a file that reads store
/// state to mention `Observer` at all. It cannot tell you the wrapper is in the
/// right place, so it is a floor, not a guarantee.
void main() {
  test('every view that reads a store also builds an Observer', () {
    final offenders = <String>[];

    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (!entity.path.contains('/view/')) continue;

      final source = entity.readAsStringSync();
      final readsStore =
          source.contains('_store.') || source.contains('Stores.');
      if (readsStore && !source.contains('Observer(')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these read observable state but never wrap it — they will not '
          'rebuild:\n${offenders.join('\n')}',
    );
  });

  test('a LayoutBuilder body builds its own Observer', () {
    // The wrapper around a whole build does not reach inside a LayoutBuilder:
    // its callback runs during layout, in a separate build scope, so store
    // reads made there record against no reaction. The screen renders once and
    // then ignores every change — which is how both public screens sat on
    // "Checking…" after their trust verdict had already landed.
    //
    // The reads are rarely in the callback itself; both bugs put them one call
    // down, in a _buildSomething helper. So this follows private calls within
    // the file rather than scanning the body alone.
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final source = entity.readAsStringSync();
      var from = source.indexOf('LayoutBuilder(');
      while (from != -1) {
        final body = _balanced(source, from, '(', ')');
        if (body != null &&
            !body.contains('Observer(') &&
            _readsStore(source, body, {})) {
          offenders.add(entity.path);
          break;
        }
        from = source.indexOf('LayoutBuilder(', from + 1);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these read store state inside a LayoutBuilder without an Observer '
          'in it — the subtree renders once and never again:\n'
          '${offenders.join('\n')}',
    );
  });

  test('a screen whose whole build is one Observer keeps it', () {
    // The wrapper is a one-line `build` delegating to `_build`. Losing that
    // line is invisible to the analyzer, so pin the screens that use it.
    const delegating = [
      'lib/features/requests/view/public_request_screen.dart',
      'lib/features/shares/view/public_share_screen.dart',
    ];

    for (final path in delegating) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('Observer(builder: (_) => _build(context))'),
        isTrue,
        reason: '$path must delegate its build through an Observer',
      );
    }
  });
}

/// True when [body], or any private method of [source] it calls, reads a store.
bool _readsStore(String source, String body, Set<String> seen) {
  if (body.contains('_store.') || body.contains('Stores.')) return true;

  for (final match in RegExp(r'\b(_\w+)\s*\(').allMatches(body)) {
    final name = match.group(1)!;
    if (!seen.add(name)) continue;
    final decl = RegExp('\\b$name\\s*\\(').allMatches(source);
    for (final d in decl) {
      final open = source.indexOf('{', d.end);
      if (open == -1) continue;
      final callee = _balanced(source, open, '{', '}');
      // A declaration, not the call site: its body starts at the brace that
      // follows the parameter list, so anything else is some other expression.
      if (callee == null || callee.length < 2) continue;
      if (_readsStore(source, callee, seen)) return true;
    }
  }
  return false;
}

/// The substring from the first [open] at or after [start] to its match.
String? _balanced(String source, int start, String open, String close) {
  final from = source.indexOf(open, start);
  if (from == -1) return null;
  var depth = 0;
  for (var i = from; i < source.length; i++) {
    if (source[i] == open) depth++;
    if (source[i] == close) {
      depth--;
      if (depth == 0) return source.substring(from, i + 1);
    }
  }
  return null;
}
