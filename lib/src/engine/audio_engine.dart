import 'dart:async';
import 'dart:developer' show log;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:rxdart/rxdart.dart' as r;

import '../enums/playback_mode.dart';
import '../shared/models/position_data.dart';
import '../shared/platform_io.dart';

/// المحرك الصوتي المشترك — يملك نسخة `AudioPlayer` واحدة وينسّق بين نظامي السور والآيات.
///
/// Shared audio engine — owns a single `AudioPlayer` and coordinates between
/// the surah and ayah systems so only one plays at a time.
///
/// عند طلب نظامٍ التحكم (`takeControl`)، يُوقف النظام الآخر أولاً لمنع التعارض.
class AudioEngine {
  AudioEngine._();
  static final AudioEngine instance = AudioEngine._();

  /// المشغّل الصوتي الوحيد المشترك بين النظامين.
  /// The single shared audio player.
  late final AudioPlayer player = AudioPlayer();

  /// النمط النشط حالياً (أي نظام يتحكم بالمشغل).
  /// The currently active playback mode.
  PlaybackMode _activeMode = PlaybackMode.none;
  PlaybackMode get activeMode => _activeMode;

  /// قائمة المستمعين الذين يُبلَّغون عند فقدان نظامٍ للسيطرة على المشغل.
  /// يُسجّل كل كنترولر مستمعاً يُصفّي حسب النمط السابق.
  ///
  /// Listeners notified when a system loses control of the player. Each
  /// controller registers a listener that filters by the previous mode.
  final List<void Function(PlaybackMode previousMode)> _controlListeners = [];

  /// سجّل مستمعاً لفقدان السيطرة / Register a control-lost listener.
  void addControlLostListener(void Function(PlaybackMode previousMode) fn) {
    _controlListeners.add(fn);
  }

  /// ألغِ تسجيل مستمع / Unregister a control-lost listener.
  void removeControlLostListener(void Function(PlaybackMode previousMode) fn) {
    _controlListeners.remove(fn);
  }

  /// الاشتراكات النشطة (يديرها كل كنترولر بنفسه، لكن المحرك يوفّر المرجع المشترك).
  StreamSubscription<PlayerState>? playerStateSubscription;
  StreamSubscription<dynamic>? currentIndexSubscription;
  StreamSubscription<Duration>? positionSubscription;

  bool _initialized = false;

  /// هل تمت تهيئة المحرك؟ / Has the engine been initialized?
  bool get isInitialized => _initialized;

  /// هيّئ المشغّل (يُستدعى مرة واحدة من الكنترولر الأول).
  /// Initialize the player (called once by the first controller).
  ///
  /// على Windows/Linux، يُهيّئ media_kit كـ backend لـ just_audio قبل إنشاء
  /// أي AudioPlayer (مطلوب صراحةً في الإصدار 2.1.0). macOS يستخدم backend
  /// AVAudioPlayer النظامي لـ just_audio مباشرةً (لا يحتاج media_kit).
  /// على الويب، يستخدم just_audio backend الويب الخاص به.
  ///
  /// On Windows/Linux, initializes media_kit as the just_audio backend before
  /// any AudioPlayer is constructed (required explicitly in v2.1.0). macOS uses
  /// just_audio's native AVAudioPlayer backend directly (no media_kit needed).
  /// On web, just_audio uses its own web backend.
  Future<void> init() async {
    if (_initialized) return;
    if (!kIsWeb && (PlatformIo.isWindows || PlatformIo.isLinux)) {
      try {
        JustAudioMediaKit.ensureInitialized(
          windows: PlatformIo.isWindows,
          linux: PlatformIo.isLinux,
        );
        log('media_kit backend initialized '
            '(windows=${PlatformIo.isWindows}, linux=${PlatformIo.isLinux})',
            name: 'AudioEngine');
      } catch (e, s) {
        log('Failed to init media_kit backend: $e',
            name: 'AudioEngine', stackTrace: s);
      }
    }
    _initialized = true;
    log('AudioEngine initialized', name: 'AudioEngine');
  }

  /// اطلب التحكم بالمشغل — يُوقف النظام السابق أولاً.
  ///
  /// Request control of the player — stops the previous system first.
  Future<void> takeControl(PlaybackMode mode) async {
    if (_activeMode == mode) return; // نفس النظام لا شيء للتغيير

    final previous = _activeMode;

    // أوقف المشغل مباشرة كإجراء أمان
    try {
      await player.stop();
    } catch (_) {}

    cancelAllSubscriptions();
    _activeMode = mode;

    // أبلغ المستمعين بفقدان السيطرة / notify listeners of control loss
    if (previous != PlaybackMode.none) {
      for (final fn in _controlListeners) {
        try {
          fn(previous);
        } catch (e, s) {
          log('control-lost listener failed: $e',
              name: 'AudioEngine', stackTrace: s);
        }
      }
    }

    log('AudioEngine control taken by: $mode (was $previous)',
        name: 'AudioEngine');
  }

  /// ألغِ كل الاشتراكات النشطة / Cancel all active subscriptions.
  void cancelAllSubscriptions() {
    playerStateSubscription?.cancel();
    currentIndexSubscription?.cancel();
    positionSubscription?.cancel();
    playerStateSubscription = null;
    currentIndexSubscription = null;
    positionSubscription = null;
  }

  /// أوقف كل شيء / Stop everything.
  Future<void> stopAll() async {
    cancelAllSubscriptions();
    try {
      await player.stop();
    } catch (_) {}
    _activeMode = PlaybackMode.none;
  }

  // ============ Streams للـ UI الخارجي ============

  /// تدفق حالة المشغل / Player state stream.
  Stream<PlayerState> get playerStateStream => player.playerStateStream;

  /// تدفق الموضع / Position stream.
  Stream<Duration> get positionStream => player.positionStream;

  /// تدفق الموضع المؤقت / Buffered position stream.
  Stream<Duration> get bufferedPositionStream => player.bufferedPositionStream;

  /// تدفق المدة الكلية / Duration stream.
  Stream<Duration?> get durationStream => player.durationStream;

  /// تدفق حالة التسلسل (للـ playlist) / Sequence state stream (for playlists).
  Stream<SequenceState?> get sequenceStateStream => player.sequenceStateStream;

  /// تدفق الموضع المدمج (position + buffered + duration) — للـ seek bar.
  Stream<PositionData> get positionDataStream =>
      r.Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        player.positionStream,
        player.bufferedPositionStream,
        player.durationStream,
        (position, buffered, duration) =>
            PositionData(position, buffered, duration ?? Duration.zero),
      );

  /// حرّر الموارد / Release resources.
  void dispose() {
    cancelAllSubscriptions();
    player.dispose();
    _initialized = false;
    _activeMode = PlaybackMode.none;
  }
}
