import 'dart:developer' show log;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:get_storage/get_storage.dart';

import '../ayah_audio/ayah_audio_controller.dart';
import '../engine/audio_engine.dart';
import '../enums/download_scope.dart';
import '../enums/playback_mode.dart';
import '../enums/repeat_mode.dart';
import '../shared/models/position_data.dart';
import '../shared/models/reader_info.dart';
import '../shared/models/surah_meta.dart';
import '../surah_audio/surah_audio_controller.dart';
import 'audio_art.dart';
import 'audio_handler.dart';
import 'media_item_builder.dart';
import 'quran_metadata.dart';

/// الواجهة الموحّدة للمكتبة — نقطة دخول واحدة لكل عمليات التشغيل الصوتي.
///
/// The unified facade for the library — a single entry point for all audio
/// playback operations.
///
/// بدلاً من التعامل مع كنترولرين منفصلين (`SurahAudioController` /
/// `AyahAudioController`)، يقدّم هذا الكلاس واجهة مسطّحة واحدة:
/// - methods تشغيل محدّدة (`playSurah`, `playAyah`) تحدّد النظام بوضوح.
/// - methods تحكم عامة (`pause`, `resume`, `stop`, `seek`, `next`, `previous`)
///   تنفّذ تلقائياً على النظام النشط حالياً.
///
/// مثال:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await QuranAudio.init();
///   runApp(MyApp());
/// }
///
/// // في أي مكان:
/// QuranAudio.playSurah(2);
/// QuranAudio.playAyah(surah: 2, ayah: 255);
/// QuranAudio.pause();   // يوقف النشط (سورة أو آية)
/// QuranAudio.next();    // ينتقل للتالي حسب النظام النشط
/// ```
class QuranAudio {
  QuranAudio._();

  // ============ التهيئة / Initialization ============

  static bool _initialized = false;

  /// هل تمت التهيئة؟ / Has the library been initialized?
  static bool get isInitialized => _initialized;

  /// النمط النشط حالياً / The currently active playback mode.
  static PlaybackMode get activeMode => AudioEngine.instance.activeMode;

  /// هل النظام النشط هو نظام السور؟ / Is the surah system active?
  static bool get isSurahMode => activeMode == PlaybackMode.surah;

  /// هل النظام النشط هو نظام الآيات؟ / Is the ayah system active?
  static bool get isAyahMode => activeMode == PlaybackMode.ayah;

  /// هل يوجد تشغيل نشط أصلاً؟ / Is any playback active?
  static bool get hasActivePlayback => activeMode != PlaybackMode.none;

  /// هيّئ المكتبة بالكامل في خطوة واحدة.
  ///
  /// Initialize the whole library in one step:
  ///  1. تخزين محلي (GetStorage).
  ///  2. بيانات السور الوصفية (~3KB).
  ///  3. كنترولر السور + كنترولر الآيات.
  ///  4. أيقونة الإشعارات الافتراضية (من حزمة المكتبة).
  ///  5. خدمة الصوت بالنظام (إشعارات/شاشة القفل).
  ///
  /// [enableSystemNotifications] - تفعيل إشعارات الوسائط (الافتراضي true).
  /// [notificationIconSource] - مصدر أيقونة الإشعارات (asset/url/file).
  ///   - null (الافتراضي): يستخدم أيقونة المكتبة الافتراضية.
  ///   - مسار asset مثل `'assets/images/logo.png'`.
  ///   - رابط url مثل `'https://example.com/logo.png'`.
  ///   - مسار ملف محلي مثل `'/path/to/logo.png'`.
  static Future<void> init({
    bool enableSystemNotifications = true,
    String androidNotificationChannelId = 'com.quran_audio.playback',
    String androidNotificationChannelName = 'Quran Audio Playback',
    String? notificationIconSource,
  }) async {
    if (_initialized) {
      log('QuranAudio already initialized — skipping.', name: 'QuranAudio');
      return;
    }

    await GetStorage.init();
    await QuranMetadata.instance.load();
    await SurahAudioController.instance.init();
    await AyahAudioController.instance.init();

    // اربط تحديث الأيقونة بإعادة بناء الـ MediaItem أثناء التشغيل النشط.
    // Wire icon refresh to rebuild the active MediaItem.
    MediaItemBuilder.onArtChanged = () async {
      if (isSurahMode) {
        SurahAudioController.instance.refreshMediaItem();
      } else if (isAyahMode) {
        AyahAudioController.instance.refreshMediaItem();
      }
    };

    // اضبط أيقونة الإشعارات (الافتراضية أو المخصّصة).
    // Set the notification icon (default or custom).
    try {
      if (notificationIconSource != null) {
        await AudioArt.setFrom(notificationIconSource);
      } else {
        await AudioArt.setDefault();
      }
    } catch (e) {
      debugPrint('QuranAudio: notification icon setup failed (non-fatal): $e');
    }

    if (enableSystemNotifications) {
      try {
        await initQuranAudioService(
          androidChannelId: androidNotificationChannelId,
          androidChannelName: androidNotificationChannelName,
        );
      } catch (e) {
        debugPrint('QuranAudio: AudioService init failed (non-fatal): $e');
      }
    }

    _initialized = true;
    log(
        'QuranAudio initialized. systemNotifications=$enableSystemNotifications, '
        'platform=${kIsWeb ? "web" : "native"}',
        name: 'QuranAudio');
  }

