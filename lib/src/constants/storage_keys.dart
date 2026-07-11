/// مفاتيح التخزين المحلي (GetStorage) للمكتبة.
///
/// Local storage keys (GetStorage) for the library.
class StorageKeys {
  StorageKeys._();

  /// القارئ المختار للسور (فهرس) / Selected surah reader index.
  static const String surahReaderIndex = 'qa_surahReaderIndex';

  /// القارئ المختار للآيات (فهرس) / Selected ayah reader index.
  static const String ayahReaderIndex = 'qa_ayahReaderIndex';

  /// آخر سورة مُستمع إليها / Last listened surah number.
  static const String lastSurah = 'qa_lastSurah';

  /// آخر موضع (بالثواني) في السورة / Last playback position (seconds).
  static const String lastPosition = 'qa_lastPosition';

  /// ما إذا كانت خدمة الصوت مهيّأة / Whether audio service is initialized.
  static const String audioServiceInitialized = 'qa_audioServiceInitialized';

  /// بادئة مفتاح كاش تحميل السورة الكاملة (آيات) / Surah-fully-downloaded cache prefix.
  /// الصيغة: `qa_surahAyahs_{surahNumber}_{readerIndex}`.
  static String surahAyahsDownloadedKey(int surahNumber, int readerIndex) =>
      'qa_surahAyahs_${surahNumber}_$readerIndex';
}
