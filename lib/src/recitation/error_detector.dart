/// كشّاف أخطاء التجويد المُحسَّن (Group-Based).
///
/// الطبقة 3 المُحسَّنة: تستخدم عمليّات المحاذاة الجماعيّة (GroupAlignOp)
/// لِكشف الأخطاء بِشكل يُطابق خادم quran-muaalem.
///
/// يُصنّف الأخطاء إلى:
/// - **tajweed (count)**: خطأ في طول المدّ (مثلاً مدّ 2 بدل 4).
/// - **tajweed (sifa)**: خطأ في صفة الحرف (تفخيم/قلقلة/غُنّة).
/// - **normal**: خطأ في الحرف نفسه (استبدال حرف بِآخر).
/// - **tashkeel**: خطأ في الحركة (فتحة/ضمّة/كسرة).
library;

import 'package:quran_audio/src/recitation/models/recitation_result.dart';
import 'package:quran_audio/src/recitation/phoneme_aligner.dart';
import 'package:quran_audio/src/recitation/quran_phoneme_db.dart';

/// أسماء رؤوس الصفات الـ10.
const _sifatHeadNames = [
  'hams_or_jahr',
  'shidda_or_rakhawa',
  'tafkheem_or_taqeeq',
  'itbaq',
  'safeer',
  'qalqla',
  'tikraar',
  'tafashie',
  'istitala',
  'ghonna',
];

/// أسماء الصفات بالعربية.
const _sifatNameAr = {
  'hams_or_jahr': 'الهمس والجهر',
  'shidda_or_rakhawa': 'الشدّة والرخاوة',
  'tafkheem_or_taqeeq': 'التفخيم والترقيق',
  'itbaq': 'الإطباق',
  'safeer': 'الصفير',
  'qalqla': 'القلقلة',
  'tikraar': 'التكرار (الراء)',
  'tafashie': 'التفشّي',
  'istitala': 'الاستطالة (الضاد)',
  'ghonna': 'الغُنّة',
};

/// معرّفات الحركات (فتحة/ضمّة/كسرة/sukun) — من vocab_official.json.
const _harakatIds = {32, 33, 34, 36, 35}; // َ ُ ِ ـ ۪

/// خريطة id → رمز عربي (لِـ expectedPh/predictedPh).
typedef PhonemeIdMap = Map<int, String>;

/// يبني أخطاء تجويد غنية من عمليّات المحاذاة الجماعيّة.
///
/// [ops] قائمة عمليّات المجموعات من alignGroups().
/// [sifatPerPhoneme] صفات كلّ فونيم متوقَّع (من النموذج، مفهرّس بِـ predIdx).
/// [referenceVerse] الآية المرجعيّة (لِـ sifat المرجعية + النصّ).
/// [phonemeIdToToken] خريطة id → رمز (من vocab).
List<RecitationError> buildErrorsFromAlignment({
  required List<GroupAlignOp> ops,
  required List<List<int>> sifatPerPhoneme,
  required ReferenceVerse referenceVerse,
  required PhonemeIdMap phonemeIdToToken,
}) {
  final errors = <RecitationError>[];

  for (final op in ops) {
    if (op.type == 'match') {
      // حتى في التطابق، قد يختلف طول المدّ أو الصفة
      _checkMatchErrors(op, errors, sifatPerPhoneme, referenceVerse,
          phonemeIdToToken);
      continue;
    }

    // إدراج: حرف زائد
    if (op.type == 'insert') {
      final predId = op.predGroup!.baseId;
      errors.add(RecitationError(
        errorType: _harakatIds.contains(predId) ? 'tashkeel' : 'normal',
        speechErrorType: 'insert',
        phPos: [op.predGroup!.startIdx, op.predGroup!.endIdx],
        predictedPh: phonemeIdToToken[predId],
      ));
      continue;
    }

    // حذف: حرف مفقود
    if (op.type == 'delete') {
      final refId = op.refGroup!.baseId;
      errors.add(RecitationError(
        errorType: _harakatIds.contains(refId) ? 'tashkeel' : 'normal',
        speechErrorType: 'delete',
        phPos: [op.refGroup!.startIdx, op.refGroup!.endIdx],
        expectedPh: phonemeIdToToken[refId],
      ));
      continue;
    }

    // استبدال: حرف مختلف
    if (op.type == 'replace') {
      _checkReplaceError(op, errors, sifatPerPhoneme, referenceVerse,
          phonemeIdToToken);
    }
  }

  return errors;
}

