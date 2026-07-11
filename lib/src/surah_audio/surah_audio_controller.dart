import 'dart:async';
import 'dart:developer' show log;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:just_audio/just_audio.dart';

import '../constants/quran_constants.dart';
import '../constants/storage_keys.dart';
import '../engine/audio_engine.dart';
import '../enums/playback_mode.dart';
import '../enums/repeat_mode.dart';
import '../shared/audio_handler.dart';
import '../shared/download_service.dart';
import '../shared/media_item_builder.dart';
import '../shared/models/reader_info.dart';
import '../shared/models/position_data.dart';
import '../shared/platform_io.dart';
import '../shared/quran_metadata.dart';
import '../shared/repeat_controller.dart';
import 'surah_readers.dart';
import 'surah_url_builder.dart';

/// متحكّم تشغيل السور - يدير تشغيل السور الكاملة (ملف MP3 واحد لكل سورة).
///
/// Surah playback controller — manages full-surah playback (one MP3 per surah).
///
/// لكل سورة قارئون مستقلون (21 قارئ افتراضياً)، وروابط مستقلة عن نظام الآيات.
/// Each surah has its own readers (21 by default) and URLs independent of the
/// ayah system.
class SurahAudioController extends GetxController {
  SurahAudioController();

  static SurahAudioController? _instance;
  static SurahAudioController get instance {
    _instance ??= SurahAudioController();
    if (!Get.isRegistered<SurahAudioController>()) {
      Get.put(_instance!, permanent: true);
    }
    return _instance!;
  }

  final AudioEngine _engine = AudioEngine.instance;
  final DownloadService _downloadService = DownloadService();
  final RepeatController _repeat = RepeatController();
  final GetStorage _box = GetStorage();

  // ============ الحالة Reactive / Reactive state ============

  /// هل التشغيل جارٍ؟ / Is playback active?
  final RxBool isPlaying = false.obs;

  /// هل يجري التحضير؟ / Is preparing?
  final RxBool isPreparing = false.obs;

  /// هل التحميل جارٍ؟ / Is download in progress?
  RxBool get isDownloading => _downloadService.isDownloading;

  /// نسبة التحميل / Download progress.
  RxDouble get downloadProgress => _downloadService.progress;

  /// رقم السورة الحالية / Current surah number.
  final RxInt currentSurahNumber = 1.obs;

  /// فهرس القارئ الحالي / Current reader index.
  final RxInt readerIndex = 0.obs;

  /// آخر موضع استماع (بالثواني) / Last playback position (seconds).
  final RxInt lastPosition = 0.obs;

  /// حجم خطوة التقديم (ثواني) / Seek step size (seconds).
  final RxInt seekStep = 5.obs;

  /// نمط التكرار الحالي / Current repeat mode.
  Rx<RepeatMode> get repeatMode => _repeat.mode.obs;

  // ============ متغيرات داخلية / Internal ============

  /// مجلد التخزين المحلي / Local storage directory.
  String? _docsDir;

  /// القارئ الحالي / Current reader.
  ReaderInfo get currentReader => SurahReaders.active[readerIndex.value];

  /// قائمة القرّاء / Readers list.
  List<ReaderInfo> get readers => SurahReaders.active;

  /// هل النظام هو النشط حالياً؟ / Is this the active system?
  bool get isActive => _engine.activeMode == PlaybackMode.surah;

  /// تدفق الموضع المدمج / Combined position stream.
  Stream<PositionData> get positionDataStream => _engine.positionDataStream;

  // ============ التهيئة / Initialization ============

