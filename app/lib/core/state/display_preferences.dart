import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How much a screen says about each thing.
enum DetailLevel {
  /// One plain sentence: who can see what, and that it can be stopped.
  essentials,

  /// Everything as well: slugs, fingerprints, DNS verdicts, formats, counts.
  full,
}

/// Display preferences that are not the theme, kept on the device.
///
/// Observable, so every `DetailGate` and the app's text size and motion
/// follow a change at once.
abstract final class DisplayPreferences {
  static const _detailKey = 'detail_level';
  static const _textScaleKey = 'text_scale';
  static const _reduceMotionKey = 'reduce_motion';

  /// The in-app text sizes offered, on top of the system's own setting.
  static const textScales = [1.0, 1.25, 1.5, 1.75, 2.0];

  static final Observable<DetailLevel> _detail = Observable(
    DetailLevel.essentials,
  );
  static final Observable<double> _textScale = Observable(1.0);
  static final Observable<bool> _reduceMotion = Observable(false);

  static DetailLevel get detailLevel => _detail.value;

  /// Multiplies the system's text size. 1.0 leaves it as the system has it.
  static double get textScale => _textScale.value;

  /// Turns animation off even when the system has not asked for that. Off
  /// means "as the system says", never "animate regardless".
  static bool get reduceMotion => _reduceMotion.value;

  /// Reads what an earlier run chose. Called once at startup.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final detail = prefs.getString(_detailKey);
      final scale = prefs.getDouble(_textScaleKey);
      runInAction(() {
        _detail.value = DetailLevel.values.firstWhere(
          (l) => l.name == detail,
          orElse: () => DetailLevel.essentials,
        );
        _textScale.value = textScales.contains(scale) ? scale! : 1.0;
        _reduceMotion.value = prefs.getBool(_reduceMotionKey) ?? false;
      });
    } catch (_) {
      // Unreadable is the same as nothing chosen.
    }
  }

  static Future<void> setDetailLevel(DetailLevel level) async {
    runInAction(() => _detail.value = level);
    await _write((p) => p.setString(_detailKey, level.name));
  }

  static Future<void> setTextScale(double scale) async {
    final next = textScales.contains(scale) ? scale : 1.0;
    runInAction(() => _textScale.value = next);
    await _write((p) => p.setDouble(_textScaleKey, next));
  }

  static Future<void> setReduceMotion(bool reduce) async {
    runInAction(() => _reduceMotion.value = reduce);
    await _write((p) => p.setBool(_reduceMotionKey, reduce));
  }

  static Future<void> _write(
    Future<bool> Function(SharedPreferences prefs) write,
  ) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {
      // Without storage it holds for this run only.
    }
  }
}
