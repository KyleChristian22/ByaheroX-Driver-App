import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AppSoundService {
  AppSoundService._();

  static AudioPlayer? _player;
  static bool _isPlaying = false;

  static bool get isPlaying => _isPlaying;

  static Future<void> playOnboardNotification() async {
    if (_isPlaying) return;
    _isPlaying = true;
    _player = AudioPlayer();
    try {
      await _player!.play(
        AssetSource('audio/onboard_notification.mp3'),
        ctx: AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      _player!.onPlayerComplete.listen((_) {
        _isPlaying = false;
      });
    } catch (e) {
      debugPrint('AppSoundService: onboard sound playback failed: $e');
      _isPlaying = false;
      await _player?.dispose();
      _player = null;
    }
  }

  static Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
    _isPlaying = false;
  }
}
