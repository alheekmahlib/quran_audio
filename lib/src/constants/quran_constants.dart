/// ثوابت القرآن الكريم المتعلقة بالتشغيل الصوتي.
///
/// Quran constants relevant to audio playback.
class QuranConstants {
  QuranConstants._();

  /// إجمالي عدد السور / Total number of surahs.
  static const int totalSurahs = 114;

  /// أول رقم سورة / First surah number.
  static const int firstSurah = 1;

  /// آخر رقم سورة / Last surah number.
  static const int lastSurah = 114;

  /// إجمالي عدد آيات القرآن / Total number of ayahs in the Quran.
  static const int totalAyahs = 6236;

  /// أول رقم فريد لآية / First ayah unique number.
  static const int firstAyahUq = 1;

  /// آخر رقم فريد لآية / Last ayah unique number.
  static const int lastAyahUq = 6236;

  /// اسم ملف الـ metadata المضغوط / Compressed metadata asset file name.
  static const String metadataAssetPath =
      'packages/quran_audio/assets/jsons/surah_metadata.json.gz';

  /// اسم ملف الـ metadata الداخلي (للاستخدام داخل المكتبة).
  static const String metadataAssetPathInternal =
      'assets/jsons/surah_metadata.json.gz';

  /// مسار أيقونة الإشعارات الافتراضية المضمّنة في حزمة المكتبة.
  /// Default notification art icon bundled within the library package.
  static const String defaultArtAssetPath =
      'packages/quran_audio/assets/images/quran_audio_logo.png';

  /// حجم نافذة التشغيل الأولية للآيات / Initial ayah playback window size.
  static const int ayahPlaylistWindowSize = 4;

  /// حد التمدد قبل إضافة آية جديدة للنافذة / Threshold before expanding window.
  static const int ayahWindowExpandThreshold = 2;
}
