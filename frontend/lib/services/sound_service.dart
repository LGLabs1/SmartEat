import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Set audio player configuration for web
      if (kIsWeb) {
        await _audioPlayer.setPlayerMode(PlayerMode.lowLatency);
      }
      _initialized = true;
    } catch (e) {}
  }

  /// Play a success sound when order is completed
  static Future<void> playOrderCompleted() async {
    try {
      if (!_initialized) {
        await initialize();
      }

      // Use a short beep sound for web compatibility
      // For web, we use a data URI with a simple beep sound
      if (kIsWeb) {
        // Simple success beep using AudioCache with a short sound
        await _audioPlayer.play(
          AssetSource('sounds/success.mp3'),
          volume: 0.7,
        );
      } else {
        // For mobile, play from assets
        await _audioPlayer.play(
          AssetSource('sounds/success.mp3'),
          volume: 0.7,
        );
      }
    } catch (e) {}
  }

  /// Play a notification sound
  static Future<void> playNotification() async {
    try {
      if (!_initialized) {
        await initialize();
      }

      await _audioPlayer.play(
        AssetSource('sounds/notification.mp3'),
        volume: 0.5,
      );
    } catch (e) {}
  }

  /// Play an error sound
  static Future<void> playError() async {
    try {
      if (!_initialized) {
        await initialize();
      }

      await _audioPlayer.play(
        AssetSource('sounds/error.mp3'),
        volume: 0.5,
      );
    } catch (e) {}
  }

  /// Dispose the audio player
  static Future<void> dispose() async {
    await _audioPlayer.dispose();
    _initialized = false;
  }
}
