import 'package:flutter/material.dart';

import '../services/preferences_service.dart';

class LocaleProvider extends ChangeNotifier {
  final PreferencesService _prefs = PreferencesService();

  Locale? _locale;
  bool _initialized = false;

  Locale? get locale => _locale;
  String get localeCode => _locale?.languageCode ?? 'system';

  Future<void> load() async {
    if (_initialized) return;
    await _prefs.init();
    _initialized = true;
    _locale = _mapCodeToLocale(_prefs.localeCode);
    notifyListeners();
  }

  Future<void> setLocaleCode(String code) async {
    if (!_initialized) {
      await load();
    }

    final normalized = code == 'system' ? null : code;
    _prefs.localeCode = normalized;
    _locale = _mapCodeToLocale(normalized);
    notifyListeners();
  }

  Locale? _mapCodeToLocale(String? code) {
    switch (code) {
      case 'en':
        return const Locale('en');
      case 'zh':
        return const Locale('zh');
      default:
        return null;
    }
  }
}
