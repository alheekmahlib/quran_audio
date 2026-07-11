/// استراتيجية إرسال مفتاح API لِـ qurani.ai.
///
/// Strategy for sending the qurani.ai API key over the WebSocket.
enum QrcAuthStrategy {
  /// أضف المفتاح كمعامل استعلام على رابط wss (مثل `?api_key=...`).
  /// Append the key as a query param on the wss URL (e.g. `?api_key=...`).
  /// هذا هو النمط الموثّق في qurani.ai: `wss://api.qurani.ai?api_key=KEY`.
  queryParam,

  /// أرسل المفتاح كأول رسالة JSON بعد الاتصال.
  firstMessage,

  /// أرسل المفتاح عبر Sec-WebSocket-Protocol subprotocol.
  subprotocol,
}

/// أحداث qurani.ai الواردة (server → client).
///
/// Inbound qurani.ai events (server → client).
enum QrcEvent {
  /// تأكيد بدء الجلسة — `{event: "start_tilawa_session", exit_code, websocket_id}`.
  startTilawaSession,

  /// التصحيح الفعلي — `{event: "check_tilawa", exit_code, correct_words, skipped_words, tajweed_mistakes, ...}`.
  checkTilawa,

  /// حدث غير معروف.
  unknown;

  /// حلّل من نص الحدث القادم من الخادم.
  /// Parse from the event string received from the server.
  static QrcEvent fromString(String? value) => switch (value) {
        'start_tilawa_session' => QrcEvent.startTilawaSession,
        'check_tilawa' => QrcEvent.checkTilawa,
        _ => QrcEvent.unknown,
      };
}

/// ثوابت عميل qurani.ai QRC (موثّقة من qurani.ai).
///
/// Constants for the qurani.ai QRC client (documented by qurani.ai).
class QrcConstants {
  QrcConstants._();

  /// عنوان WebSocket الرسمي الموثّق.
  ///
  /// The official documented WebSocket endpoint.
  /// صيغة الاستخدام: `wss://api.qurani.ai?api_key=YOUR_KEY`.
  static const String defaultWsUrl = 'wss://api.qurani.ai';

  /// استراتيجية المصادقة الافتراضية (موثّقة في qurani.ai JS).
  static const QrcAuthStrategy defaultAuthStrategy =
      QrcAuthStrategy.queryParam;

  /// اسم معامل الاستعلام لِلمفتاح.
  static const String apiKeyQueryParam = 'api_key';

  /// زمن انتظار الاتصال الافتراضي.
  static const Duration connectTimeout = Duration(seconds: 10);

  /// الحد الأدنى لِمستوى الحفظ.
  static const int minHafzLevel = 1;

  /// الحد الأقصى لِمستوى الحفظ.
  static const int maxHafzLevel = 3;

  /// الحد الأدنى لِمستوى التجويد.
  static const int minTajweedLevel = 1;

  /// الحد الأقصى لِمستوى التجويد.
  static const int maxTajweedLevel = 3;
}