  // ============ أيقونة الإشعارات / Notification icon ============

  /// عيّن أيقونة الإشعارات من asset.
  ///
  /// Set the notification icon from an asset path.
  ///
  /// مثال: `QuranAudio.setNotificationIconFromAsset('assets/images/logo.png')`.
  static Future<void> setNotificationIconFromAsset(String assetPath) =>
      AudioArt.setFromAsset(assetPath);

  /// عيّن أيقونة الإشعارات من رابط شبكي.
  ///
  /// Set the notification icon from a network URL.
  static Future<void> setNotificationIconFromUrl(String url) =>
      AudioArt.setFromUrl(url);

  /// عيّن أيقونة الإشعارات من مسار ملف محلي.
  ///
  /// Set the notification icon from a local file path.
  static Future<void> setNotificationIconFromFile(String filePath) =>
      AudioArt.setFromFile(filePath);

  /// عيّن أيقونة الإشعارات تلقائياً حسب نوع المصدر (asset / url / file).
  ///
  /// Set the notification icon automatically based on source type.
  static Future<void> setNotificationIcon(String source) =>
      AudioArt.setFrom(source);

  /// استخدم أيقونة المكتبة الافتراضية.
  ///
  /// Use the library's default notification icon.
  static Future<void> useDefaultNotificationIcon() => AudioArt.setDefault();

  /// الأيقونة الحالية (قد تكون null) / Current icon URI (may be null).
  static Uri? get notificationIcon => AudioArt.current;

  // ============ التشغيل — تحديد النظام بوضوح ============
  // Playback — explicitly selects the system.

  /// شغّل سورة كاملة (ملف MP3 واحد) / Play a full surah.
  ///
  /// [surahNumber] - رقم السورة (1..114).
  /// [streamFirst] - true (الافتراضي): بث مباشر فوراً إن لم يكن الملف محمّلاً.
  /// [downloadFirst] - true: حمّل السورة كاملة قبل التشغيل.
  static Future<void> playSurah(
    int surahNumber, {
    bool streamFirst = true,
    bool downloadFirst = false,
  }) =>
      SurahAudioController.instance.playSurah(
        surahNumber: surahNumber,
        streamFirst: streamFirst,
        downloadFirst: downloadFirst,
      );

  /// شغّل آية محددة (ملف MP3 لكل آية) / Play a specific ayah.
  ///
  /// [surah] - رقم السورة (1..114).
  /// [ayah] - رقم الآية ضمن السورة.
  /// [singleAyah] - true: آية واحدة فقط / false: يتابع للآيات التالية.
  /// [streamFirst] - true (الافتراضي): بث مباشر فوراً إن لم يكن الملف محمّلاً.
  /// [downloadFirst] - true: حمّل الآية/السورة أولاً ثم شغّلها (يسود على streamFirst).
  /// [downloadScope] - نطاق التحميل عند downloadFirst=true
  ///   (single: الآية الحالية، surah: كل آيات السورة).
  static Future<void> playAyah({
    required int surah,
    required int ayah,
    bool singleAyah = false,
    bool streamFirst = true,
    bool downloadFirst = false,
    DownloadScope downloadScope = DownloadScope.single,
  }) =>
      AyahAudioController.instance.playAyah(
        surahNumber: surah,
        ayahNumber: ayah,
        singleAyah: singleAyah,
        streamFirst: streamFirst,
        downloadFirst: downloadFirst,
        downloadScope: downloadScope,
      );

  // ============ التحكم — ينفّذ على النظام النشط تلقائياً ============
  // Controls — executed on whichever system is currently active.

  /// استئناف التشغيل (النظام النشط) / Resume the active system.
  static Future<void> resume() async {
    if (isSurahMode) {
      await SurahAudioController.instance.resume();
    } else if (isAyahMode) {
      await AyahAudioController.instance.resume();
    }
  }

  /// إيقاف مؤقت (النظام النشط) / Pause the active system.
  static Future<void> pause() async {
    if (isSurahMode) {
      await SurahAudioController.instance.pause();
    } else if (isAyahMode) {
      await AyahAudioController.instance.pause();
    }
  }

