/// قاعدة بيانات الفونيمات المرجعية لِكلّ القرآن.
///
/// تُحمَّل من `assets/models/quran_reference.json.gz`. لِكلّ آية تُوفّر:
/// - `u`: النصّ العثماني
/// - `p`: سلسلة فونيمات QPS
/// - `pi`: معرّفات الفونيمات الرقمية
/// - `s`: 10 صفات تجويد لِكلّ **مجموعة فونيمات** (وليس لِكلّ فونيم)
/// - `tr`: قواعد تجويد غنية لِكلّ فونيم (Madd/Qalqalah/Ghonnah + golden_len)
/// - `pm`: خريطة phonemeIdx → uthmaniCharIdx (لِـ استخراج wordText)
///
/// تُولَّد بِـ scripts/12_generate_quran_db.py على Python (مرّة واحدة).
library;

import 'dart:convert';
import 'dart:developer' show log;
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'models/recitation_result.dart' show TajweedRule;

/// بيانات مرجعية لِآية واحدة.
class ReferenceVerse {
  ReferenceVerse({
    required this.verseKey,
    required this.uthmani,
    required this.phonemes,
    required this.phonemeIds,
    required this.sifat,
    required this.tajweedRulesPerPhoneme,
    required this.phonemeToUthmani,
  });

  /// "sura:aya" مثل "1:1".
  final String verseKey;

  /// النصّ العثماني.
  final String uthmani;

  /// سلسلة فونيمات QPS.
  final String phonemes;

  /// معرّفات الفونيمات الرقمية (مطابقة لِـ vocab_official.json).
  final List<int> phonemeIds;

  /// 10 صفات تجويد لِكلّ **مجموعة** فونيمات. البنية: sifat[groupIdx][headIdx].
  /// headIndex: 0=hams_or_jahr, 1=shidda_or_rakhawa, ..., 9=ghonna.
  /// ملاحظة: طول هذه القائمة = عدد المجموعات (أقلّ من phonemeIds).
  final List<List<int>> sifat;

  /// قواعد تجويد غنية لِكلّ **فونيم**. البنية: tr[phonemeIdx] = List<TajweedRule>.
  /// طول هذه القائمة = طول phonemeIds.
  final List<List<TajweedRule>> tajweedRulesPerPhoneme;

  /// خريطة phonemeIdx → uthmaniCharIdx. تُستخدم لِـ استخراج wordText.
  final Map<int, int> phonemeToUthmani;

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

    // قواعد التجويد لِكلّ فونيم (إن وُجدت في الـDB).
    final trRaw = m['tr'] as List?;
    List<List<TajweedRule>> tajweedRules;
    if (trRaw != null) {
      tajweedRules = trRaw.map(_parseRules).toList(growable: false);
    } else {
      // DB قديم بِلا tr — أعِد قائمة فارغة لِكلّ فونيم.
      tajweedRules = List.generate(phonemeIds.length, (_) => const <TajweedRule>[]);
    }

    // خريطة phonemeIdx → uthmaniCharIdx (إن وُجدت في الـDB).
    final pmRaw = m['pm'];
    Map<int, int> phonemeToUthmani;
    if (pmRaw is Map) {
      phonemeToUthmani = {
        for (final e in pmRaw.entries) int.parse(e.key): (e.value as num).toInt(),
      };
    } else {
      phonemeToUthmani = const {};
    }

    return ReferenceVerse(
      verseKey: verseKey,
      uthmani: m['u'] as String,
      phonemes: m['p'] as String,
      phonemeIds: phonemeIds,
      sifat: sifatRaw,
      tajweedRulesPerPhoneme: tajweedRules,
      phonemeToUthmani: phonemeToUthmani,
    );
  }

  /// يحوّل قواعد JSON إلى TajweedRule dart.
  static List<TajweedRule> _parseRules(dynamic rulesList) {
    if (rulesList is! List || rulesList.isEmpty) return const [];
    return rulesList.whereType<Map>().map((m) {
      final mm = Map<String, dynamic>.from(m);
      return TajweedRule(
        nameAr: (mm['ar'] as String?) ?? '',
        nameEn: (mm['en'] as String?) ?? '',
        goldenLen: (mm['g'] as num?)?.toInt(),
        correctnessType: mm['ct'] as String?,
        tag: mm['tag'] as String?,
      );
    }).toList(growable: false);
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
