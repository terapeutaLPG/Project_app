import 'package:vibration/vibration.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class ProximityService {
  static const int _threshold300m = 300;
  static const int _threshold200m = 200;
  static const int _threshold100m = 100;

  String? _currentSelectedPlaceId;
  bool _isEnabled = true;

  final Map<String, Set<int>> _triggeredThresholds = {};

  Future<void> initialize() async {
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  bool getIsEnabled() => _isEnabled;

  void resetProximityState(String placeId) {
    _currentSelectedPlaceId = placeId;
    if (!_triggeredThresholds.containsKey(placeId)) {
      _triggeredThresholds[placeId] = {};
    } else {
      _triggeredThresholds[placeId]!.clear();
    }
  }

  void resetProximityStateForDistance() {
    if (_currentSelectedPlaceId != null && _triggeredThresholds.containsKey(_currentSelectedPlaceId)) {
      _triggeredThresholds[_currentSelectedPlaceId]!.clear();
    }
  }

  Future<void> checkProximityAndTrigger(
    double distanceMeters,
    String placeId,
  ) async {
    if (!_isEnabled || _currentSelectedPlaceId == null || _currentSelectedPlaceId != placeId) {
      return;
    }

    if (distanceMeters > _threshold300m) {
      resetProximityStateForDistance();
      return;
    }

    _triggeredThresholds.putIfAbsent(placeId, () => {});

    if (distanceMeters <= _threshold100m &&
        !_triggeredThresholds[placeId]!.contains(100)) {
      _triggeredThresholds[placeId]!.add(100);
      await _playSystemSound(AndroidSounds.notification, IosSounds.triTone);
      await _vibrate(200);
    } else if (distanceMeters <= _threshold200m &&
        !_triggeredThresholds[placeId]!.contains(200)) {
      _triggeredThresholds[placeId]!.add(200);
      await _playSystemSound(AndroidSounds.alarm, IosSounds.glass);
      await _vibrate(150);
    } else if (distanceMeters <= _threshold300m &&
        !_triggeredThresholds[placeId]!.contains(300)) {
      _triggeredThresholds[placeId]!.add(300);
      await _playSystemSound(AndroidSounds.ringtone, IosSounds.electronic);
      await _vibrate(100);
    }
  }

  Future<void> _playSystemSound(AndroidSound android, IosSound ios) async {
    try {
      FlutterRingtonePlayer().play(
        android: android,
        ios: ios,
        looping: false,
        volume: 1.0,
      );
    } catch (e) {
      print('Error playing system sound: $e');
    }
  }

  Future<void> _vibrate(int duration) async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(duration: duration);
      }
    } catch (e) {
      print('Error vibrating: $e');
    }
  }

  void dispose() {
  }
}
