/// كشّاف أخطاء التجويد — مُطابق لِخادم quran-muaalem.
///
/// يُحاكي منطق `quran_transcript.phonetics.error_explainer.explain_error`:
/// لِكلّ عمليّة محاذاة جماعيّة، يُصنّف الخطأ وفق الفروع الخمسة للخادم:
///   1. `insert`  → normal/insert (حرف زائد)
///   2. `delete`  → tajweed إن كان لِلحرف قاعدة، وإلاّ normal
///   3. `replace` مَع قاعدة تجويد → tajweed/replace + ref/replaced rules + lens
///   4. `replace` بِلا قاعدة → normal/replace
///   5. `match`   → tajweed/replace (فرق مدّ أو match rule) أو tashkeel
library;

import 'package:quran_audio/src/recitation/models/recitation_result.dart';
import 'package:quran_audio/src/recitation/phoneme_aligner.dart';
import 'package:quran_audio/src/recitation/quran_phoneme_db.dart';

/// خريطة id → رمز عربي.
typedef PhonemeIdMap = Map<int, String>;

/// يبني أخطاء تجويد غنية من عمليّات المحاذاة الجماعيّة.
///
/// [ops] قائمة عمليّات المجموعات من alignGroups().
/// [referenceVerse] الآية المرجعيّة (لِـ قواعد التجويد + خريطة uthmani + النصّ).
/// [phonemeIdToToken] خريطة id → رمز (من vocab).
List<RecitationError> buildErrorsFromAlignment({
  required List<GroupAlignOp> ops,
  required ReferenceVerse referenceVerse,
  required PhonemeIdMap phonemeIdToToken,
}) {
  final errors = <RecitationError>[];

  for (final op in ops) {
    switch (op.type) {
      case 'match':
        _handleMatch(op, errors, referenceVerse, phonemeIdToToken);
        break;
      case 'insert':
        _handleInsert(op, errors, referenceVerse, phonemeIdToToken);
        break;
      case 'delete':
        _handleDelete(op, errors, referenceVerse, phonemeIdToToken);
        break;
      case 'replace':
        _handleReplace(op, errors, referenceVerse, phonemeIdToToken);
        break;
    }
  }

  return errors;
}

/// موضع عثمانيّ لِمجموعة مرجعيّة [start, end) من خريطة phonemeToUthmani.
List<int> _uthmaniPosForRefGroup(PhonemeGroup g, ReferenceVerse ref) {
  final pm = ref.phonemeToUthmani;
  if (pm.isEmpty) return const [0, 0];
  final start = pm[g.startIdx] ?? 0;
  final lastPh = g.endIdx - 1;
  final end = (pm[lastPh] ?? start) + 1;
  return [start, end];
}

/// يستخرج الكلمة العثمانيّة المحيطة بِموضع [start, end] (مثل النموذج).
///
/// يُستخدم لِعرض الكلمة المتأثّرة في بطاقة الخطأ.
String? _extractWord(String uthmani, List<int> pos) {
  if (pos.length < 2 || uthmani.isEmpty) return null;
  if (pos[0] == 0 && pos[1] == 0) return null; // insert zero-width
  final start = pos[0].clamp(0, uthmani.length).toInt();
  final end = pos[1].clamp(start, uthmani.length).toInt();
  int wordStart = start;
  while (wordStart > 0 && !_isSep(uthmani[wordStart - 1])) {
    wordStart--;
  }
  int wordEnd = end;
  while (wordEnd < uthmani.length && !_isSep(uthmani[wordEnd])) {
    wordEnd++;
  }
  final w = uthmani.substring(wordStart, wordEnd).trim();
  return w.isEmpty ? null : w;
}

bool _isSep(String ch) => ch == ' ' || ch == '\u0640';

/// موضع عثمانيّ تقريبيّ لِـ insert (مربوط بِأقرب مرجع).
List<int> _uthmaniPosForInsert(GroupAlignOp op, ReferenceVerse ref) {
  // insert ليس لَه refGroup — استخدم zero-width (مثل الخادم لِـ insert).
  return const [0, 0];
}

// ═══════════════════════ الفروع الخمسة (مثل explain_error) ═══════════════════════