  /// إيقاف كامل (النظام النشط) / Stop the active system.
  static Future<void> stop() async {
    if (isSurahMode) {
      await SurahAudioController.instance.stop();
    } else if (isAyahMode) {
      await AyahAudioController.instance.stop();
    }
  }

  /// تقديم/تأخير (النظام النشط) / Seek the active system.
  static Future<void> seek(Duration position) async {
    if (isSurahMode) {
      await SurahAudioController.instance.seek(position);
    } else if (isAyahMode) {
      await AyahAudioController.instance.seek(position);
    }
  }

  /// التالي (حسب النظام النشط: سورة تالية أو آية تالية).
  ///
  /// Next (depends on active system: next surah or next ayah).
  static Future<void> next() async {
    if (isSurahMode) {
      await SurahAudioController.instance.playNextSurah();
    } else if (isAyahMode) {
      await AyahAudioController.instance.skipNextAyah();
    }
  }

  /// السابق (حسب النظام النشط: سورة سابقة أو آية سابقة).
  ///
  /// Previous (depends on active system: previous surah or previous ayah).
  static Future<void> previous() async {
    if (isSurahMode) {
      await SurahAudioController.instance.playPreviousSurah();
    } else if (isAyahMode) {
      await AyahAudioController.instance.skipPreviousAyah();
    }
  }

  /// تبديل بين التشغيل والإيقاف المؤقت (النظام النشط).
  ///
  /// Toggle play/pause (active system).
  static Future<void> togglePlayPause() async {
    if (isSurahMode) {
      final c = SurahAudioController.instance;
      c.isPlaying.value ? await c.pause() : await c.resume();
    } else if (isAyahMode) {
      final c = AyahAudioController.instance;
      c.isPlaying.value ? await c.pause() : await c.resume();
    }
  }

  // ============ القرّاء / Readers ============

  /// قائمة قرّاء السور / Surah readers list.
  static List<ReaderInfo> get surahReaders =>
      SurahAudioController.instance.readers;

  /// قائمة قرّاء الآيات / Ayah readers list.
  static List<ReaderInfo> get ayahReaders =>
      AyahAudioController.instance.readers;

  /// فهرس قارئ السور الحالي / Current surah reader index.
  static int get surahReaderIndex =>
      SurahAudioController.instance.readerIndex.value;

  /// فهرس قارئ الآيات الحالي / Current ayah reader index.
  static int get ayahReaderIndex =>
      AyahAudioController.instance.readerIndex.value;

  /// تعيين قارئ السور / Set the surah reader by index.
  static Future<void> setSurahReader(int index) =>
      SurahAudioController.instance.setReader(index);

  /// تعيين قارئ الآيات / Set the ayah reader by index.
  static Future<void> setAyahReader(int index) =>
      AyahAudioController.instance.setReader(index);

  // ============ التحميل / Downloads ============

  /// حمّل سورة كاملة للعمل أوفلاين (نظام السور) / Download a full surah.
  static Future<bool> downloadSurah(int surahNumber) =>
      SurahAudioController.instance.downloadSurah(surahNumber);

  /// هل السورة محمّلة (نظام السور)؟ / Is a surah downloaded?
  static Future<bool> isSurahDownloaded(int surahNumber) =>
      SurahAudioController.instance.isSurahDownloaded(surahNumber);

  /// احذف ملف سورة محمّل / Delete a downloaded surah.
  static Future<void> deleteSurahDownload(int surahNumber) =>
      SurahAudioController.instance.deleteSurahDownload(surahNumber);

  /// حمّل جميع آيات سورة للعمل أوفلاين (نظام الآيات).
  ///
  /// [onProgress] - رد نداء اختياري: (current, total).
  static Future<void> downloadSurahAyahs(
    int surahNumber, {
    void Function(int current, int total)? onProgress,
  }) =>
      AyahAudioController.instance
          .downloadSurahAyahs(surahNumber, onProgress: onProgress);

  /// حمّل نطاقاً من الآيات / Download a range of ayahs.
  static Future<void> downloadAyahRange(
    int surahNumber, {
    required int from,
    required int to,
    void Function(int current, int total)? onProgress,
  }) =>
      AyahAudioController.instance.downloadAyahRange(
        surahNumber,
        from: from,
        to: to,
        onProgress: onProgress,
      );

  /// هل آية محمّلة؟ / Is an ayah downloaded?
  static Future<bool> isAyahDownloaded(int surahNumber, int ayahInSurah) =>
      AyahAudioController.instance.isAyahDownloaded(surahNumber, ayahInSurah);

  /// هل جميع آيات السورة محمّلة؟ / Are all ayahs of a surah downloaded?
  static Future<bool> isSurahAyahsDownloaded(int surahNumber) =>
      AyahAudioController.instance.isSurahAyahsDownloaded(surahNumber);