/// يفحص مجموعة متطابقة (match) لِكشف أخطاء المدود والصفات.
void _checkMatchErrors(
  GroupAlignOp op,
  List<RecitationError> errors,
  List<List<int>> sifatPerPhoneme,
  ReferenceVerse referenceVerse,
  PhonemeIdMap phonemeIdToToken,
) {
  final refG = op.refGroup!;
  final predG = op.predGroup!;

  // 1) خطأ في طول المدّ
  if (refG.isMadd || predG.isMadd) {
    if (refG.length != predG.length) {
      errors.add(RecitationError(
        errorType: 'tajweed',
        speechErrorType: 'replace',
        phPos: [predG.startIdx, predG.endIdx],
        expectedPh: phonemeIdToToken[refG.baseId],
        predictedPh: phonemeIdToToken[predG.baseId],
        expectedLen: refG.length,
        predictedLen: predG.length,
        refTajweedRules: [
          TajweedRule(
            nameAr: 'مدّ',
            nameEn: 'madd',
            goldenLen: refG.length,
            correctnessType: 'count',
          ),
        ],
      ));
      return; // خطأ مدّ مُكتشف، لا حاجة لِفحص الصفات
    }
  }

  // 2) خطأ في الصفات (إن كانت المجموعة في المرجع)
  if (refG.startIdx < referenceVerse.sifat.length) {
    final refSifat = referenceVerse.sifat[refG.startIdx];
    final predIdx = predG.startIdx;
    if (predIdx < sifatPerPhoneme.length) {
      final predSifat = sifatPerPhoneme[predIdx];
      _checkSifatDiff(
        refSifat: refSifat,
        predSifat: predSifat,
        phPos: [predG.startIdx, predG.endIdx],
        errors: errors,
      );
    }
  }
}

/// يفحص مجموعة مستبدلة (replace) لِتصنيف الخطأ بدقّة.
void _checkReplaceError(
  GroupAlignOp op,
  List<RecitationError> errors,
  List<List<int>> sifatPerPhoneme,
  ReferenceVerse referenceVerse,
  PhonemeIdMap phonemeIdToToken,
) {
  final refG = op.refGroup!;
  final predG = op.predGroup!;
  final refId = refG.baseId;
  final predId = predG.baseId;

  // هل الفرق في الحركة فقط (tashkeel)؟
  final refIsHaraka = _harakatIds.contains(refId);
  final predIsHaraka = _harakatIds.contains(predId);
  if (refIsHaraka || predIsHaraka) {
    errors.add(RecitationError(
      errorType: 'tashkeel',
      speechErrorType: 'replace',
      phPos: [predG.startIdx, predG.endIdx],
      expectedPh: phonemeIdToToken[refId],
      predictedPh: phonemeIdToToken[predId],
    ));
    return;
  }

  // هل الفرق في الحرف نفسه لكنّ الصفات مختلفة (tajweed/sifa)؟
  // هذا يحدث نادراً في الاستبدال، لكنّه ممكن (مثلاً تاء بدل طاء).
  if (refG.startIdx < referenceVerse.sifat.length &&
      predG.startIdx < sifatPerPhoneme.length) {
    final refSifat = referenceVerse.sifat[refG.startIdx];
    final predSifat = sifatPerPhoneme[predG.startIdx];
    if (_sifatDiffers(refSifat, predSifat)) {
      _checkSifatDiff(
        refSifat: refSifat,
        predSifat: predSifat,
        phPos: [predG.startIdx, predG.endIdx],
        errors: errors,
        expectedPh: phonemeIdToToken[refId],
        predictedPh: phonemeIdToToken[predId],
      );
      return;
    }
  }

  // خلاف ذلك: خطأ نطق عاديّ (حرف مختلف)
  errors.add(RecitationError(
    errorType: 'normal',
    speechErrorType: 'replace',
    phPos: [predG.startIdx, predG.endIdx],
    expectedPh: phonemeIdToToken[refId],
    predictedPh: phonemeIdToToken[predId],
  ));
}

/// يفحص اختلاف الصفات ويُضيف أخطاءً لِكلّ صفة مختلفة.
void _checkSifatDiff({
  required List<int> refSifat,
  required List<int> predSifat,
  required List<int> phPos,
  required List<RecitationError> errors,
  String? expectedPh,
  String? predictedPh,
}) {
  for (var h = 0; h < _sifatHeadNames.length; h++) {
    if (h >= refSifat.length || h >= predSifat.length) break;
    if (refSifat[h] != predSifat[h] && refSifat[h] != 0) {
      final headName = _sifatHeadNames[h];
      errors.add(RecitationError(
        errorType: 'tajweed',
        speechErrorType: 'replace',
        phPos: phPos,
        expectedPh: expectedPh,
        predictedPh: predictedPh,
        refTajweedRules: [
          TajweedRule(
            nameAr: _sifatNameAr[headName] ?? headName,
            nameEn: headName,
            correctnessType: 'sifa',
          ),
        ],
      ));
    }
  }
}

/// هل تختلف الصفات بين مرجعي ومتوقَّع؟
bool _sifatDiffers(List<int>? ref, List<int>? pred) {
  if (ref == null || pred == null) return false;
  final len = ref.length < pred.length ? ref.length : pred.length;
  for (var i = 0; i < len; i++) {
    if (ref[i] != pred[i] && ref[i] != 0) return true;
  }
  return false;
}
