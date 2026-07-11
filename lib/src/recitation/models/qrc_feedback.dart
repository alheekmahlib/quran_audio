/// تصحيح تلاوة وارد من qurani.ai.
///
/// Recitation feedback received from qurani.ai.
///
/// ⚠️ qurani.ai لا تنشر بنية JSON لِلاستجابة. لذلك هذا النموذج **permissive**:
/// يحتفظ بِالـ JSON الخام في [raw] ويوفّر accessors دفاعية لِحقول محتملة شائعة.
/// عند توثيق البنية لاحقاً، يمكن إضافة accessors أقوى أو إنشاء sub-models.
///
/// ⚠️ qurani.ai does not publish the response JSON schema. So this model is
/// **permissive**: it keeps the raw JSON in [raw] and provides defensive
/// accessors for common likely fields. Once documented, stronger accessors or
/// sub-models can be added.
class QrcFeedback {
  /// الـ JSON الخام القادم من الخادم.
  /// The raw JSON received from the server.
  final Map<String, dynamic> raw;

  /// وقت استلام الرسالة.
  /// Time the message was received.
  final DateTime timestamp;

  const QrcFeedback({required this.raw, required this.timestamp});

  factory QrcFeedback.fromJson(Map<String, dynamic> json) =>
      QrcFeedback(raw: json, timestamp: DateTime.now());

  // ============ accessors دفاعية لِحقول محتملة ============
  // Defensive accessors for likely fields (all nullable — absent-safe).

  /// اسم الحدث/الطريقة إن وُجد (مثل `event`, `type`, `method`).
  /// Event/method name if present (e.g. `event`, `type`, `method`).
  String? get event =>
      (raw['event'] ?? raw['type'] ?? raw['method']) as String?;

  /// هل التلاوة صحيحة حتى الآن؟ (إن وفَر الخادم هذا الحقل).
  /// Is the recitation correct so far? (if the server provides this field).
  bool? get isCorrect => raw['correct'] as bool?;

  /// درجة صحة (0..100 أو 0..1) إن وُجدت.
  /// Correctness score (0..100 or 0..1) if present.
  num? get score => (raw['score'] ?? raw['accuracy']) as num?;

  /// قائمة أخطاء محتملة (إن وُجدت).
  /// List of detected errors (if present).
  List<dynamic>? get errors => raw['errors'] as List<dynamic>?;

  /// الكلمة/الآية المعنية (إن وُجدت).
  /// The word/verse in question (if present).
  dynamic get target => raw['word'] ?? raw['verse'] ?? raw['target'];

  /// رسالة نصية إن وُجدت.
  /// Text message if present.
  String? get message => raw['message'] as String?;

  @override
  String toString() => 'QrcFeedback(event: $event, correct: $isCorrect, '
      'score: $score, raw: $raw)';
}
