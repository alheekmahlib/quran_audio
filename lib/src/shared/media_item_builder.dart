import 'dart:developer' show log;

import 'package:audio_service/audio_service.dart';

import '../shared/models/reader_info.dart';
import '../shared/quran_metadata.dart';

/// باني عناصر الوسائط (MediaItem) لإشعارات النظام — منفصل عن أي QuranCtrl.
///
/// Builds MediaItem instances for system notifications — independent of any QuranCtrl.
class MediaItemBuilder {
  MediaItemBuilder._();

  /// Uri? - رابط أيقونة الإشعارات / notification art icon URI (nullable).
  /// يمكن للمستخدم تخصيصه عبر [AudioArt] أو `QuranAudio.setNotificationIcon`.
  ///
  /// The notification art icon URI. Customize via [AudioArt] or
  /// `QuranAudio.setNotificationIcon`.
  static Uri? appIconUri;

  /// رد نداء يُستدعى عند تغيّر artUri ليُحدّث الـ controller النشط.
  /// تُسجّله `QuranAudio` لتجنب الاعتماد الدائري.
  ///
  /// Callback invoked when artUri changes so the active controller can refresh.
  /// Registered by `QuranAudio` to avoid a circular dependency.
  static Future<void> Function()? onArtChanged;

  /// ابنِ MediaItem لسورة كاملة / Build MediaItem for a full surah.
  static MediaItem surahItem({
    required int surahNumber,
    required ReaderInfo reader,
  }) {
    final meta = QuranMetadata.instance.surah(surahNumber);
    return MediaItem(
      id: '$surahNumber',
      title: meta.name,
      album: '${meta.englishName} (${meta.ayahCount} آية)',
      artist: reader.name,
      artUri: appIconUri,
    );
  }

  /// ابنِ MediaItem لآية محددة / Build MediaItem for a specific ayah.
  static MediaItem ayahItem({
    required int surahNumber,
    required int ayahInSurah,
    required ReaderInfo reader,
  }) {
    final meta = QuranMetadata.instance.surah(surahNumber);
    return MediaItem(
      id: '${surahNumber}_$ayahInSurah',
      title: '${meta.englishName} $surahNumber:$ayahInSurah',
      album: meta.name,
      artist: reader.name,
      artUri: appIconUri,
    );
  }

  /// حدّث الـ MediaItem الحالي بإشعارات النظام ليعكس artUri الجديد.
  ///
  /// Refresh the current MediaItem in the system notification to reflect the
  /// new artUri.
  static Future<void> refreshCurrentMediaItem() async {
    try {
      await onArtChanged?.call();
    } catch (e) {
      log('MediaItemBuilder: refresh failed (non-fatal): $e',
          name: 'MediaItemBuilder');
    }
  }
}