/// فرع `match`: المجموعتان متطابقتان في baseId لكن قد تختلفان في الطول/الحركة.
void _handleMatch(
  GroupAlignOp op,
  List<RecitationError> errors,
  ReferenceVerse ref,
  PhonemeIdMap idToToken,
) {
  final refG = op.refGroup!;
  final predG = op.predGroup!;

  // إن كانتا متطابقتين تماماً (نفس الفونيمات) → لا خطأ (مثل الخادم: `...`).
  if (_groupsEqual(refG, predG)) return;

  final uthmaniPos = _uthmaniPosForRefGroup(refG, ref);
  final phPos = [predG.startIdx, predG.endIdx];
  final refRules = _refRulesForGroup(refG, ref);
  final word = _extractWord(ref.uthmani, uthmaniPos);

  if (refRules.isNotEmpty) {
    // فرع الخادم (line 367-411): لِكلّ قاعدة تجويد، تحقّق.
    for (final rule in refRules) {
      final ct = rule.correctnessType ?? '';
      if (ct == 'count') {
        // مدّ: قارن الطول (عدد الحركات).
        final expLen = rule.goldenLen ?? _maddLength(refG);
        final predLen = _maddLength(predG);
        if (expLen != predLen) {
          errors.add(RecitationError(
            errorType: 'tajweed',
            speechErrorType: 'replace',
            uthmaniPos: uthmaniPos,
            phPos: phPos,
            expectedPh: _groupToken(refG, idToToken),
            predictedPh: _groupToken(predG, idToToken),
            expectedLen: expLen,
            predictedLen: predLen,
            wordText: word,
            refTajweedRules: [rule],
          ));
        }
      } else if (ct == 'match') {
        // قاعدة bool (قلقلة/غُنّة): هل تطابقت؟
        // لا نملك معلومات كافية هنا على الـoffline لِلحكم، فنُخطّي (لا false
        // positive). الخادم يفحص بِـ taj_rule.match(ref_ph, pred_ph).
      }
    }
    // فرع الحركة الزائدة (line 400-411): إن انتهت المرجع بحركة واختلفت.
    if (harakatIds.contains(refG.lastId) && refG.lastId != predG.lastId) {
      final err = _tashkeelError(refG, predG, uthmaniPos, phPos, idToToken);
      errors.add(RecitationError(
        errorType: err.errorType,
        speechErrorType: err.speechErrorType,
        uthmaniPos: err.uthmaniPos,
        phPos: err.phPos,
        expectedPh: err.expectedPh,
        predictedPh: err.predictedPh,
        wordText: word,
      ));
    }
  } else if (harakatIds.contains(refG.lastId)) {
    // فرع الخادم (line 414-422): فرق في الحركة فقط → tashkeel.
    final err = _tashkeelError(refG, predG, uthmaniPos, phPos, idToToken);
    errors.add(RecitationError(
      errorType: err.errorType,
      speechErrorType: err.speechErrorType,
      uthmaniPos: err.uthmaniPos,
      phPos: err.phPos,
      expectedPh: err.expectedPh,
      predictedPh: err.predictedPh,
      wordText: word,
    ));
  } else {
    // فرع الخادم (line 429-445): حرف ساكن مختلف.
    // إن انتهى المتوقَّع بِحركة → tashkeel، وإلاّ → normal.
    final isTashkeel = harakatIds.contains(predG.lastId);
    errors.add(RecitationError(
      errorType: isTashkeel ? 'tashkeel' : 'normal',
      speechErrorType: 'insert', // مثل الخادم line 441
      uthmaniPos: uthmaniPos,
      phPos: phPos,
      expectedPh: _groupToken(refG, idToToken),
      predictedPh: _groupToken(predG, idToToken),
      wordText: word,
    ));
  }
}

/// فرع `insert`: حرف زائد.
void _handleInsert(
  GroupAlignOp op,
  List<RecitationError> errors,
  ReferenceVerse ref,
  PhonemeIdMap idToToken,
) {
  final predG = op.predGroup!;
  final uthmaniPos = _uthmaniPosForInsert(op, ref);
  final phPos = [predG.startIdx, predG.endIdx];
  // insert ليس لَه موضع مرجعيّ → wordText غير معروف (مثل الخادم).
  errors.add(RecitationError(
    errorType: 'normal', // مثل الخادم line 294
    speechErrorType: 'insert',
    uthmaniPos: uthmaniPos,
    phPos: phPos,
    expectedPh: '',
    predictedPh: _groupToken(predG, idToToken),
  ));
}

/// فرع `delete`: حرف مفقود.
void _handleDelete(
  GroupAlignOp op,
  List<RecitationError> errors,
  ReferenceVerse ref,
  PhonemeIdMap idToToken,
) {
  final refG = op.refGroup!;
  final uthmaniPos = _uthmaniPosForRefGroup(refG, ref);
  final phPos = [refG.startIdx, refG.endIdx];
  final word = _extractWord(ref.uthmani, uthmaniPos);
  // مثل الخادم line 359-361: tajweed إن كان لِلحرف قاعدة، وإلاّ normal.
  final refRules = _refRulesForGroup(refG, ref);
  final isTajweed = refRules.isNotEmpty;
  errors.add(RecitationError(
    errorType: isTajweed ? 'tajweed' : 'normal',
    speechErrorType: 'delete',
    uthmaniPos: uthmaniPos,
    phPos: phPos,
    expectedPh: _groupToken(refG, idToToken),
    predictedPh: '',
    wordText: word,
    refTajweedRules: isTajweed ? refRules : const [],
  ));
}

