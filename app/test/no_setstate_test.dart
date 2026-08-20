import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A view holds no state of its own: it reads a store and wraps what changes in
/// an Observer. These are the three ways that rule drifted — 153 `setState`
/// calls, 7 `StatefulBuilder`s whose callback was named `setSheetState` so a
/// grep for `setState` missed them, and stores handing views a plain
/// `TextEditingController`, which MobX cannot see (a screen gating its save
/// button on `controller.text` simply froze).
void main() {
  List<String> scan(String root, RegExp pattern) {
    final hits = <String>[];
    for (final entity in Directory(root).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in pattern.allMatches(source)) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        hits.add('${entity.path}:$line');
      }
    }
    return hits;
  }

  test('no setState anywhere in lib', () {
    expect(
      scan('lib', RegExp(r'\bsetState\s*\(')),
      isEmpty,
      reason: 'state belongs in a store (or a Local), read through an Observer',
    );
  });

  test('no StatefulBuilder — it is setState under another name', () {
    expect(
      scan('lib', RegExp(r'\bStatefulBuilder\b')),
      isEmpty,
      reason:
          'a sheet that needs state needs a store; rebuild with an Observer',
    );
  });

  test('a view never disposes something a store owns', () {
    // Stores are singletons, so disposing one of their controllers kills it
    // for every later visit: the link-search drawer threw
    // "used after being disposed" the second time it was opened.
    expect(
      scan('lib', RegExp(r'(_?store|Stores)\.[\w.]*\.dispose\s*\(')),
      isEmpty,
      reason: 'a singleton outlives the view; let the store keep its own',
    );
  });

  test('stores never own a plain TextEditingController', () {
    expect(
      scan('lib', RegExp(r'(?<!Observable)TextEditingController\s*\(')),
      isEmpty,
      reason:
          'use ObservableTextController, or typing will not rebuild anything',
    );
  });
}
