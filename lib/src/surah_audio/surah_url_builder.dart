import 'package:path/path.dart' as p;

import '../shared/models/reader_info.dart';

/// بنّاء روابط وأسماء ملفات السور.
///
/// Builder for surah audio URLs and local file names.
///
/// تنسيق الرابط: `${reader.url}${reader.readerNamePath}${NNN}.mp3`
/// حيث NNN = رقم السورة مبطّن إلى 3 أرقام (مثل 002 للبقرة).
class SurahUrlBuilder {
  SurahUrlBuilder._();

  /// ابنِ رابط السورة الكامل / Build the full surah audio URL.
  ///
  /// [surahNumber] - رقم السورة (1..114).
  /// [reader] - معلومات القارئ.
  static String url({
    required int surahNumber,
    required ReaderInfo reader,
  }) {
    final surahPart = surahNumber.toString().padLeft(3, '0');
    return '${reader.url}${reader.readerNamePath}$surahPart.mp3';
  }

  /// اسم الملف المحلي للسورة (نسب لمجلد القارئ) / Local file name for the surah.
  ///
  /// النتيجة مثل `mahmood_khaleel_al-husaree_iza3a/002.mp3`.
  static String fileName({
    required int surahNumber,
    required ReaderInfo reader,
  }) {
    final surahPart = surahNumber.toString().padLeft(3, '0');
    return p.join(reader.readerNamePath, '$surahPart.mp3');
  }

  /// المسار المحلي الكامل للسورة / Full local filesystem path.
  ///
  /// [docsDir] - مجلد التخزين (getApplicationDocumentsDirectory).
  static String localPath({
    required String docsDir,
    required int surahNumber,
    required ReaderInfo reader,
  }) {
    return p.join(docsDir, fileName(surahNumber: surahNumber, reader: reader));
  }
}
