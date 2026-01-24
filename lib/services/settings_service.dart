import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _backgroundSoundsKey = 'background_sounds_enabled';

  Future<void> setBackgroundSoundsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundSoundsKey, enabled);
  }

  Future<bool> isBackgroundSoundsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_backgroundSoundsKey) ?? false;
  }
}