  /// احذف آيات سورة محمّلة / Delete downloaded ayahs of a surah.
  static Future<void> deleteSurahAyahDownloads(int surahNumber) =>
      AyahAudioController.instance.deleteSurahAyahDownloads(surahNumber);

  /// ألغِ التحميل الجاري / Cancel the ongoing download.
  static void cancelDownload() {
    if (isSurahMode) {
      SurahAudioController.instance.cancelDownload();
    } else if (isAyahMode) {
      AyahAudioController.instance.cancelDownload();
    } else {
      // ألغِ في كلا النظامين احتياطاً
      SurahAudioController.instance.cancelDownload();
      AyahAudioController.instance.cancelDownload();
    }
  }

  // ============ التكرار / Repeat ============

  /// تعيين نمط التكرار للنظام النشط / Set repeat mode (active system).
  static void setRepeatMode(RepeatMode mode) {
    if (isSurahMode) {
      SurahAudioController.instance.setRepeatMode(mode);
    } else if (isAyahMode) {
      AyahAudioController.instance.setRepeatMode(mode);
    }
  }

  /// تكرار الآية الحالية (نظام الآيات) / Repeat the current ayah.
  static void repeatAyah() => AyahAudioController.instance.setRepeatOne();

  /// تكرار السورة الحالية / Repeat the current surah.
  static void repeatSurah() {
    if (isSurahMode) {
      SurahAudioController.instance.setRepeatMode(RepeatMode.surah);
    } else if (isAyahMode) {
      AyahAudioController.instance.setRepeatSurah();
    }
  }

  /// تكرار نطاق آيات (نظام الآيات) / Repeat an ayah range.
  static void repeatAyahRange({
    required int fromAyah,
    required int toAyah,
    int? times,
  }) =>
      AyahAudioController.instance.setRepeatRange(
        fromAyah: fromAyah,
        toAyah: toAyah,
        times: times,
      );

  /// أوقف التكرار / Disable repeat (both systems).
  static void disableRepeat() {
    SurahAudioController.instance.setRepeatMode(RepeatMode.off);
    AyahAudioController.instance.disableRepeat();
  }

  // ============ الحالة الحالية / Current state ============

  /// السورة الحالية (أياً كان النظام النشط) / Current surah number.
  static int get currentSurahNumber {
    if (isSurahMode) {
      return SurahAudioController.instance.currentSurahNumber.value;
    } else if (isAyahMode) {
      return AyahAudioController.instance.currentSurahNumber.value;
    }
    return SurahAudioController.instance.currentSurahNumber.value;
  }

  /// الآية الحالية ضمن السورة (نظام الآيات، أو null لنظام السور).
  ///
  /// Current ayah in surah (ayah system; null in surah mode).
  static int get currentAyahInSurah =>
      AyahAudioController.instance.currentAyahInSurah.value;

  /// هل التشغيل جارٍ؟ / Is playback active?
  static bool get isPlaying {
    if (isSurahMode) {
      return SurahAudioController.instance.isPlaying.value;
    } else if (isAyahMode) {
      return AyahAudioController.instance.isPlaying.value;
    }
    return false;
  }

  /// تدفق الموضع المدمج للنظام النشط / Combined position stream (active system).
  static Stream<PositionData> get positionDataStream =>
      AudioEngine.instance.positionDataStream;

  // ============ بيانات السور / Surah metadata ============

  /// بيانات سورة بالرقم / Get surah metadata by number.
  static SurahMeta surah(int surahNumber) =>
      QuranMetadata.instance.surah(surahNumber);

  /// عدد آيات سورة / Ayah count of a surah.
  static int ayahCountOf(int surahNumber) =>
      QuranMetadata.instance.ayahCountOf(surahNumber);

  /// الرقم الفريد لآية / UQ number for an ayah.
  static int uqNumberOf(int surah, int ayah) =>
      QuranMetadata.instance.uqNumberOf(surah, ayah);

  /// كل السور / All surahs.
  static List<SurahMeta> get allSurahs => QuranMetadata.instance.allSurahs;

  // ============ الوصول المتقدم / Advanced access ============
  // للوصول المباشر للكنترولرات عند الحاجة لتخصيص أعمق.

  /// كنترولر السور (وصول متقدم) / Surah controller (advanced access).
  static SurahAudioController get surahController =>
      SurahAudioController.instance;

  /// كنترولر الآيات (وصول متقدم) / Ayah controller (advanced access).
  static AyahAudioController get ayahController => AyahAudioController.instance;

  /// بيانات السور الوصفية (وصول متقدم) / Metadata (advanced access).
  static QuranMetadata get metadata => QuranMetadata.instance;

  /// أعد ضبط حالة التهيئة (لاختبارات الوحدة).
  /// Reset initialization state (mainly for unit tests).
  static void reset() {
    _initialized = false;
  }
}
