import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class ProximityService {
  static const int _threshold300m = 300;
  static const int _threshold200m = 200;
  static const int _threshold100m = 100;

  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentSelectedPlaceId;
  bool _isEnabled = true;

  final Map<String, Set<int>> _triggeredThresholds = {};

  Future<void> initialize() async {
    await _audioPlayer.setVolume(1.0);
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
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
      await _playSystemSound(AndroidSoundIDs.notification);
      await _vibrate(200);
    } else if (distanceMeters <= _threshold200m &&
        !_triggeredThresholds[placeId]!.contains(200)) {
      _triggeredThresholds[placeId]!.add(200);
      await _playSystemSound(AndroidSoundIDs.alarm);
      await _vibrate(150);
    } else if (distanceMeters <= _threshold300m &&
        !_triggeredThresholds[placeId]!.contains(300)) {
      _triggeredThresholds[placeId]!.add(300);
      await _playSystemSound(AndroidSoundIDs.ringtone);
      await _vibrate(100);
    }
  }

  Future<void> _playSystemSound(int soundId) async {
    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.glass,
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
    _audioPlayer.dispose();
  }
}

class AndroidSoundIDs {
  static const int notification = 1;
  static const int alarm = 2;
  static const int ringtone = 3;
}
