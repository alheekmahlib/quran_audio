import 'dart:convert';
import 'dart:developer' show log;
import 'dart:io' show gzip;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../constants/quran_constants.dart';
import 'models/surah_meta.dart';

/// سجل موحد لنتيجة (سورة + آية ضمن السورة).
///
/// Unified record for (surah number, ayah-in-surah).
typedef SurahAyah = ({int surah, int ayahInSurah});

/// محمّل ومخدِّم بيانات السور الوصفية للقرآن الكريم.
///
/// يحمّل ملف JSON صغير جداً (~3KB) يحتوي على أرقام السور وأسمائها وعدد آيات كل سورة.
/// يحسب الأرقام الفريدة للآيات (UQ 1..6236) بالجمع التراكمي — فلا حاجة لتخزينها.
///
/// Loads a tiny JSON (~3KB) holding surah numbers, names, and ayah counts.
/// Computes ayah unique numbers (UQ 1..6236) cumulatively — no need to store them.
class QuranMetadata {
  QuranMetadata._();
  static final QuranMetadata instance = QuranMetadata._();

  final List<SurahMeta> _surahs = [];

  /// مجموع أعداد الآيات التراكمي — `_cumStart[i]` = أول UQ للسورة `i+1`.
  /// `_cumStart[0]` = 1 (أول آية في القرآن).
  final List<int> _cumStart = [];

  bool _loaded = false;

  /// هل تم تحميل البيانات؟ / Has metadata been loaded?
  bool get isLoaded => _loaded;

  /// عدد السور الكلي / Total number of surahs.
  int get totalSurahs => _surahs.length;

  /// حمّل بيانات السور من الـ asset المضغوط.
  ///
  /// Loads surah metadata from the gzipped asset.
  Future<void> load() async {
    if (_loaded) return;

    try {
      // rootBundle.load تُعيد ByteData — حوّله إلى Uint8List لفك ضغط gzip
      final byteData =
          await rootBundle.load(QuranConstants.metadataAssetPath);
      final bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes, byteData.lengthInBytes);

      // فك ضغط gzip / decompress gzip
      final decoded = gzip.decode(bytes);
      final jsonStr = utf8.decode(decoded);
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final list = data['surahs'] as List<dynamic>;

      _surahs
        ..clear()
        ..addAll(list
            .map((e) => SurahMeta.fromJson(e as Map<String, dynamic>)));

      // احسب البدايات التراكمية للأرقام الفريدة
      // Compute cumulative UQ starts
      _cumStart.clear();
      int running = 1; // أول آية فريدة = 1
      for (final s in _surahs) {
        _cumStart.add(running);
        running += s.ayahCount;
      }

      _loaded = true;
      log('QuranMetadata loaded: ${_surahs.length} surahs, '
          'total ayahs = $totalAyahs',
          name: 'QuranMetadata');
    } catch (e, s) {
      log('Failed to load QuranMetadata: $e',
          name: 'QuranMetadata', stackTrace: s, error: e);
      rethrow;
    }
  }

  /// إجمالي عدد الآيات / Total number of ayahs (6236).
  int get totalAyahs {
    if (_surahs.isEmpty) return QuranConstants.totalAyahs;
    return _surahs.fold(0, (sum, s) => sum + s.ayahCount);
  }

  /// تحقق من صحة رقم السورة / Validate a surah number (1..114).
  bool isValidSurah(int surahNumber) =>
      surahNumber >= QuranConstants.firstSurah &&
      surahNumber <= QuranConstants.lastSurah;

  /// تحقق من صحة (سورة، آية) / Validate a (surah, ayahInSurah) pair.
  bool isValidAyah(int surahNumber, int ayahInSurah) {
    if (!isValidSurah(surahNumber)) return false;
    if (ayahInSurah < 1) return false;
    return ayahInSurah <= ayahCountOf(surahNumber);
  }

  /// بيانات السورة بالرقم / Get surah metadata by number (1..114).
  SurahMeta surah(int surahNumber) {
    _ensureLoaded();
    if (!isValidSurah(surahNumber)) {
      throw RangeError('Surah number must be 1..114, got $surahNumber');
    }
    return _surahs[surahNumber - 1];
  }

  /// كل السور / All surahs.
  List<SurahMeta> get allSurahs {
    _ensureLoaded();
    return List.unmodifiable(_surahs);
  }

  /// عدد آيات سورة معيّنة / Ayah count of a surah.
  int ayahCountOf(int surahNumber) {
    return surah(surahNumber).ayahCount;
  }

  /// أول رقم فريد لآية في السورة / First ayah UQ number in a surah.
  ///
  /// مثال: السورة 1 → 1، السورة 2 → 8، السورة 3 → 294.
  int firstAyahUqOf(int surahNumber) {
    _ensureLoaded();
    if (!isValidSurah(surahNumber)) {
      throw RangeError('Surah number must be 1..114, got $surahNumber');
    }
    return _cumStart[surahNumber - 1];
  }

  /// آخر رقم فريد لآية في السورة / Last ayah UQ number in a surah.
  int lastAyahUqOf(int surahNumber) {
    _ensureLoaded();
    if (!isValidSurah(surahNumber)) {
      throw RangeError('Surah number must be 1..114, got $surahNumber');
    }
    final idx = surahNumber - 1;
    return _cumStart[idx] + _surahs[idx].ayahCount - 1;
  }

  /// الرقم الفريد لآية محددة / UQ number for a specific ayah.
  ///
  /// [surahNumber] - رقم السورة (1..114).
  /// [ayahInSurah] - رقم الآية ضمن السورة (1..ayahCount).
  int uqNumberOf(int surahNumber, int ayahInSurah) {
    _ensureLoaded();
    if (!isValidAyah(surahNumber, ayahInSurah)) {
      throw RangeError(
          'Invalid (surah:$surahNumber, ayah:$ayahInSurah)');
    }
    return _cumStart[surahNumber - 1] + (ayahInSurah - 1);
  }

  /// عكسي: من الرقم الفريد إلى (سورة، آية) / Reverse: UQ → (surah, ayahInSurah).
  SurahAyah surahAyahOfUq(int uqNumber) {
    _ensureLoaded();
    if (uqNumber < QuranConstants.firstAyahUq ||
        uqNumber > QuranConstants.lastAyahUq) {
      throw RangeError('UQ must be 1..6236, got $uqNumber');
    }

    // بحث ثنائي في `_cumStart` للعثور على السورة / binary search
    int lo = 0, hi = _cumStart.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_cumStart[mid] <= uqNumber) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final surah = lo + 1; // رقم السورة
    final ayahInSurah = uqNumber - _cumStart[lo] + 1;
    return (surah: surah, ayahInSurah: ayahInSurah);
  }

  /// هل هي آخر آية في السورة؟ / Is this the last ayah in the surah?
  bool isLastAyahInSurah(int surahNumber, int ayahInSurah) {
    return ayahInSurah >= ayahCountOf(surahNumber);
  }

  /// هل هي أول آية في السورة؟ / Is this the first ayah in the surah?
  bool isFirstAyahInSurah(int surahNumber, int ayahInSurah) {
    return ayahInSurah <= 1;
  }

  void _ensureLoaded() {
    if (!_loaded) {
      throw StateError(
          'QuranMetadata not loaded. Call QuranMetadata.instance.load() first.');
    }
  }

  /// مسار ملف الـ metadata المحلي على القرص (لاستخدامه في الاختبارات/التصدير).
  ///
  /// Local filesystem path to the metadata file (for tests/exports).
  Future<String> localFilePath(String docsDir) async {
    return p.join(docsDir, 'surah_metadata.json');
  }
}
