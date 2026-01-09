import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

class ProximityService {
  static const int _threshold120m = 120;
  static const int _threshold80m = 80;
  static const int _threshold30m = 30;
  static const int _threshold10m = 10;
  static const int _threshold5m = 5;

  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentSelectedPlaceId;
  bool _isEnabled = true;

  final Map<String, Set<int>> _triggeredThresholds = {};

  Future<void> initialize() async {
    await _audioPlayer.setVolume(1.0);
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

    if (distanceMeters > _threshold120m) {
      resetProximityStateForDistance();
      return;
    }

    _triggeredThresholds.putIfAbsent(placeId, () => {});

    if (distanceMeters <= _threshold5m &&
        !_triggeredThresholds[placeId]!.contains(5)) {
      _triggeredThresholds[placeId]!.add(5);
      await _playSound('assets/sfx/ping_close.wav');
      await _vibrate(100, [0, 100, 100]);
    } else if (distanceMeters <= _threshold10m &&
        !_triggeredThresholds[placeId]!.contains(10)) {
      _triggeredThresholds[placeId]!.add(10);
      await _playSound('assets/sfx/ping.wav');
      await _vibrate(80, [0, 80, 80]);
    } else if (distanceMeters <= _threshold30m &&
        !_triggeredThresholds[placeId]!.contains(30)) {
      _triggeredThresholds[placeId]!.add(30);
      await _playSound('assets/sfx/ping.wav');
      await _vibrate(60, [0, 60, 60]);
    } else if (distanceMeters <= _threshold80m &&
        !_triggeredThresholds[placeId]!.contains(80)) {
      _triggeredThresholds[placeId]!.add(80);
      await _playSound('assets/sfx/ping.wav');
      await _vibrate(40, [0, 40, 40]);
    }
  }

  Future<void> _playSound(String assetPath) async {
    try {
      await _audioPlayer.play(AssetSource(assetPath));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  Future<void> _vibrate(
    int duration,
    List<int> pattern,
  ) async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(duration: duration, pattern: pattern);
      }
    } catch (e) {
      print('Error vibrating: $e');
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
