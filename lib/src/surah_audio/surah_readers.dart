import '../shared/models/reader_info.dart';

/// ثوابت قرّاء السور ومصادر روابطهم.
///
/// Surah readers constants and their audio source URLs. Each surah is one
/// full MP3 file named `NNN.mp3` under the reader's path.
class SurahReaders {
  SurahReaders._();

  // ============ مصادر روابط السور / Surah URL sources ============

  /// quranicaudio.com
  static const String url1 = 'https://download.quranicaudio.com/quran/';

  /// mp3quran.net - server16
  static const String url2 = 'https://server16.mp3quran.net/';

  /// mp3quran.net - server12
  static const String url3 = 'https://server12.mp3quran.net/';

  /// mp3quran.net - server6
  static const String url4 = 'https://server6.mp3quran.net/';

  /// mp3quran.net - server11
  static const String url5 = 'https://server11.mp3quran.net/';

  /// tarteel.ai
  static const String url6 = 'https://audio-cdn.tarteel.ai/quran/surah/';

  // ============ قرّاء مخصصون (اختياري) / Custom readers (optional) ============

  /// قائمة قرّاء مخصّصة — إن عُيِّنت تُستخدم بدلاً من الافتراضية.
  static List<ReaderInfo>? customReaders;

  /// القائمة النشطة (المخصصة إن وُجدت، وإلا الافتراضية).
  static List<ReaderInfo> get active =>
      customReaders ?? defaults;

  // ============ القائمة الافتراضية (21 قارئ) ============

  static final List<ReaderInfo> defaults = [
    const ReaderInfo(
      index: 0,
      name: 'عبد الباسط',
      readerNamePath: 'abdulBasit/murattal/mp3/',
      url: url6,
    ),
    const ReaderInfo(
      index: 1,
      name: 'محمد المنشاوي',
      readerNamePath: 'minshawy/murattal/mp3/',
      url: url6,
    ),
    const ReaderInfo(
      index: 2,
      name: 'محمود الحصري',
      readerNamePath: 'mahmood_khaleel_al-husaree_iza3a/',
      url: url1,
    ),
    const ReaderInfo(
      index: 3,
      name: 'أحمد العجمي',
      readerNamePath: 'ahmed_ibn_3ali_al-3ajamy/',
      url: url1,
    ),
    const ReaderInfo(
      index: 4,
      name: 'ماهر المعيقلي',
      readerNamePath: 'maher_almu3aiqly/year1440/',
      url: url1,
    ),
    const ReaderInfo(
      index: 5,
      name: 'سعود الشريم',
      readerNamePath: 'saudAlShuraim/murattal/mp3/',
      url: url6,
    ),
    const ReaderInfo(
      index: 6,
      name: 'سعد الغامدي',
      readerNamePath: 'ghamadi/murattal/mp3/',
      url: url6,
    ),
    const ReaderInfo(
      index: 7,
      name: 'مصطفى العززاوي',
      readerNamePath: 'mustafa_al3azzawi/',
      url: url1,
    ),
    const ReaderInfo(
      index: 8,
      name: 'ناصر القطامي',
      readerNamePath: 'nasser_bin_ali_alqatami/',
      url: url1,
    ),
    const ReaderInfo(
      index: 9,
      name: 'قادر الكردي',
      readerNamePath: 'peshawa/Rewayat-Hafs-A-n-Assem/',
      url: url2,
    ),
    const ReaderInfo(
      index: 10,
      name: 'شيرزاد طاهر',
      readerNamePath: 'taher/',
      url: url3,
    ),
    const ReaderInfo(
      index: 11,
      name: 'عبد الرحمن العوسي',
      readerNamePath: 'aloosi/',
      url: url4,
    ),
    const ReaderInfo(
      index: 12,
      name: 'وديع اليمني',
      readerNamePath: 'wdee3/',
      url: url4,
    ),
    const ReaderInfo(
      index: 13,
      name: 'ياسر الدوسري',
      readerNamePath: 'yasser_ad-dussary/',
      url: url1,
    ),
    const ReaderInfo(
      index: 14,
      name: 'عبد الله الجهني',
      readerNamePath: 'abdullaah_3awwaad_al-juhaynee/',
      url: url1,
    ),
    const ReaderInfo(
      index: 15,
      name: 'فارس عباد',
      readerNamePath: 'fares/',
      url: url1,
    ),
    const ReaderInfo(
      index: 16,
      name: 'محمد أيوب',
      readerNamePath: 'muhammad_ayyoob_hq/',
      url: url1,
    ),
    const ReaderInfo(
      index: 17,
      name: 'ماهر المعيقلي - مجود',
      readerNamePath: 'maher/',
      url: url3,
    ),
    const ReaderInfo(
      index: 18,
      name: 'أحمد النفيس - مجود',
      readerNamePath: 'nufais/Rewayat-Hafs-A-n-Assem/',
      url: url2,
    ),
    const ReaderInfo(
      index: 19,
      name: 'ياسر الدوسري - مجود',
      readerNamePath: 'yasser/',
      url: url5,
    ),
    const ReaderInfo(
      index: 20,
      name: 'علي جابر',
      readerNamePath: 'ali_jaber/',
      url: url1,
    ),
  ];
}
