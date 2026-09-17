import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ViewModel for managing app language/locale
class LanguageViewModel extends ChangeNotifier {
  static const String _localeKey = 'app_locale';
  
  Locale _currentLocale = const Locale('en', 'US');
  
  Locale get currentLocale => _currentLocale;
  
  bool get isEnglish => _currentLocale.languageCode == 'en';
  
  bool get isTagalog => _currentLocale.languageCode == 'tl';
  
  /// Available locales for the app
  static const List<Locale> supportedLocales = [
    Locale('en', 'US'),
    Locale('tl', 'PH'),
  ];
  
  /// Language names for display
  static const Map<String, String> languageNames = {
    'en': 'English',
    'tl': 'Tagalog',
  };
  
  LanguageViewModel() {
    _loadSavedLocale();
  }
  
  /// Load saved locale from preferences
  Future<void> _loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLocale = prefs.getString(_localeKey);
    
    if (savedLocale != null) {
      final parts = savedLocale.split('_');
      if (parts.length == 2) {
        _currentLocale = Locale(parts[0], parts[1]);
        notifyListeners();
      }
    }
  }
  
  /// Set locale to English
  Future<void> setEnglish() async {
    await _setLocale(const Locale('en', 'US'));
  }
  
  /// Set locale to Tagalog
  Future<void> setTagalog() async {
    await _setLocale(const Locale('tl', 'PH'));
  }
  
  /// Toggle between English and Tagalog
  Future<void> toggleLanguage() async {
    if (isEnglish) {
      await setTagalog();
    } else {
      await setEnglish();
    }
  }
  
  /// Set a specific locale
  Future<void> _setLocale(Locale locale) async {
    if (_currentLocale == locale) return;
    
    _currentLocale = locale;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, '${locale.languageCode}_${locale.countryCode}');
    
    notifyListeners();
  }
}
