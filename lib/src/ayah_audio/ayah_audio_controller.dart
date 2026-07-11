import 'dart:async';
import 'dart:developer' show log;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:just_audio/just_audio.dart';

import '../constants/quran_constants.dart';
import '../constants/storage_keys.dart';
import '../engine/audio_engine.dart';
import '../enums/download_scope.dart';
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
import 'ayah_readers.dart';
import 'ayah_url_builder.dart';

/// متحكّم تشغيل الآيات - يدير تشغيل الآيات المفردة (ملف MP3 لكل آية).
///
/// Ayah playback controller — manages single-ayah playback (one MP3 per ayah).
///
/// لكل قارئ تنسيق رابط مختلف حسب المصدر، وقرّاء مستقلون عن نظام السور.
/// Each reader has a different URL format depending on the source, and readers
/// are independent from the surah system.
///
/// يدعم نمطين:
/// - [playSingleAyah] = true: تشغيل آية واحدة فقط ثم توقف.
/// - [playSingleAyah] = false: تشغيل متتابع للآيات داخل السورة (playlist).
class AyahAudioController extends GetxController {
  AyahAudioController();

  static AyahAudioController? _instance;
  static AyahAudioController get instance {
    _instance ??= AyahAudioController();
    if (!Get.isRegistered<AyahAudioController>()) {
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

  /// رقم الآية الحالية ضمن السورة / Current ayah number within the surah.
  final RxInt currentAyahInSurah = 1.obs;

  /// الرقم الفريد للآية الحالية (1..6236) / Current ayah unique number.
  final RxInt currentAyahUq = 1.obs;

  /// فهرس القارئ الحالي / Current reader index.
  final RxInt readerIndex = 0.obs;

  /// نمط التشغيل: آية واحدة فقط / Single-ayah mode.
  final RxBool playSingleAyah = false.obs;

  /// نمط التكرار الحالي / Current repeat mode.
  Rx<RepeatMode> get repeatMode => _repeat.mode.obs;

  // ============ متغيرات داخلية / Internal ============

  /// مجلد التخزين المحلي / Local storage directory.
  String? _docsDir;

  /// قائمة الـ AudioSources الحالية للـ playlist (للنمو التدريجي).
  final List<AudioSource> _playlistSources = [];

  /// فهرس بداية الـ playlist داخل السورة (للنمط المتحرك).
  int _playlistStartIndex = 0;

  /// هل يُفضّل التحميل قبل التشغيل (من معامل downloadFirst)؟
  /// يُعاد ضبطه لـ false بعد كل عملية تشغيل.
  ///
  /// Whether to prefer downloading before playback (from downloadFirst).
  /// Reset to false after each playback.
  bool _preferLocal = false;

  /// القارئ الحالي / Current reader.
  ReaderInfo get currentReader => AyahReaders.active[readerIndex.value];

  /// قائمة القرّاء / Readers list.
  List<ReaderInfo> get readers => AyahReaders.active;

  /// هل النظام هو النشط حالياً؟ / Is this the active system?
  bool get isActive => _engine.activeMode == PlaybackMode.ayah;

  /// الرقم الفريد للآية الحالية (محسوب) / Computed UQ of current ayah.
  int get uqNumberOfCurrent => QuranMetadata.instance
      .uqNumberOf(currentSurahNumber.value, currentAyahInSurah.value);

  /// تدفق الموضع المدمج / Combined position stream.
  Stream<PositionData> get positionDataStream => _engine.positionDataStream;

  // ============ التهيئة / Initialization ============

  /// هيّئ الكنترولر (يُستدعى مرة بعد GetStorage.init).
  Future<void> init() async {
    await QuranMetadata.instance.load();
    await _engine.init();

    readerIndex.value = _box.read(StorageKeys.ayahReaderIndex) ?? 0;

    if (!kIsWeb) {
      _docsDir = await PlatformIo.documentsDir;
    }

    _registerAudioHandlerCallbacks();

    // عند استيلاء نظام السور على المشغل، أوقف حالة التشغيل لدينا
    // When the surah system takes over, reset our playing state.
    _engine.addControlLostListener((previousMode) {
      if (previousMode == PlaybackMode.ayah) {
        isPlaying.value = false;
        _engine.cancelAllSubscriptions();
      }
    });

    log('AyahAudioController initialized', name: 'AyahAudioController');
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
      if (isActive) await skipNextAyah();
    };
    handler.onSkipToPrevious = () async {
      if (isActive) await skipPreviousAyah();
    };
  }

  // ============ التشغيل / Playback ============

  /// شغّل آية محددة - الميثود الأساسية المطلوبة.
  ///
  /// Play a specific ayah — the primary entry point.
  ///
  /// [surahNumber] - رقم السورة (1..114).
  /// [ayahNumber] - رقم الآية ضمن السورة (1..ayahCount).
  /// [singleAyah] - true: آية واحدة فقط / false: أكمل للآيات التالية في السورة.
  /// [streamFirst] - true (الافتراضي): بث مباشر فوراً إن لم يكن الملف محمّلاً.
  /// [downloadFirst] - true: حمّل الآية/السورة أولاً ثم شغّلها (يسود على streamFirst).
  /// [downloadScope] - نطاق التحميل عند downloadFirst=true (single: الآية الحالية،
  ///   surah: كل آيات السورة).
  Future<void> playAyah({
    required int surahNumber,
    required int ayahNumber,
    bool singleAyah = false,
    bool streamFirst = true,
    bool downloadFirst = false,
    DownloadScope downloadScope = DownloadScope.single,
  }) async {
    if (!QuranMetadata.instance.isValidAyah(surahNumber, ayahNumber)) {
      log('Invalid ayah ($surahNumber:$ayahNumber)',
          name: 'AyahAudioController');
      return;
    }

    // استولِ على المشغّل (يوقف نظام السور إن كان نشطاً)
    await _engine.takeControl(PlaybackMode.ayah);

    isPreparing.value = true;
    currentSurahNumber.value = surahNumber;
    currentAyahInSurah.value = ayahNumber;
    currentAyahUq.value = uqNumberOfCurrent;
    playSingleAyah.value = singleAyah;

    // اضبط تفضيل التحميل لِـ _ayahAudioSource (يُعاد ضبطه لاحقاً).
    // Set the download preference for _ayahAudioSource (reset later).
    _preferLocal = downloadFirst && !kIsWeb;

    // إن طُلب التحميل قبل التشغيل، حمّل النطاق المطلوب أولاً.
    // If download-first was requested, download the requested scope first.
    if (_preferLocal) {
      try {
        if (downloadScope == DownloadScope.surah) {
          // حمّل كل آيات السورة / download all surah ayahs
          await downloadSurahAyahs(surahNumber);
        } else {
          // حمّل الآية الحالية فقط / download only the current ayah
          await _downloadCurrentAyah(surahNumber, ayahNumber);
        }
      } catch (e, s) {
        log('playAyah: pre-download failed, falling back to stream: $e',
            name: 'AyahAudioController', stackTrace: s);
        _preferLocal = false; // ارجع للبث عند فشل التحميل
      }
    }
    // ملاحظة: streamFirst ضمني عندما downloadFirst=false؛ لا حاجة لِمنطق إضافي
    // لأن _ayahAudioSource يبثّ افتراضياً عند عدم وجود الملف.

    try {
      if (singleAyah) {
        await _playSingleAyah(surahNumber, ayahNumber);
      } else {
        await _playAyahPlaylist(surahNumber, ayahNumber);
      }
      isPlaying.value = true;
      isPreparing.value = false;
      _updateMediaItem();
    } catch (e, s) {
      isPreparing.value = false;
      isPlaying.value = false;
      log('playAyah($surahNumber:$ayahNumber) failed: $e',
          name: 'AyahAudioController', stackTrace: s);
    } finally {
      _preferLocal = false; // أعد الضبط بعد التشغيل
    }
  }

  /// حمّل آية واحدة (للتحميل قبل التشغيل).
  /// Download a single ayah (for download-then-play).
  Future<void> _downloadCurrentAyah(int surah, int ayah) async {
    final reader = currentReader;
    final localPath = AyahUrlBuilder.localPath(
      docsDir: _docsDir!,
      surahNumber: surah,
      ayahInSurah: ayah,
      reader: reader,
    );
    final url = AyahUrlBuilder.url(
      surahNumber: surah,
      ayahInSurah: ayah,
      reader: reader,
    );
    await _downloadService.downloadIfNotExists(url: url, localPath: localPath);
  }

  /// استئناف التشغيل / Resume playback.
  Future<void> resume() async {
    if (!isActive) return;
    isPlaying.value = true;
    await _engine.player.play();
  }

  /// إيقاف مؤقت / Pause.
  Future<void> pause() async {
    if (!isActive) return;
    isPlaying.value = false;
    await _engine.player.pause();
  }

  /// إيقاف كامل / Stop.
  Future<void> stop() async {
    isPlaying.value = false;
    _engine.cancelAllSubscriptions();
    await _engine.player.stop();
  }

  /// تقديم/تأخير / Seek to position.
  Future<void> seek(Duration position) async {
    await _engine.player.seek(position);
  }

  /// الآية التالية / Skip to next ayah (respects surah boundaries).
  Future<void> skipNextAyah() async {
    final surah = currentSurahNumber.value;
    final ayah = currentAyahInSurah.value;
    final total = QuranMetadata.instance.ayahCountOf(surah);

    // عند آخر آية في السورة، توقف / stop at last ayah
    if (ayah >= total) {
      await stop();
      return;
    }

    if (playSingleAyah.value) {
      await playAyah(
        surahNumber: surah,
        ayahNumber: ayah + 1,
        singleAyah: true,
      );
    } else {
      // في نمط playlist استخدم seekToNext
      try {
        await _engine.player.seekToNext();
      } catch (e) {
        log('seekToNext failed: $e', name: 'AyahAudioController');
      }
    }
  }

  /// الآية السابقة / Skip to previous ayah (respects surah boundaries).
  Future<void> skipPreviousAyah() async {
    final surah = currentSurahNumber.value;
    final ayah = currentAyahInSurah.value;

    // عند أول آية في السورة، توقف / stop at first ayah
    if (ayah <= 1) {
      await stop();
      return;
    }

    if (playSingleAyah.value) {
      await playAyah(
        surahNumber: surah,
        ayahNumber: ayah - 1,
        singleAyah: true,
      );
    } else {
      try {
        await _engine.player.seekToPrevious();
      } catch (e) {
        log('seekToPrevious failed: $e', name: 'AyahAudioController');
      }
    }
  }

  // ============ نمط الآية المفردة / Single-ayah mode ============

  Future<void> _playSingleAyah(int surah, int ayah) async {
    await _engine.player.stop();
    final source = await _ayahAudioSource(surah, ayah);

    await _engine.player.setAudioSource(source);

    // مستمع لإيقاف عند الاكتمال / listener to stop on completion
    _engine.playerStateSubscription?.cancel();
    _engine.playerStateSubscription =
        _engine.player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        // تحقّق من التكرار / check repeat
        if (_repeat.mode == RepeatMode.one) {
          await _engine.player.seek(Duration.zero);
          await _engine.player.play();
          return;
        }
        isPlaying.value = false;
        await _engine.player.stop();
      }
    });
    await _engine.player.play();
  }

  // ============ نمط الـ playlist + windowing / Playlist mode ============

  Future<void> _playAyahPlaylist(int surah, int startAyah) async {
    await _engine.player.stop();
    _engine.cancelAllSubscriptions();

    final totalAyahs = QuranMetadata.instance.ayahCountOf(surah);

    // ابنِ نافذة أولية بحجم windowSize تبدأ من startAyah
    // Build an initial window of `windowSize` ayahs starting from startAyah
    _playlistStartIndex = startAyah;
    final remaining = totalAyahs - startAyah + 1;
    final batchCount = remaining < QuranConstants.ayahPlaylistWindowSize
        ? remaining
        : QuranConstants.ayahPlaylistWindowSize;

    _playlistSources.clear();
    for (int i = 0; i < batchCount; i++) {
      final ayahInSurah = startAyah + i;
      _playlistSources.add(await _ayahAudioSource(surah, ayahInSurah));
    }

    // عيّن قائمة التشغيل مع الفهرس الابتدائي 0
    await _engine.player.setAudioSources(
      _playlistSources,
      initialIndex: 0,
    );
    await _engine.player.setShuffleModeEnabled(false);
    await _engine.player.setLoopMode(LoopMode.off);

    // مستمع تغيّر الفهرس — يحدّث الآية الحالية + يوسّع النافذة
    // Index-change listener — updates current ayah + expands window
    int? lastHandledIndex;
    _engine.currentIndexSubscription =
        _engine.player.sequenceStateStream.listen((sequenceState) async {
      final index = sequenceState.currentIndex;
      if (index == null || index < 0 || index >= _playlistSources.length) {
        return;
      }
      if (lastHandledIndex == index) return; // تجاهل التكرار
      lastHandledIndex = index;

      // احسب رقم الآية الجديد / compute new ayah number
      final globalAyah = _playlistStartIndex + index;
      if (globalAyah > totalAyahs) return;

      currentAyahInSurah.value = globalAyah;
      currentSurahNumber.value = surah;
      currentAyahUq.value = QuranMetadata.instance.uqNumberOf(surah, globalAyah);
      _updateMediaItem();

      // توسيع النافذة تدريجياً / gradually expand the window
      if (!kIsWeb) {
        await _maybeExpandWindow(index, totalAyahs);
      }
    });

    // مستمع الاكتمال — يدير التكرار والتوقف / completion listener
    _engine.playerStateSubscription =
        _engine.player.playerStateStream.listen((state) async {
      if (state.processingState != ProcessingState.completed) return;
      if (!isActive) return;

      final action = _repeat.onCompleted(
        currentSurah: surah,
        currentAyah: currentAyahInSurah.value,
      );

      switch (action) {
        case RepeatActionReplayCurrent():
          await _engine.player.seek(Duration.zero);
          await _engine.player.play();
          break;
        case RepeatActionReplayRange(:final fromAyah):
          await playAyah(surahNumber: surah, ayahNumber: fromAyah);
          break;
        case RepeatActionStop():
          isPlaying.value = false;
          await _engine.player.stop();
          break;
        case RepeatActionProceedNext():
          // اكتملت السورة — توقف (لا انتقال تلقائي للسورة التالية افتراضياً)
          isPlaying.value = false;
          await _engine.player.stop();
          break;
        case RepeatActionReplaySurah():
          await playAyah(surahNumber: surah, ayahNumber: 1);
          break;
      }
    });

    await _engine.player.play();
  }

  /// وسّع نافذة الـ playlist بإضافة آية واحدة عند الاقتراب من النهاية.
  ///
  /// Expand the playlist window by appending one ayah when nearing the end.
  Future<void> _maybeExpandWindow(int currentIndex, int totalAyahs) async {
    final lastPlaylistGlobalIndex =
        _playlistStartIndex + _playlistSources.length - 1;
    final currentGlobalIndex = _playlistStartIndex + currentIndex;

    // إذا تبقّى أقل من الحد أمامنا وما زال هناك آيات، أضف آية واحدة
    if (lastPlaylistGlobalIndex < totalAyahs - 1 &&
        (lastPlaylistGlobalIndex - currentGlobalIndex) <
            QuranConstants.ayahWindowExpandThreshold) {
      final nextGlobalIndex = lastPlaylistGlobalIndex + 1;
      if (nextGlobalIndex >= 1 && nextGlobalIndex <= totalAyahs) {
        try {
          final source = await _ayahAudioSource(
              currentSurahNumber.value, nextGlobalIndex);
          await _engine.player.addAudioSource(source);
          _playlistSources.add(source);
        } catch (e) {
          log('Window expand failed at ayah $nextGlobalIndex: $e',
              name: 'AyahAudioController');
        }
      }
    }
  }

  // ============ بناء مصدر الصوت للآية / Build audio source ============

  Future<AudioSource> _ayahAudioSource(int surah, int ayah) async {
    final reader = currentReader;
    final tag = MediaItemBuilder.ayahItem(
      surahNumber: surah,
      ayahInSurah: ayah,
      reader: reader,
    );

    if (kIsWeb) {
      // ويب: بث مباشر دائماً (لا يمكن التحميل) / web: always stream
      final url =
          AyahUrlBuilder.url(surahNumber: surah, ayahInSurah: ayah, reader: reader);
      return AudioSource.uri(Uri.parse(url), tag: tag);
    }

    // محلي: تحقق من الملف أولاً / local: check file first
    final localPath = AyahUrlBuilder.localPath(
      docsDir: _docsDir!,
      surahNumber: surah,
      ayahInSurah: ayah,
      reader: reader,
    );

    if (await PlatformIo.fileExists(localPath)) {
      return AudioSource.file(localPath, tag: tag);
    } else if (_preferLocal) {
      // downloadFirst=true: حمّل الآية ثم شغّلها محلياً.
      // downloadFirst=true: download the ayah then play locally.
      final url = AyahUrlBuilder.url(
          surahNumber: surah, ayahInSurah: ayah, reader: reader);
      await _downloadService.downloadIfNotExists(url: url, localPath: localPath);
      return AudioSource.file(localPath, tag: tag);
    } else {
      // غير محمّل — بث مباشر / not downloaded — stream
      final url =
          AyahUrlBuilder.url(surahNumber: surah, ayahInSurah: ayah, reader: reader);
      return AudioSource.uri(Uri.parse(url), tag: tag);
    }
  }

  void _updateMediaItem() {
    final item = MediaItemBuilder.ayahItem(
      surahNumber: currentSurahNumber.value,
      ayahInSurah: currentAyahInSurah.value,
      reader: currentReader,
    );
    QuranAudioHandler.instance.mediaItem.add(item);
  }

  /// أعد بناء وبثّ الـ MediaItem الحالي (لتحديث الأيقونة أثناء التشغيل).
  ///
  /// Rebuild and broadcast the current MediaItem (to refresh the icon during playback).
  void refreshMediaItem() => _updateMediaItem();

  // ============ القرّاء / Readers ============

  /// تعيين القارئ / Set the reader by index.
  Future<void> setReader(int index) async {
    if (index < 0 || index >= AyahReaders.active.length) return;
    await _engine.player.stop();
    isPlaying.value = false;
    readerIndex.value = index;
    _box.write(StorageKeys.ayahReaderIndex, index);

    // إن كان التشغيل جارياً، أعد تشغيل الآية الحالية بالقارئ الجديد
    if (currentSurahNumber.value > 0 && currentAyahInSurah.value > 0) {
      await playAyah(
        surahNumber: currentSurahNumber.value,
        ayahNumber: currentAyahInSurah.value,
        singleAyah: playSingleAyah.value,
      );
    }
  }

  // ============ التحميل / Downloads ============

  /// حمّل آيات سورة كاملة للعمل أوفلاين / Download all ayahs of a surah.
  Future<void> downloadSurahAyahs(int surahNumber,
      {void Function(int current, int total)? onProgress}) async {
    if (kIsWeb) return;
    if (!QuranMetadata.instance.isValidSurah(surahNumber)) return;

    final total = QuranMetadata.instance.ayahCountOf(surahNumber);
    final reader = currentReader;

    for (int ayah = 1; ayah <= total; ayah++) {
      final localPath = AyahUrlBuilder.localPath(
        docsDir: _docsDir!,
        surahNumber: surahNumber,
        ayahInSurah: ayah,
        reader: reader,
      );
      final url = AyahUrlBuilder.url(
        surahNumber: surahNumber,
        ayahInSurah: ayah,
        reader: reader,
      );
      await _downloadService.downloadIfNotExists(
        url: url,
        localPath: localPath,
      );
      // ضع علامة محمّلة في الكاش
      _box.write(
        StorageKeys.surahAyahsDownloadedKey(surahNumber, readerIndex.value),
        false,
      );
      onProgress?.call(ayah, total);
    }
    _box.write(
      StorageKeys.surahAyahsDownloadedKey(surahNumber, readerIndex.value),
      true,
    );
  }

  /// حمّل نطاقاً من الآيات / Download a range of ayahs.
  Future<void> downloadAyahRange(
    int surahNumber, {
    required int from,
    required int to,
    void Function(int current, int total)? onProgress,
  }) async {
    if (kIsWeb) return;
    final reader = currentReader;
    final total = to - from + 1;
    var done = 0;
    for (int ayah = from; ayah <= to; ayah++) {
      final localPath = AyahUrlBuilder.localPath(
        docsDir: _docsDir!,
        surahNumber: surahNumber,
        ayahInSurah: ayah,
        reader: reader,
      );
      final url = AyahUrlBuilder.url(
        surahNumber: surahNumber,
        ayahInSurah: ayah,
        reader: reader,
      );
      await _downloadService.downloadIfNotExists(
        url: url,
        localPath: localPath,
      );
      done++;
      onProgress?.call(done, total);
    }
  }

  /// هل الآية محمّلة؟ / Is an ayah downloaded?
  Future<bool> isAyahDownloaded(int surahNumber, int ayahInSurah) async {
    if (kIsWeb) return false;
    final reader = currentReader;
    final localPath = AyahUrlBuilder.localPath(
      docsDir: _docsDir!,
      surahNumber: surahNumber,
      ayahInSurah: ayahInSurah,
      reader: reader,
    );
    return PlatformIo.fileExists(localPath);
  }

  /// هل جميع آيات السورة محمّلة؟ / Are all ayahs of a surah downloaded?
  Future<bool> isSurahAyahsDownloaded(int surahNumber) async {
    if (kIsWeb) return false;

    // تحقق من الكاش أولاً / check cache first
    final cached = _box.read<bool>(
      StorageKeys.surahAyahsDownloadedKey(surahNumber, readerIndex.value),
    );
    if (cached == true) return true;

    final total = QuranMetadata.instance.ayahCountOf(surahNumber);
    final reader = currentReader;
    for (int ayah = 1; ayah <= total; ayah++) {
      final localPath = AyahUrlBuilder.localPath(
        docsDir: _docsDir!,
        surahNumber: surahNumber,
        ayahInSurah: ayah,
        reader: reader,
      );
      if (!await PlatformIo.fileExists(localPath)) {
        _box.write(
          StorageKeys.surahAyahsDownloadedKey(surahNumber, readerIndex.value),
          false,
        );
        return false;
      }
    }
    _box.write(
      StorageKeys.surahAyahsDownloadedKey(surahNumber, readerIndex.value),
      true,
    );
    return true;
  }

  /// احذف آيات سورة محمّلة / Delete downloaded ayahs of a surah.
  Future<void> deleteSurahAyahDownloads(int surahNumber) async {
    if (kIsWeb) return;
    final total = QuranMetadata.instance.ayahCountOf(surahNumber);
    final reader = currentReader;
    for (int ayah = 1; ayah <= total; ayah++) {
      final localPath = AyahUrlBuilder.localPath(
        docsDir: _docsDir!,
        surahNumber: surahNumber,
        ayahInSurah: ayah,
        reader: reader,
      );
      await _downloadService.deleteFile(localPath);
    }
    _box.write(
      StorageKeys.surahAyahsDownloadedKey(surahNumber, readerIndex.value),
      false,
    );
  }

  /// ألغِ التحميل الجاري / Cancel ongoing download.
  void cancelDownload() => _downloadService.cancel();

  // ============ التكرار / Repeat ============

  /// تعيين نمط التكرار / Set repeat mode.
  void setRepeatMode(RepeatMode mode) => _repeat.setMode(mode);

  /// تكرار آية واحدة / Repeat a single ayah.
  void setRepeatOne() => _repeat.setOne();

  /// تكرار السورة / Repeat the whole surah.
  void setRepeatSurah() => _repeat.setSurah();

  /// تكرار نطاق آيات / Repeat an ayah range.
  void setRepeatRange({
    required int fromAyah,
    required int toAyah,
    int? times,
  }) =>
      _repeat.setRange(fromAyah: fromAyah, toAyah: toAyah, times: times);

  /// أوقف التكرار / Disable repeat.
  void disableRepeat() => _repeat.off();

  // ============ دورة الحياة / Lifecycle ============

  @override
  void onClose() {
    _engine.cancelAllSubscriptions();
    super.onClose();
  }
}