  /// هيّئ الكنترولر (يُستدعى مرة بعد GetStorage.init).
  ///
  /// Initialize the controller (call once after GetStorage.init).
  Future<void> init() async {
    await QuranMetadata.instance.load();
    await _engine.init();

    // حمّل القارئ والموضع الأخير / load reader & last position
    readerIndex.value = _box.read(StorageKeys.surahReaderIndex) ?? 0;
    _loadLastListen();

    if (!kIsWeb) {
      _docsDir = await PlatformIo.documentsDir;
    }

    // سجّل callbacks جسر الإشعارات / register notification handler callbacks
    _registerAudioHandlerCallbacks();

    // عند استيلاء نظام الآيات على المشغل، أوقف حالة التشغيل لدينا
    // When the ayah system takes over, reset our playing state.
    _engine.addControlLostListener((previousMode) {
      if (previousMode == PlaybackMode.surah) {
        isPlaying.value = false;
        _disablePositionSaving();
        _disableAutoNextListener();
      }
    });

    log('SurahAudioController initialized. Last surah: ${currentSurahNumber.value}',
        name: 'SurahAudioController');
  }

  void _registerAudioHandlerCallbacks() {
    final handler = QuranAudioHandler.instance;
    handler.onPlay = () async {
      if (isActive) await resume();
    };
    handler.onPause = () async {
      if (isActive) await pause();
    };
    handler.onStop = () async {
      if (isActive) await stop();
    };
    handler.onSkipToNext = () async {
      if (isActive) await playNextSurah();
    };
    handler.onSkipToPrevious = () async {
      if (isActive) await playPreviousSurah();
    };
  }

  // ============ التشغيل / Playback ============

  /// شغّل سورة كاملة / Play a full surah.
  ///
  /// [surahNumber] - رقم السورة (1..114).
  Future<void> playSurah({required int surahNumber}) async {
    if (!QuranMetadata.instance.isValidSurah(surahNumber)) {
      log('Invalid surah number: $surahNumber', name: 'SurahAudioController');
      return;
    }

    // استولِ على المشغّل (يوقف نظام الآيات إن كان نشطاً)
    await _engine.takeControl(PlaybackMode.surah);

    isPreparing.value = true;
    currentSurahNumber.value = surahNumber;

    try {
      await _setAudioSource(surahNumber);
      _enableAutoNextListener();
      _enablePositionSaving();
      isPlaying.value = true;
      isPreparing.value = false;
      await _engine.player.play();
      _updateMediaItem();
      _saveLastSurah(surahNumber);
    } catch (e, s) {
      isPreparing.value = false;
      isPlaying.value = false;
      log('playSurah($surahNumber) failed: $e',
          name: 'SurahAudioController', stackTrace: s);
    }
  }

  /// استئناف التشغيل / Resume playback.
  Future<void> resume() async {
    if (!isActive) return;
    isPlaying.value = true;
    _enableAutoNextListener();
    _enablePositionSaving();
    await _engine.player.play();
  }

  /// إيقاف مؤقت / Pause.
  Future<void> pause() async {
    if (!isActive) return;
    isPlaying.value = false;
    _disablePositionSaving();
    _disableAutoNextListener();
    await _engine.player.pause();
  }

  /// إيقاف كامل / Stop.
  Future<void> stop() async {
    isPlaying.value = false;
    _disablePositionSaving();
    _disableAutoNextListener();
    await _engine.player.stop();
  }

  /// تقديم/تأخير / Seek to position.
  Future<void> seek(Duration position) async {
    await _engine.player.seek(position);
  }

  /// تقديم للأمام بثواني / Fast forward by seconds.
  Future<void> seekForward([int? seconds]) async {
    final step = seconds ?? seekStep.value;
    final newPos = _engine.player.position + Duration(seconds: step);
    final dur = _engine.player.duration ?? Duration.zero;
    await seek(newPos > dur ? dur : newPos);
  }

  /// تأخير للخلف بثواني / Rewind by seconds.
  Future<void> seekBackward([int? seconds]) async {
    final step = seconds ?? seekStep.value;
    final newPos = _engine.player.position - Duration(seconds: step);
    await seek(newPos.isNegative ? Duration.zero : newPos);
  }

  /// شغّل السورة التالية / Play next surah (stops at 114).
  Future<void> playNextSurah() async {
    final next = currentSurahNumber.value + 1;
    if (next > QuranConstants.lastSurah) {
      await stop();
      return;
    }
    await playSurah(surahNumber: next);
  }

