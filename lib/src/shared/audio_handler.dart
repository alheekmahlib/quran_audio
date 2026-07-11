import 'dart:async';
import 'dart:developer' show log;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../engine/audio_engine.dart';
import '../enums/playback_mode.dart';

/// جسر إشعارات الوسائط — يربط أحداث just_audio بإشعارات النظام
/// (شاشة القفل، البلوتوث، سماعة السيارة).
///
/// System media notification bridge — connects just_audio events to the
/// system media notification (lock screen, Bluetooth, car audio).
///
/// يُفوِّض أزرار التحكم (next/prev/seek) للكنترولر النشط حالياً عبر ردود النداء.
class QuranAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  QuranAudioHandler._();
  static final QuranAudioHandler instance = QuranAudioHandler._();

  StreamSubscription<PlaybackEvent>? _eventSubscription;

  /// ردود النداء — يُعيّنها كل كنترولر ليُفوِّض التحكم.
  /// Callbacks — set by each controller to delegate controls.
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onStop;
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  /// هيّئ الجسر واربطه بأحداث المشغّل.
  /// Initialize the bridge and wire it to player events.
  void init(AudioPlayer player) {
    _eventSubscription?.cancel();
    _eventSubscription = player.playbackEventStream.listen(_broadcastState);
  }

  @override
  Future<void> play() async {
    if (AudioEngine.instance.activeMode == PlaybackMode.none) return;
    await onPlay?.call();
  }

  @override
  Future<void> pause() async {
    await onPause?.call();
  }

  @override
  Future<void> stop() async {
    await onStop?.call();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    await onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onSkipToPrevious?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    await AudioEngine.instance.player.seek(position);
  }

  /// بث حالة التشغيل لإشعارات النظام / Broadcast playback state to system.
  void _broadcastState(PlaybackEvent event) {
    final player = AudioEngine.instance.player;
    final playing = player.playing;
    final processingState = player.processingState;

    final state = PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[processingState]!,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
    );
    playbackState.add(state);
  }

  /// حرّر الموارد / Release resources.
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}

/// هيّئ خدمة الصوت بالنظام / Initialize the system audio service.
///
/// [androidChannelId] - معرّف قناة إشعارات أندرويد.
/// [androidChannelName] - اسم قناة الإشعارات.
Future<void> initQuranAudioService({
  String androidChannelId = 'com.quran_audio.playback',
  String androidChannelName = 'Quran Audio Playback',
}) async {
  try {
    await AudioService.init(
      builder: () => QuranAudioHandler.instance,
      config: AudioServiceConfig(
        androidNotificationChannelId: androidChannelId,
        androidNotificationChannelName: androidChannelName,
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    QuranAudioHandler.instance.init(AudioEngine.instance.player);
    log('QuranAudioService initialized', name: 'QuranAudioHandler');
  } catch (e, s) {
    log('Failed to init QuranAudioService: $e',
        name: 'QuranAudioHandler', stackTrace: s);
    rethrow;
  }
}
