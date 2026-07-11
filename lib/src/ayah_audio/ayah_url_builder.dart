import 'package:path/path.dart' as p;

import '../shared/models/reader_info.dart';
import '../shared/quran_metadata.dart';
import 'ayah_readers.dart';

/// بنّاء روابط وأسماء ملفات الآيات — يدعم التنسيقين المختلفين حسب المصدر.
///
/// Builder for ayah audio URLs and local file names — supports both source
/// formats.
///
/// تنسيقان:
/// - **islamic.network**: اسم الملف = الرقم الفريد للآية (يُحسب عبر [QuranMetadata]).
///   مثال: `128/ar.ahmedajamy/255.mp3`
/// - **everyayah.com**: اسم الملف = رقم السورة (3) + رقم الآية (3).
///   مثال: `Husary_128kbps/002255.mp3`
class AyahUrlBuilder {
  AyahUrlBuilder._();

  /// هل يستخدم القارئ مصدر islamic.network؟ / Does the reader use islamic.network?
  static bool isIslamicNetwork(ReaderInfo reader) =>
      reader.url == AyahReaders.islamicNetworkSource;

  /// اسم الملف النسبي للآية (نسب لمجلد القارئ) / Relative file name for the ayah.
  ///
  /// [surahNumber] - رقم السورة (1..114).
  /// [ayahInSurah] - رقم الآية ضمن السورة.
  /// [reader] - معلومات القارئ.
  static String fileName({
    required int surahNumber,
    required int ayahInSurah,
    required ReaderInfo reader,
  }) {
    final String ayahFile;
    if (isIslamicNetwork(reader)) {
      // المصدر الأول: الرقم الفريد للآية (يُحسب تراكمياً)
      final uq = QuranMetadata.instance.uqNumberOf(surahNumber, ayahInSurah);
      ayahFile = '$uq.mp3';
    } else {
      // المصدر الثاني: رقم السورة + رقم الآية (SSSAAA)
      final s = surahNumber.toString().padLeft(3, '0');
      final a = ayahInSurah.toString().padLeft(3, '0');
      ayahFile = '$s$a.mp3';
    }
    return p.join(reader.readerNamePath, ayahFile);
  }

  /// ابنِ رابط الآية الكامل / Build the full ayah audio URL.
  static String url({
    required int surahNumber,
    required int ayahInSurah,
    required ReaderInfo reader,
  }) {
    return '${reader.url}${fileName(
      surahNumber: surahNumber,
      ayahInSurah: ayahInSurah,
      reader: reader,
    )}';
  }

  /// المسار المحلي الكامل للآية / Full local filesystem path.
  static String localPath({
    required String docsDir,
    required int surahNumber,
    required int ayahInSurah,
    required ReaderInfo reader,
  }) {
    return p.join(docsDir,
        fileName(surahNumber: surahNumber, ayahInSurah: ayahInSurah, reader: reader));
  }
}