  /// شغّل السورة السابقة / Play previous surah (stops at 1).
  Future<void> playPreviousSurah() async {
    final prev = currentSurahNumber.value - 1;
    if (prev < QuranConstants.firstSurah) {
      await stop();
      return;
    }
    await playSurah(surahNumber: prev);
  }

  // ============ تعيين مصدر الصوت / Set audio source ============

  Future<void> _setAudioSource(int surahNumber) async {
    await _engine.player.stop();
    final reader = currentReader;

    if (kIsWeb) {
      // ويب: بث مباشر دائماً / web: always stream
      final url = SurahUrlBuilder.url(surahNumber: surahNumber, reader: reader);
      await _engine.player.setAudioSource(
        AudioSource.uri(Uri.parse(url), tag: _mediaItem(surahNumber)),
      );
      return;
    }

    // محلي: تحقق من الملف، حمّل إن لزم / local: check file, download if needed
    final localPath = SurahUrlBuilder.localPath(
      docsDir: _docsDir!,
      surahNumber: surahNumber,
      reader: reader,
    );

    if (await PlatformIo.fileExists(localPath)) {
      await _engine.player.setAudioSource(
        AudioSource.file(localPath, tag: _mediaItem(surahNumber)),
      );
    } else {
      final url = SurahUrlBuilder.url(surahNumber: surahNumber, reader: reader);
      await _engine.player.setAudioSource(
        AudioSource.uri(Uri.parse(url), tag: _mediaItem(surahNumber)),
      );
    }
  }

  MediaItem _mediaItem(int surahNumber) {
    return MediaItemBuilder.surahItem(
      surahNumber: surahNumber,
      reader: currentReader,
    );
  }

  void _updateMediaItem() {
    final item = _mediaItem(currentSurahNumber.value);
    QuranAudioHandler.instance.mediaItem.add(item);
  }

  /// أعد بناء وبثّ الـ MediaItem الحالي (لتحديث الأيقونة أثناء التشغيل).
  ///
  /// Rebuild and broadcast the current MediaItem (to refresh the icon during playback).
  void refreshMediaItem() => _updateMediaItem();

  // ============ الانتقال التلقائي للسورة التالية / Auto-next ============

  /// منع إعادة الإدخال / re-entrancy guard.
  bool _autoNextInProgress = false;
  double? _lastCompletionTime;

  void _enableAutoNextListener() {
    _engine.playerStateSubscription?.cancel();
    _engine.playerStateSubscription =
        _engine.player.playerStateStream.listen((state) async {
      if (state.processingState != ProcessingState.completed) return;
      if (!isActive) return;
      if (_autoNextInProgress) return;

      _autoNextInProgress = true;
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final last = _lastCompletionTime ?? 0.0;
      // debounce لمنع التفعيل المزدوج
      if ((now - last) < 1.0) {
        _autoNextInProgress = false;
        return;
      }
      _lastCompletionTime = now;

      try {
        await _engine.player.stop();

        // تحقّق من نمط التكرار / check repeat mode
        final action = _repeat.onCompleted(
          currentSurah: currentSurahNumber.value,
          currentAyah: 0, // لا يهم في نظام السور
        );

        switch (action) {
          case RepeatActionReplaySurah():
            await _engine.player.seek(Duration.zero);
            await _engine.player.play();
            break;
          case RepeatActionStop():
            isPlaying.value = false;
            break;
          case RepeatActionProceedNext():
            await playNextSurah();
            break;
          default:
            await playNextSurah();
        }
      } catch (e, s) {
        log('Auto-next failed: $e', name: 'SurahAudioController',
            stackTrace: s);
      } finally {
        _autoNextInProgress = false;
      }
    });
  }

  void _disableAutoNextListener() {
    _engine.playerStateSubscription?.cancel();
    _engine.playerStateSubscription = null;
  }

  // ============ حفظ الموضع / Position saving ============

