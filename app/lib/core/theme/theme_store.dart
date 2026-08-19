import 'package:flutter/material.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_store.g.dart';

/// The user's chosen [ThemeMode], persisted across launches.
// ignore: library_private_types_in_public_api
class ThemeStore = _ThemeStore with _$ThemeStore;

abstract class _ThemeStore with Store {
  static const _key = 'theme_mode';

  @observable
  ThemeMode mode = ThemeMode.system;

  @action
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode = _decode(prefs.getString(_key));
  }

  @action
  Future<void> setMode(ThemeMode next) async {
    if (next == mode) return;
    mode = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(next));
  }

  static ThemeMode _decode(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
