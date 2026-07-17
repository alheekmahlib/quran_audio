/// كشّاف أخطاء التجويد من عمليّات المحاذاة.
///
/// الطبقة 3 من خطّة مقارنة التجويد.
///
/// يحوّل قائمة AlignOp (من phoneme_aligner) + صفات التجويد إلى
/// RecitationError[] (النموذج المستخدَم في quran_audio).
library;

import 'package:quran_audio/src/recitation/models/recitation_result.dart';
import 'package:quran_audio/src/recitation/phoneme_aligner.dart';
import 'package:quran_audio/src/recitation/quran_phoneme_db.dart';

/// أسماء رؤوس الصفات الـ10 (بِالترتيب المُستخدَم في sifat[][]).
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

/// أسماء الصفات بالعربية (لِعرضها في TajweedRule.nameAr).
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

/// معرّفات الفونيمات → رموز عربية (لِـ expectedPh/predictedPh).
/// نُمرّر هذا كَـ معامل لأنّ المُعرّف يأتي من vocab_official.json.
typedef PhonemeIdMap = Map<int, String>;

/// يبني أخطاء التجويد من عمليّات المحاذاة + الصفات.
///
/// [ops] قائمة العمليّات من alignPhonemes().
/// [sifatPerPhoneme] صفات كلّ فونيم متوقَّع (من النموذج).
/// [referenceVerse] الآية المرجعية (لِـ sifat المرجعية + النصّ).
/// [phonemeIdToToken] خريطة id → رمز (من vocab).
List<RecitationError> buildErrorsFromAlignment({
  required List<AlignOp> ops,
  required List<List<int>> sifatPerPhoneme,
  required ReferenceVerse referenceVerse,
  required PhonemeIdMap phonemeIdToToken,
}) {
  final errors = <RecitationError>[];

  for (final op in ops) {
    if (op.type == 'match') continue; // لا خطأ

    // خريطة رمز الفونيم (لِـ expectedPh/predictedPh)
    final expectedPh = op.refId != null
        ? (phonemeIdToToken[op.refId] ?? '?')
        : null;
    final predictedPh = op.predId != null
        ? (phonemeIdToToken[op.predId] ?? '?')
        : null;

    // صفات الفونيم المتوقَّع (لِكشف نوع الخطأ)
    List<int>? predSifat;
    if (op.predIdx < sifatPerPhoneme.length) {
      predSifat = sifatPerPhoneme[op.predIdx];
    }

    // صفات الفونيم المرجعي
    List<int>? refSifat;
    if (op.refIdx < referenceVerse.sifat.length) {
      refSifat = referenceVerse.sifat[op.refIdx];
    }

    // حدّد نوع الخطأ: تجويد أم نطق عادي.
    // إن كان الفونيم متطابقاً (نفس id) لكنّ صفاته مختلفة → تجويد.
    // إن كان الفونيم مختلفاً → نطق.
    final isTajweedError = op.type == 'replace' &&
        op.refId == op.predId &&
        _sifatDiffers(refSifat, predSifat);

    final errorType = isTajweedError ? 'tajweed' : 'normal';
    final speechType = op.type; // 'insert'/'delete'/'replace'

    // ابنِ TajweedRule للصفات المختلفة (إن وُجدت)
    final tajweedRules = <TajweedRule>[];
    if (isTajweedError && refSifat != null && predSifat != null) {
      for (var h = 0; h < _sifatHeadNames.length; h++) {
        if (h >= refSifat.length || h >= predSifat.length) break;
        if (refSifat[h] != predSifat[h] && refSifat[h] != 0) {
          // الصفة المرجعية غير صفر (PAD) ومختلفة
          final headName = _sifatHeadNames[h];
          tajweedRules.add(TajweedRule(
            nameAr: _sifatNameAr[headName] ?? headName,
            nameEn: headName,
            correctnessType: 'sifa',
          ));
        }
      }
    }

    // للمدود: عدّ تكرار الفونيم (إذا كان حرف مدّ)
    int? expectedLen;
    int? predictedLen;
    if (op.type == 'delete' || op.type == 'replace') {
      expectedLen = _countRunLength(referenceVerse.phonemeIds, op.refIdx);
    }
    if (op.type == 'insert' || op.type == 'replace') {
      if (op.predIdx < sifatPerPhoneme.length) {
        // عدّ من predicted (نُمرّر قائمة المعرّفات المتوقَّعة)
        // نُعالج هذا في المعالجة الخارجية — هنا نضع 1 كَـ placeholder
        predictedLen = 1;
      }
    }

    errors.add(RecitationError(
      errorType: errorType,
      speechErrorType: speechType,
      phPos: [op.predIdx, op.predIdx + 1],
      expectedPh: expectedPh,
      predictedPh: predictedPh,
      expectedLen: expectedLen,
      predictedLen: predictedLen,
      refTajweedRules: tajweedRules,
    ));
  }

  return errors;
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

/// يعدّ طول سلسلة الفونيمات المتكرّرة (لِـ المدود).
///
/// مثلاً: [29, 29, 29, 5] عند idx=0 → يُعيد 3 (ثلاثة "ا").
int _countRunLength(List<int> ids, int idx) {
  if (idx < 0 || idx >= ids.length) return 1;
  final target = ids[idx];
  int count = 1;
  // عدّ لِلأمام
  for (var i = idx + 1; i < ids.length && ids[i] == target; i++) {
    count++;
  }
  return count;
}