/// فرع `replace`: استبدال.
void _handleReplace(
  GroupAlignOp op,
  List<RecitationError> errors,
  ReferenceVerse ref,
  PhonemeIdMap idToToken,
) {
  final refG = op.refGroup!;
  final predG = op.predGroup!;
  final uthmaniPos = _uthmaniPosForRefGroup(refG, ref);
  final phPos = [predG.startIdx, predG.endIdx];
  final word = _extractWord(ref.uthmani, uthmaniPos);
  final refRules = _refRulesForGroup(refG, ref);

  if (refRules.isNotEmpty) {
    // فرع الخادم (line 301-339): لِكلّ قاعدة، tajweed/replace.
    for (final rule in refRules) {
      final ct = rule.correctnessType ?? '';
      int? expLen;
      int? predLen;
      if (ct == 'count') {
        expLen = rule.goldenLen ?? _maddLength(refG);
        predLen = _maddLength(predG);
      }
      errors.add(RecitationError(
        errorType: 'tajweed',
        speechErrorType: 'replace',
        uthmaniPos: uthmaniPos,
        phPos: phPos,
        expectedPh: _groupToken(refG, idToToken),
        predictedPh: _groupToken(predG, idToToken),
        expectedLen: expLen,
        predictedLen: predLen,
        wordText: word,
        refTajweedRules: [rule],
      ));
    }
  } else {
    // فرع الخادم (line 342-352): لا قاعدة → normal/replace.
    errors.add(RecitationError(
      errorType: 'normal',
      speechErrorType: 'replace',
      uthmaniPos: uthmaniPos,
      phPos: phPos,
      expectedPh: _groupToken(refG, idToToken),
      predictedPh: _groupToken(predG, idToToken),
      wordText: word,
    ));
  }
}

// ═══════════════════════ أدوات مساعدة ═══════════════════════

/// هل المجموعتان متطابقتان تماماً (نفس الفونيمات بنفس الترتيب)؟
bool _groupsEqual(PhonemeGroup a, PhonemeGroup b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a.ids[i] != b.ids[i]) return false;
  }
  return true;
}

/// يحوّل مجموعة إلى رمز نصّي (مثل "اا" أو "بِ").
///
/// ملاحظة: الأحرف الـ[PAD] تُستبدل بِـ '?' لِتسهيل القراءة.
String _groupToken(PhonemeGroup g, PhonemeIdMap idToToken) {
  return g.ids.map((id) => idToToken[id] ?? '?').join();
}

/// يحسب طول المدّ لِمجموعة، مُطابقاً `rule.count` الخادم.
///
/// الخادم: `pred_text.count(base)` — أي عدد تكرار الحرف الأساسيّ.
/// لِمجموعة مدّ (كلّ الفونيمات نفس baseId) = عدد الفونيمات.
/// لكن إن انتهت بِحركة، فلا تُحتسب في المدّ (مثل الخادم).
///
/// Count madd length matching the server's rule.count.
int _maddLength(PhonemeGroup g) {
  // إن انتهت المجموعة بِحركة مختلفة عن baseId، أسقطها من العدّ.
  if (g.length > 1 && harakatIds.contains(g.lastId) && g.lastId != g.baseId) {
    return g.length - 1;
  }
  return g.length;
}

/// يبني خطأ tashkeel (مثل `get_tasshkeel_error` الخادم).
///
/// `speech_error_type` يعتمد على الطول:
/// - pred أطول → insert
/// - pred أقصر → delete
/// - متساوٍ → replace
RecitationError _tashkeelError(
  PhonemeGroup refG,
  PhonemeGroup predG,
  List<int> uthmaniPos,
  List<int> phPos,
  PhonemeIdMap idToToken,
) {
  final String spTp;
  if (predG.length > refG.length) {
    spTp = 'insert';
  } else if (predG.length < refG.length) {
    spTp = 'delete';
  } else {
    spTp = 'replace';
  }
  return RecitationError(
    errorType: 'tashkeel',
    speechErrorType: spTp,
    uthmaniPos: uthmaniPos,
    phPos: phPos,
    expectedPh: _groupToken(refG, idToToken),
    predictedPh: _groupToken(predG, idToToken),
  );
}

/// يجمع قواعد التجويد المرجعيّة لِكلّ الفونيمات في مجموعة مرجعيّة.
///
/// مثل `get_ref_phonetic_groups_tajweed_rules` في الخادم: نجمع قواعد كلّ
/// الفونيمات في المجموعة (بِدون تكرار لِنفس موضع uthmani).
List<TajweedRule> _refRulesForGroup(PhonemeGroup g, ReferenceVerse ref) {
  final all = <TajweedRule>[];
  final tr = ref.tajweedRulesPerPhoneme;
  for (var i = g.startIdx; i < g.endIdx && i < tr.length; i++) {
    all.addAll(tr[i]);
  }
  // أزِل التكرار بِـ nameEn (مجموعة قد تمتدّ فونيمات متعدّدة لِنفس الحرف).
  final seen = <String>{};
  return all.where((r) {
    final key = r.nameEn;
    if (seen.contains(key)) return false;
    seen.add(key);
    return true;
  }).toList(growable: false);
}
