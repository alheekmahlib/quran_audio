import '../qrc_constants.dart';
import 'qrc_method.dart';

/// إعدادات بدء جلسة تسميع (payload لِـ `start_tilawa_session`).
///
/// Configuration to start a recitation session (the `start_tilawa_session` payload).
///
/// الحقول مطابقة لِوثائق qurani.ai JS. النطاقات مؤكَّدة:
/// - chapter_index: 1..114 (1-based)
/// - verse_index / word_index: 1-based ضمن السورة/الآية
/// - hafz_level: 1..3
/// - tajweed_level: 1..3
///
/// Fields match the qurani.ai JS docs. Ranges are confirmed.
class QrcConfig {
  /// رقم السورة (1..114).
  final int chapterIndex;

  /// رقم الآية ضمن السورة (1..ayahCount).
  final int verseIndex;

  /// رقم الكلمة الابتدائية ضمن الآية (الافتراضي 1).
  final int wordIndex;

  /// مستوى الحفظ (1..3). يضبط توقّعات النموذج.
  final int hafzLevel;

  /// مستوى صرامة فحص التجويد (1..3).
  final int tajweedLevel;

  const QrcConfig({
    required this.chapterIndex,
    required this.verseIndex,
    this.wordIndex = 1,
    this.hafzLevel = 1,
    this.tajweedLevel = 1,
  })  : assert(hafzLevel >= QrcConstants.minHafzLevel &&
            hafzLevel <= QrcConstants.maxHafzLevel),
        assert(tajweedLevel >= QrcConstants.minTajweedLevel &&
            tajweedLevel <= QrcConstants.maxTajweedLevel);

  /// ابنِ payload رسالة بدء الجلسة كما تتوقّعها qurani.ai.
  /// Build the start_tilawa_session payload expected by qurani.ai.
  Map<String, dynamic> toStartPayload() => {
        'method': QrcMethod.startTilawaSession.wire,
        'chapter_index': chapterIndex,
        'verse_index': verseIndex,
        'word_index': wordIndex,
        'hafz_level': hafzLevel,
        'tajweed_level': tajweedLevel,
      };

  /// ابنِ payload إنهاء الجلسة.
  /// Build the end_tilawa_session payload.
  Map<String, dynamic> toEndPayload() => {
        'method': QrcMethod.endTilawaSession.wire,
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
