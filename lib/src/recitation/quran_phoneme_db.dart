/// قاعدة بيانات الفونيمات المرجعية لِكلّ القرآن (6207 آية).
///
/// تُحمَّل من `assets/models/quran_reference.json.gz` (1.4MB مضغوط).
/// لِكلّ آية (مُعرَّفة بِـ "sura:aya") تُوفّر:
/// - النصّ العثماني
/// - سلسلة فونيمات QPS
/// - معرّفات الفونيمات الرقمية (مطابقة لِـ vocab_official.json)
/// - 10 صفات تجويد لِكلّ فونيم (مُرمَّزة كَـ IDs)
///
/// تُولَّد بِـ scripts/12_generate_quran_db.py على Python (مرّة واحدة).
library;

import 'dart:convert';
import 'dart:developer' show log;
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// بيانات مرجعية لِآية واحدة.
class ReferenceVerse {
  ReferenceVerse({
    required this.verseKey,
    required this.uthmani,
    required this.phonemes,
    required this.phonemeIds,
    required this.sifat,
  });

  /// "sura:aya" مثل "1:1".
  final String verseKey;

  /// النصّ العثماني.
  final String uthmani;

  /// سلسلة فونيمات QPS.
  final String phonemes;

  /// معرّفات الفونيمات الرقمية (مطابقة لِـ vocab_official.json).
  final List<int> phonemeIds;

  /// 10 صفات تجويد لِكلّ فونيم. البنية: sifat[phonemeIndex][headIndex].
  /// headIndex: 0=hams_or_jahr, 1=shidda_or_rakhawa, ..., 9=ghonna.
  final List<List<int>> sifat;

  @override
  String toString() =>
      'ReferenceVerse($verseKey: $uthmani → ${phonemeIds.length} phonemes)';
}

/// قاعدة بيانات الفونيمات المرجعية لِكلّ القرآن.
class QuranPhonemeDb {
  QuranPhonemeDb();

  Map<String, dynamic> _db = {};
  bool _loaded = false;

  /// هل الـDB محمّلة؟
  bool get isLoaded => _loaded;

  /// عدد الآيات في الـDB.
  int get verseCount => _db.length;

  /// حمّل الـDB من asset أو من مسار خارجي.
  ///
  /// [assetPath] مسار asset (افتراضي: bundled).
  /// [filePath] مسار ملفّ خارجي (إن نُزِّل من Release).
  Future<void> load({String? assetPath, String? filePath}) async {
    if (_loaded) return;

    List<int> gzBytes;
    if (filePath != null && File(filePath).existsSync()) {
      log('QuranPhonemeDb: loading from file: $filePath', name: 'QuranDb');
      gzBytes = await File(filePath).readAsBytes();
    } else {
      final path = assetPath ?? 'assets/models/quran_reference.json.gz';
      log('QuranPhonemeDb: loading from asset: $path', name: 'QuranDb');
      final byteData = await rootBundle.load(path);
      gzBytes = byteData.buffer.asUint8List();
    }

    // فكّ gzip
    final decoded = gzip.decode(gzBytes);
    final jsonStr = utf8.decode(decoded);
    _db = jsonDecode(jsonStr) as Map<String, dynamic>;
    _loaded = true;
    log('QuranPhonemeDb: loaded ${_db.length} verses', name: 'QuranDb');
  }

  /// حمّل الـDB من ملفّ خارجي (بعد تنزيله من Release).
  Future<void> loadFromFile(String filePath) async {
    await load(filePath: filePath);
  }

  /// ابحث عن آية بِـ suraIdx و ayaIdx (1-based).
  ///
  /// يُعيد null إن لم تُوجد (مثل الحروف المقطّعة المفقودة).
  ReferenceVerse? getReference({required int suraIdx, required int ayaIdx}) {
    final key = '$suraIdx:$ayaIdx';
    return getReferenceByKey(key);
  }

  /// ابحث عن آية بِـ مفتاح "sura:aya".
  ReferenceVerse? getReferenceByKey(String verseKey) {
    final raw = _db[verseKey];
    if (raw == null) return null;
    final m = raw as Map<String, dynamic>;
    final phonemeIds = (m['pi'] as List).cast<int>();
    final sifatRaw = (m['s'] as List)
        .map((e) => (e as List).cast<int>())
        .toList(growable: false);

    // الفجوة 1: وسّع sifat لتطابق طول phonemeIds.
    // الـDB الأصليّ يُخزّن sifat كَـ صفّ لِكلّ حرف عثماني، لكنّ phonemeIds
    // كَـ صفّ لِكلّ فونيم (وبعض الحروف تُولّد فونيمات متعدّدة). نُوسّع
    // بِالتوزيع النسبي حتّى يطابق الطول.
    // Expand sifat to match phonemeIds length. The DB stores sifat per Uthmani
    // letter, but phonemeIds per phoneme (some letters generate multiple
    // phonemes). Expand by proportional distribution to match the length.
    final sifatExpanded = _expandSifatToPhonemes(sifatRaw, phonemeIds.length);

    return ReferenceVerse(
      verseKey: verseKey,
      uthmani: m['u'] as String,
      phonemes: m['p'] as String,
      phonemeIds: phonemeIds,
      sifat: sifatExpanded,
    );
  }

  /// يُوسّع قائمة sifat (عدد الحروف) لتطابق عدد الفونيمات بِالتوزيع النسبي.
  ///
  /// [sifat] صفوف sifat الأصليّة (واحد لِكلّ حرف عثماني).
  /// [targetLen] عدد الفونيمات المطلوب (طول phonemeIds).
  ///
  /// يُعيد قائمة بِطول targetLen، حيث يُكرّر كلّ صفّ حسب نسبة فونيماته.
  List<List<int>> _expandSifatToPhonemes(
    List<List<int>> sifat,
    int targetLen,
  ) {
    if (sifat.isEmpty || targetLen == 0) return sifat;
    if (sifat.length >= targetLen) return sifat.sublist(0, targetLen);

    // وزّع targetLen موضعاً على sifat.length صفّاً نسبيّاً.
    // Distribute targetLen positions across sifat.length rows proportionally.
    final result = <List<int>>[];
    final ratio = targetLen / sifat.length;
    for (var i = 0; i < sifat.length; i++) {
      // عدد الفونيمات لهذا الحرف ≈ ratio (مع التقريب).
      final count = (ratio * (i + 1)).round() - (ratio * i).round();
      final n = count < 1 ? 1 : count;
      for (var j = 0; j < n && result.length < targetLen; j++) {
        result.add(sifat[i]);
      }
    }
    // إن نقص (بسبب التقريب)، املأ بِآخر صفّ.
    while (result.length < targetLen) {
      result.add(sifat.last);
    }
    return result;
  }

  /// هل الآية موجودة في الـDB؟
  bool hasVerse({required int suraIdx, required int ayaIdx}) {
    return _db.containsKey('$suraIdx:$ayaIdx');
  }

  /// حرّر الذاكرة.
  void dispose() {
    _db = {};
    _loaded = false;
  }
}
