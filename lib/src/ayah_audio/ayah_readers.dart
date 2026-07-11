import '../shared/models/reader_info.dart';

/// ثوابت قرّاء الآيات ومصادر روابطهم.
///
/// Ayah readers constants and their audio source URLs. Each ayah is one MP3.
/// لكل قارئ تنسيق اسم ملف مختلف حسب المصدر (راجع [AyahUrlBuilder]).
class AyahReaders {
  AyahReaders._();

  // ============ مصادر روابط الآيات / Ayah URL sources ============

  /// cdn.islamic.network — اسم الملف = الرقم الفريد للآية (1..6236).
  /// File name = ayah UQ number (1..6236).
  static const String islamicNetworkSource =
      'https://cdn.islamic.network/quran/audio/';

  /// everyayah.com — اسم الملف = رقم السورة (3 أرقام) + رقم الآية (3 أرقام).
  /// File name = surah(3-digit) + ayah(3-digit).
  static const String everyAyahSource = 'https://everyayah.com/data/';

  // ============ قرّاء مخصصون (اختياري) / Custom readers (optional) ============

  /// قائمة قرّاء مخصّصة — إن عُيِّنت تُستخدم بدلاً من الافتراضية.
  static List<ReaderInfo>? customReaders;

  /// القائمة النشطة (المخصصة إن وُجدت، وإلا الافتراضية).
  static List<ReaderInfo> get active =>
      customReaders ?? defaults;

  // ============ القائمة الافتراضية (12 قارئ) ============

  static final List<ReaderInfo> defaults = [
    const ReaderInfo(
      index: 0,
      name: 'عبد الباسط',
      readerNamePath: 'Abdul_Basit_Murattal_192kbps',
      url: everyAyahSource,
    ),
    const ReaderInfo(
      index: 1,
      name: 'محمد المنشاوي',
      readerNamePath: 'Minshawy_Murattal_128kbps',
      url: everyAyahSource,
    ),
    const ReaderInfo(
      index: 2,
      name: 'محمود الحصري',
      readerNamePath: 'Husary_128kbps',
      url: everyAyahSource,
    ),
    const ReaderInfo(
      index: 3,
      name: 'أحمد العجمي',
      readerNamePath: '128/ar.ahmedajamy',
      url: islamicNetworkSource,
    ),
    const ReaderInfo(
      index: 4,
      name: 'ماهر المعيقلي',
      readerNamePath: 'MaherAlMuaiqly128kbps',
      url: everyAyahSource,
    ),
    const ReaderInfo(
      index: 5,
      name: 'سعود الشريم',
      readerNamePath: 'Saood_ash-Shuraym_128kbps',
      url: everyAyahSource,
    ),
    const ReaderInfo(
      index: 6,
      name: 'عبد الله الجهني',
      readerNamePath: 'Abdullaah_3awwaad_Al-Juhaynee_128kbps',
      url: everyAyahSource,
    ),
    const ReaderInfo(
      index: 7,
      name: 'فارس عباد',
      readerNamePath: 'Fares_Abbad_64kbps',
      url: everyAyahSource,
    ),
    const ReaderInfo(
      index: 8,
      name: 'محمد أيوب',
      readerNamePath: '128/ar.muhammadayyoub',
      url: islamicNetworkSource,
    ),
    const ReaderInfo(
      index: 9,
      name: 'ماهر المعيقلي - مجود',
      readerNamePath: 'MaherAlMuaiqly128kbps',
      url: everyAyahSource,
    ),
    const ReaderInfo(
      index: 10,
      name: 'ياسر الدوسري - مجود',
      readerNamePath: 'Yasser_Ad-Dussary_128kbps',
      url: everyAyahSource,
    ),
    const ReaderInfo(
      index: 11,
      name: 'علي جابر',
      readerNamePath: 'Ali_Jaber_64kbps',
      url: everyAyahSource,
    ),
  ];
}