  void _enablePositionSaving() {
    _engine.positionSubscription?.cancel();
    DateTime? lastSaveTime;
    int? lastSavedPosition;

    _engine.positionSubscription =
        _engine.player.positionStream.listen((position) {
      final posSeconds = position.inSeconds;
      lastPosition.value = posSeconds;

      final now = DateTime.now();
      final shouldSave = lastSaveTime == null ||
          now.difference(lastSaveTime!).inSeconds >= 3 ||
          (lastSavedPosition != null &&
              (posSeconds - lastSavedPosition!).abs() >= 5);

      if (shouldSave) {
        _box.write(StorageKeys.lastPosition, posSeconds);
        lastSavedPosition = posSeconds;
        lastSaveTime = now;
        _saveLastSurah(currentSurahNumber.value);
      }
    });
  }

  void _disablePositionSaving() {
    if (lastPosition.value > 0) {
      _box.write(StorageKeys.lastPosition, lastPosition.value);
      _saveLastSurah(currentSurahNumber.value);
    }
    _engine.positionSubscription?.cancel();
    _engine.positionSubscription = null;
  }

  void _loadLastListen() {
    final lastSurah = _box.read(StorageKeys.lastSurah) ?? 1;
    final lastPos = _box.read(StorageKeys.lastPosition) ?? 0;
    currentSurahNumber.value = lastSurah;
    lastPosition.value = lastPos;
  }

  void _saveLastSurah(int surahNumber) {
    _box.write(StorageKeys.lastSurah, surahNumber);
  }

  // ============ القرّاء / Readers ============

  /// تعيين القارئ / Set the reader by index.
  Future<void> setReader(int index) async {
    if (index < 0 || index >= SurahReaders.active.length) return;
    await _engine.player.stop();
    isPlaying.value = false;
    readerIndex.value = index;
    _box.write(StorageKeys.surahReaderIndex, index);

    // أعد تعيين المصدر للقارئ الجديد
    await _setAudioSource(currentSurahNumber.value);
    _updateMediaItem();
  }

  // ============ التحميل / Downloads ============

  /// حمّل سورة للعمل أوفلاين / Download a surah for offline use.
  Future<bool> downloadSurah(int surahNumber) async {
    if (kIsWeb) return false;
    if (!QuranMetadata.instance.isValidSurah(surahNumber)) return false;

    final reader = currentReader;
    final localPath = SurahUrlBuilder.localPath(
      docsDir: _docsDir!,
      surahNumber: surahNumber,
      reader: reader,
    );
    final url = SurahUrlBuilder.url(surahNumber: surahNumber, reader: reader);

    return _downloadService.download(url: url, localPath: localPath);
  }

  /// هل السورة محمّلة؟ / Is the surah downloaded?
  Future<bool> isSurahDownloaded(int surahNumber) async {
    if (kIsWeb) return false;
    final reader = currentReader;
    final localPath = SurahUrlBuilder.localPath(
      docsDir: _docsDir!,
      surahNumber: surahNumber,
      reader: reader,
    );
    return PlatformIo.fileExists(localPath);
  }

  /// احذف ملف السورة المحمّل / Delete a downloaded surah file.
  Future<void> deleteSurahDownload(int surahNumber) async {
    if (kIsWeb) return;
    final reader = currentReader;
    final localPath = SurahUrlBuilder.localPath(
      docsDir: _docsDir!,
      surahNumber: surahNumber,
      reader: reader,
    );
    await _downloadService.deleteFile(localPath);
  }

  /// ألغِ التحميل الجاري / Cancel ongoing download.
  void cancelDownload() => _downloadService.cancel();

  // ============ التكرار / Repeat ============

  /// تعيين نمط التكرار / Set repeat mode.
  void setRepeatMode(RepeatMode mode) {
    _repeat.setMode(mode);
    // حدّث loopMode في just_audio للسورة
    switch (mode) {
      case RepeatMode.surah:
        _engine.player.setLoopMode(LoopMode.one);
        break;
      default:
        _engine.player.setLoopMode(LoopMode.off);
    }
  }

  // ============ دورة الحياة / Lifecycle ============

  @override
  void onClose() {
    _disablePositionSaving();
    _disableAutoNextListener();
    super.onClose();
  }
}
