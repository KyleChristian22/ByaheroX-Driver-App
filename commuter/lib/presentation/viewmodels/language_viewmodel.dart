import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';

/// Supported languages
enum AppLanguage {
  english,
  tagalog,
}

/// ViewModel for managing app language/locale
class LanguageViewModel extends ChangeNotifier {
  static const String _languageKey = 'app_language';

  Locale _currentLocale = const Locale('en');
  AppLanguage _currentLanguage = AppLanguage.english;

  LanguageViewModel() {
    _loadSavedLanguage();
  }

  /// Get current locale
  Locale get currentLocale => _currentLocale;

  /// Get current language enum
  AppLanguage get currentLanguage => _currentLanguage;

  /// Get language display name
  String get languageDisplayName {
    switch (_currentLanguage) {
      case AppLanguage.english:
        return 'English';
      case AppLanguage.tagalog:
        return 'Tagalog';
    }
  }

  /// Get language code
  String get languageCode => _currentLocale.languageCode;

  /// Check if current language is English
  bool get isEnglish => _currentLanguage == AppLanguage.english;

  /// Check if current language is Tagalog
  bool get isTagalog => _currentLanguage == AppLanguage.tagalog;

  /// Load saved language preference
  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(_languageKey);
    
    if (savedLanguage != null) {
      if (savedLanguage == 'fil') {
        _currentLocale = const Locale('fil');
        _currentLanguage = AppLanguage.tagalog;
      } else {
        _currentLocale = const Locale('en');
        _currentLanguage = AppLanguage.english;
      }
      notifyListeners();
    }
  }

  /// Set language to English
  Future<void> setEnglish() async {
    await _setLanguage(const Locale('en'), AppLanguage.english);
  }

  /// Set language to Tagalog
  Future<void> setTagalog() async {
    await _setLanguage(const Locale('fil'), AppLanguage.tagalog);
  }

  /// Toggle between English and Tagalog
  Future<void> toggleLanguage() async {
    if (_currentLanguage == AppLanguage.english) {
      await setTagalog();
    } else {
      await setEnglish();
    }
  }

  /// Set specific language
  Future<void> _setLanguage(Locale locale, AppLanguage language) async {
    if (_currentLocale == locale) return;

    _currentLocale = locale;
    _currentLanguage = language;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, locale.languageCode);

    notifyListeners();
  }

  /// Get AppLocalizations for the current context
  AppLocalizations localizations(BuildContext context) {
    return AppLocalizations.of(context);
  }

  /// Supported locales
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('fil'),
  ];
}
