import '../qrc_constants.dart';

/// تصحيح تلاوة وارد من qurani.ai.
///
/// Recitation feedback received from qurani.ai.
///
/// بنية الاستجابة موثّقة الآن:
/// - `start_tilawa_session`: `{event, exit_code, websocket_id}`
/// - `check_tilawa`: `{event, exit_code, chapter_index, verse_index, word_index,
///    correct_words[], skipped_words[], tajweed_mistakes[]}`
///
/// The response schema is now documented.
class QrcFeedback {
  /// الـ JSON الخام القادم من الخادم.
  final Map<String, dynamic> raw;

  /// وقت استلام الرسالة.
  final DateTime timestamp;

  const QrcFeedback({required this.raw, required this.timestamp});

  factory QrcFeedback.fromJson(Map<String, dynamic> json) =>
      QrcFeedback(raw: json, timestamp: DateTime.now());

  // ============ الحقول المشتركة / Common fields ============

  /// نوع الحدث.
  /// Event type.
  QrcEvent get event => QrcEvent.fromString(raw['event'] as String?);

  /// رمز الخروج/الحالة (0 = نجاح عادةً).
  /// Exit/status code (0 = success typically).
  int? get exitCode => raw['exit_code'] as int?;

  /// هل الحدث ناجح (exit_code == 0)؟
  /// Is this event successful (exit_code == 0)?
  bool get isSuccess => exitCode == 0;

  // ============ حقول start_tilawa_session ============

  /// معرّف الـ websocket (في حدث بدء الجلسة).
  /// WebSocket id (in the session-start event).
  String? get websocketId => raw['websocket_id'] as String?;

  // ============ حقول check_tilawa (التصحيح) ============

  /// رقم السورة المعنية بالتصحيح.
  /// Surah number in the feedback.
  int? get chapterIndex => raw['chapter_index'] as int?;

  /// رقم الآية المعنية بالتصحيح.
  /// Verse number in the feedback.
  int? get verseIndex => raw['verse_index'] as int?;

  /// رقم الكلمة المعنية.
  /// Word number in the feedback.
  int? get wordIndex => raw['word_index'] as int?;

  /// الكلمات الصحيحة (نطقها المستخدم بشكل سليم).
  /// Correctly recited words.
  List<String> get correctWords =>
      (raw['correct_words'] as List<dynamic>?)?.cast<String>() ?? const [];

  /// الكلمات المتخطّاة (لم ينطقها المستخدم).
  /// Skipped words (not recited by the user).
  List<String> get skippedWords =>
      (raw['skipped_words'] as List<dynamic>?)?.cast<String>() ?? const [];

  /// أخطاء التجويد.
  /// Tajweed mistakes.
  List<dynamic> get tajweedMistakes =>
      (raw['tajweed_mistakes'] as List<dynamic>?) ?? const [];

  /// عدد أخطاء التجويد.
  /// Number of tajweed mistakes.
  int get tajweedMistakeCount => tajweedMistakes.length;

  /// هل التلاوة صحيحة تماماً (لا كلمات متخطّاة، لا أخطاء تجويد)؟
  /// Is the recitation fully correct (no skipped words, no tajweed mistakes)?
  bool get isFullyCorrect =>
      skippedWords.isEmpty && tajweedMistakes.isEmpty && correctWords.isNotEmpty;

  /// درجة تقريبية (نسبة الكلمات الصحيحة من المجموع).
  /// Approximate score (ratio of correct words to total).
  double get score {
    final total = correctWords.length + skippedWords.length;
    if (total == 0) return 0;
    return correctWords.length / total;
  }

  /// هل هذه رسالة تصحيح (check_tilawa)؟
  /// Is this a feedback message (check_tilawa)?
  bool get isFeedback => event == QrcEvent.checkTilawa;

  /// هل هذه رسالة تأكيد بدء الجلسة؟
  /// Is this a session-start confirmation?
  bool get isSessionStart => event == QrcEvent.startTilawaSession;

  @override
  String toString() => 'QrcFeedback(event: $event, exitCode: $exitCode, '
      'correct: ${correctWords.length}, skipped: ${skippedWords.length}, '
      'tajweedMistakes: $tajweedMistakeCount)';
}
