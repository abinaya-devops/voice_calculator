import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plays calculator-style key sounds. Sounds are preloaded once and cached;
/// respects a persisted mute preference (speaker toggle in the app bar).
class KeySoundManager {
  KeySoundManager._();

  static final AudioPlayer _player = AudioPlayer();
  static const String _muteKey = 'soundsMuted';
  static bool _muted = false;
  static bool _loaded = false;
  static bool _loadedAssets = false;

  static Future<void> ensureLoaded() async {
    if (_loadedAssets) return;
    _loadedAssets = true;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setPlayerMode(PlayerMode.lowLatency);
      await _player.setVolume(0.9);
    } catch (_) {
      // Sound is best-effort; never break the calculation flow.
    }
  }

  static Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _muted = prefs.getBool(_muteKey) ?? false;
    await ensureLoaded();
  }

  static bool get muted => _muted;

  static Future<void> setMuted(bool value) async {
    _muted = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_muteKey, value);
  }

  /// Play the tap "tick" for a key press.
  static Future<void> tap() => _play('assets/sounds/key_press.wav');

  /// Play the "=" confirmation tone.
  static Future<void> confirm() => _play('assets/sounds/key_confirm.wav');

  /// Play the clear/AC sweep.
  static Future<void> clear() => _play('assets/sounds/key_clear.wav');

  static Future<void> _play(String asset) async {
    if (_muted) return;
    try {
      await ensureLoaded();
      await _player.stop();
      await _player.play(AssetSource(asset.substring('assets/'.length)));
    } catch (_) {
      // Never let sound break the calculation flow.
    }
  }
}
