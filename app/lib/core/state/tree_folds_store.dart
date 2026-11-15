import 'dart:convert';

import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'tree_folds_store.g.dart';

/// A tree whose rows fold, and which way its rows start.
enum TreeFold {
  /// Sources in the vault, open until folded.
  vaultSources(startsOpen: true),

  /// Links, closed until opened to what they expose.
  links(startsOpen: false),

  /// Requests, closed until opened to their answers.
  requests(startsOpen: false),

  /// Template rows in the requests list, open until folded.
  requestTemplates(startsOpen: true);

  final bool startsOpen;
  const TreeFold({required this.startsOpen});
}

/// Which rows of the vault, links and requests trees were folded or opened,
/// kept on the device so a screen comes back the way it was left.
// ignore: library_private_types_in_public_api
class TreeFoldsStore = _TreeFoldsStore with _$TreeFoldsStore;

abstract class _TreeFoldsStore with Store {
  static const _key = 'tree_folds';

  /// Per tree, the rows turned away from how they start.
  final ObservableMap<TreeFold, ObservableSet<String>> _changed =
      ObservableMap();

  bool isOpen(TreeFold tree, String id) =>
      (_changed[tree]?.contains(id) ?? false) != tree.startsOpen;

  /// The rows of [tree] that are open, for a tree whose rows start closed.
  Set<String> opened(TreeFold tree) =>
      tree.startsOpen ? const {} : {...?_changed[tree]};

  @action
  void toggle(TreeFold tree, String id) {
    final changed = _changed.putIfAbsent(tree, ObservableSet.new);
    if (!changed.remove(id)) changed.add(id);
    _save();
  }

  @action
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      runInAction(() {
        for (final tree in TreeFold.values) {
          final ids = decoded[tree.name];
          if (ids is List) {
            _changed[tree] = ObservableSet.of(ids.whereType<String>());
          }
        }
      });
    } catch (_) {
      // Unreadable is the same as nothing folded.
    }
  }

  /// Forgets every fold, so the next account starts from the defaults.
  @action
  void forget() {
    _changed.clear();
    _save();
  }

  // The snapshot is taken after the await, so of two quick saves neither
  // can write an older state over a newer one.
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = {
        for (final MapEntry(:key, :value) in _changed.entries)
          key.name: value.toList(),
      };
      await prefs.setString(_key, jsonEncode(snapshot));
    } catch (_) {
      // Without storage the folds hold for this run only.
    }
  }
}
