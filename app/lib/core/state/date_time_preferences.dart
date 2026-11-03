import 'package:flutter/widgets.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// How a date is written.
enum DateStyle {
  automatic,
  dayMonthYearDots,
  dayMonthYearSlashes,
  monthDayYear,
  yearMonthDay,
}

/// Whether a time of day reads "14:05" or "2:05 PM".
enum ClockStyle { automatic, hours24, hours12 }

/// How dates, times and the time zone are shown, kept on the device.
///
/// Each one starts as automatic: the date style and clock follow the device's
/// region, and the time zone is the device's own, so a phone set to Germany
/// shows German dates in German time without anyone choosing it.
abstract final class DateTimePreferences {
  static const _dateStyleKey = 'date_style';
  static const _clockStyleKey = 'clock_style';
  static const _timeZoneKey = 'time_zone';

  static final Observable<DateStyle> _dateStyle = Observable(
    DateStyle.automatic,
  );
  static final Observable<ClockStyle> _clockStyle = Observable(
    ClockStyle.automatic,
  );
  static final Observable<tz.Location?> _timeZone = Observable(null);

  static DateStyle get dateStyle => _dateStyle.value;
  static ClockStyle get clockStyle => _clockStyle.value;

  /// The chosen zone, or null to use the device's.
  static tz.Location? get timeZone => _timeZone.value;

  /// The date style the device's region expects.
  static DateStyle get automaticDateStyle => dateStyleFor(_deviceLocale);

  /// [dateStyle] with automatic resolved against the device's region.
  static DateStyle get effectiveDateStyle =>
      dateStyle == DateStyle.automatic ? automaticDateStyle : dateStyle;

  /// [clockStyle] with automatic resolved against the device's region.
  static ClockStyle get effectiveClockStyle =>
      clockStyle == ClockStyle.automatic
      ? clockStyleFor(_deviceLocale)
      : clockStyle;

  /// Every zone that can be chosen, by its region and city name.
  static List<String> get timeZoneNames {
    _ensureZones();
    const regions = {
      'Africa',
      'America',
      'Antarctica',
      'Asia',
      'Atlantic',
      'Australia',
      'Europe',
      'Indian',
      'Pacific',
    };
    return [
      'UTC',
      ...tz.timeZoneDatabase.locations.keys.where(
        (name) => regions.contains(name.split('/').first),
      ),
    ]..sort();
  }

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final zone = _zone(prefs.getString(_timeZoneKey));
      runInAction(() {
        _dateStyle.value = _decode(
          DateStyle.values,
          prefs.getString(_dateStyleKey),
          DateStyle.automatic,
        );
        _clockStyle.value = _decode(
          ClockStyle.values,
          prefs.getString(_clockStyleKey),
          ClockStyle.automatic,
        );
        _timeZone.value = zone;
      });
    } catch (_) {
      // Unreadable is the same as nothing chosen.
    }
  }

  static Future<void> setDateStyle(DateStyle style) async {
    runInAction(() => _dateStyle.value = style);
    await _write((p) => p.setString(_dateStyleKey, style.name));
  }

  static Future<void> setClockStyle(ClockStyle style) async {
    runInAction(() => _clockStyle.value = style);
    await _write((p) => p.setString(_clockStyleKey, style.name));
  }

  /// Null goes back to the device's zone.
  static Future<void> setTimeZone(String? name) async {
    final zone = _zone(name);
    runInAction(() => _timeZone.value = zone);
    await _write(
      (p) => zone == null
          ? p.remove(_timeZoneKey)
          : p.setString(_timeZoneKey, zone.name),
    );
  }

  /// The date style people in [locale]'s region expect.
  static DateStyle dateStyleFor(Locale locale) {
    final country = locale.countryCode?.toUpperCase();
    if (country != null && country.isNotEmpty) {
      if (_monthFirstCountries.contains(country)) return DateStyle.monthDayYear;
      if (_yearFirstCountries.contains(country)) return DateStyle.yearMonthDay;
      if (_dottedCountries.contains(country)) {
        return DateStyle.dayMonthYearDots;
      }
      return DateStyle.dayMonthYearSlashes;
    }
    final language = locale.languageCode.toLowerCase();
    if (language == 'en') return DateStyle.monthDayYear;
    if (_yearFirstLanguages.contains(language)) return DateStyle.yearMonthDay;
    if (_dottedLanguages.contains(language)) return DateStyle.dayMonthYearDots;
    return DateStyle.dayMonthYearSlashes;
  }

  /// The clock people in [locale]'s region expect.
  static ClockStyle clockStyleFor(Locale locale) {
    final country = locale.countryCode?.toUpperCase();
    if (country != null && country.isNotEmpty) {
      return _twelveHourCountries.contains(country)
          ? ClockStyle.hours12
          : ClockStyle.hours24;
    }
    return locale.languageCode.toLowerCase() == 'en'
        ? ClockStyle.hours12
        : ClockStyle.hours24;
  }

  static const _monthFirstCountries = {'US', 'PH', 'PR', 'GU', 'AS', 'UM'};
  static const _yearFirstCountries = {
    'CN',
    'JP',
    'KR',
    'TW',
    'HU',
    'SE',
    'LT',
    'MN',
    'CA',
  };
  static const _dottedCountries = {
    'DE',
    'AT',
    'CH',
    'LI',
    'LU',
    'PL',
    'CZ',
    'SK',
    'RU',
    'UA',
    'BY',
    'NO',
    'FI',
    'DK',
    'EE',
    'LV',
    'TR',
    'RS',
    'HR',
    'SI',
    'BA',
    'ME',
    'MK',
    'BG',
    'RO',
    'AZ',
    'KZ',
    'GE',
    'AM',
    'IS',
  };
  static const _yearFirstLanguages = {'zh', 'ja', 'ko', 'hu', 'sv', 'lt'};
  static const _dottedLanguages = {
    'de',
    'pl',
    'cs',
    'sk',
    'ru',
    'uk',
    'be',
    'nb',
    'nn',
    'no',
    'fi',
    'da',
    'et',
    'lv',
    'tr',
    'sr',
    'hr',
    'sl',
    'bs',
    'mk',
    'bg',
    'ro',
    'is',
  };
  static const _twelveHourCountries = {
    'US',
    'CA',
    'AU',
    'NZ',
    'IN',
    'PK',
    'BD',
    'PH',
    'EG',
    'SA',
    'JO',
    'MX',
    'CO',
    'PR',
    'GU',
  };

  static Locale get _deviceLocale =>
      WidgetsBinding.instance.platformDispatcher.locale;

  static var _zonesLoaded = false;

  static void _ensureZones() {
    if (_zonesLoaded) return;
    tzdata.initializeTimeZones();
    _zonesLoaded = true;
  }

  static tz.Location? _zone(String? name) {
    if (name == null || name.isEmpty) return null;
    _ensureZones();
    try {
      return tz.getLocation(name);
    } catch (_) {
      return null;
    }
  }

  static T _decode<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
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
