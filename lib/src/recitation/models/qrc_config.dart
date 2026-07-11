import 'qrc_method.dart';

/// إعدادات بدء جلسة تسميع (payload لِـ `StartTilawaSession`).
///
/// Configuration to start a recitation session (the `StartTilawaSession` payload).
///
/// الحقول تطابق ما ورد في مثال qurani.ai JS. النطاقات والدلالات الدقيقة
/// لبعض الحقول غير موثّقة (مُعلَّمة بِـ TODO) — استخدم القيم الافتراضية ثم
/// اضبطها تجريبياً عند الحصول على API key.
///
/// Fields match the qurani.ai JS example. Exact ranges/semantics for some
/// fields are undocumented (marked TODO) — use defaults, then calibrate
/// empirically once you have an API key.
class QrcConfig {
  /// رقم السورة (1..114).
  ///
  /// ⚠️ TODO: لم تُوثّق qurani.ai ما إذا كان 0-based أم 1-based. الافتراض 1-based
  /// (مطابق لِلاتفاق القرآني). تحقّق عند الاختبار.
  ///
  /// ⚠️ TODO: qurani.ai doesn't state 0-based vs 1-based. Assumed 1-based
  /// (matching Quran convention). Verify during testing.
  final int chapterIndex;

  /// رقم الآية ضمن السورة (1..ayahCount).
  /// Verse index within the surah (1..ayahCount).
  final int verseIndex;

  /// رقم الكلمة الابتدائية ضمن الآية (الافتراضي 1).
  /// Starting word index within the verse (default 1).
  final int wordIndex;

  /// مستوى الحفظ — يضبط توقّعات النموذج حسب مستوى الحافظ.
  ///
  /// ⚠️ TODO: النطاق المسموح غير موثّق. الافتراضي 1.
  ///
  /// ⚠️ TODO: allowed range is undocumented. Default 1.
  final int hafzLevel;

  /// مستوى صرامة فحص التجويد.
  ///
  /// ⚠️ TODO: النطاق المسموح غير موثّق. الافتراضي 1.
  ///
  /// ⚠️ TODO: allowed range is undocumented. Default 1.
  final int tajweedLevel;

  const QrcConfig({
    required this.chapterIndex,
    required this.verseIndex,
    this.wordIndex = 1,
    this.hafzLevel = 1,
    this.tajweedLevel = 1,
  });

  /// ابنِ payload رسالة بدء الجلسة كما تتوقّعها qurani.ai.
  /// Build the StartTilawaSession payload expected by qurani.ai.
  Map<String, dynamic> toStartPayload() => {
        'method': QrcMethod.startTilawaSession.wire,
        'chapter_index': chapterIndex,
        'verse_index': verseIndex,
        'word_index': wordIndex,
        'hafz_level': hafzLevel,
        'tajweed_level': tajweedLevel,
      };

  QrcConfig copyWith({
    int? chapterIndex,
    int? verseIndex,
    int? wordIndex,
    int? hafzLevel,
    int? tajweedLevel,
  }) =>
      QrcConfig(
        chapterIndex: chapterIndex ?? this.chapterIndex,
        verseIndex: verseIndex ?? this.verseIndex,
        wordIndex: wordIndex ?? this.wordIndex,
        hafzLevel: hafzLevel ?? this.hafzLevel,
        tajweedLevel: tajweedLevel ?? this.tajweedLevel,
      );

  @override
  String toString() => 'QrcConfig(chapter:$chapterIndex, verse:$verseIndex, '
      'word:$wordIndex, hafz:$hafzLevel, tajweed:$tajweedLevel)';
}
