import 'package:flutter/material.dart';

/// Manages the app's ThemeMode, driven by the user's profile preference.
class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;

  ThemeMode get mode => _mode;
  bool get isLight => _mode == ThemeMode.light;

  void setLight(bool light) {
    _mode = light ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void toggle() {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}
