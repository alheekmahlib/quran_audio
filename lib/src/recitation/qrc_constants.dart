/// استراتيجية إرسال مفتاح API لِـ qurani.ai.
///
/// Strategy for sending the qurani.ai API key over the WebSocket.
///
/// qurani.ai لا توثّق كيفية إرسال المفتاح صراحةً. الافتراضي هو query param،
/// لكن المستخدم يمكنه تجاوزه عبر `Recitation.init(authStrategy: ...)`.
///
/// qurani.ai does not document how the key is sent. The default is a query
/// param, but the user can override via `Recitation.init(authStrategy: ...)`.
enum QrcAuthStrategy {
  /// أضف المفتاح كمعامل استعلام على رابط wss (مثل `?api_key=...`).
  /// Append the key as a query param on the wss URL (e.g. `?api_key=...`).
  queryParam,

  /// أرسل المفتاح كأول رسالة JSON بعد الاتصال.
  /// Send the key as the first JSON message after connecting.
  firstMessage,

  /// أرسل المفتاح عبر Sec-WebSocket-Protocol subprotocol.
  /// Send the key via the Sec-WebSocket-Protocol subprotocol.
  subprotocol,
}

/// ثوابت عميل qurani.ai QRC.
///
/// Constants for the qurani.ai QRC client.
class QrcConstants {
  QrcConstants._();

  /// عنوان WebSocket الافتراضي.
  ///
  /// ⚠️ TODO(qurani.ai): العنوان الدقيق غير موثّق بِشكل قاطع في الوثائق
  /// (يُضمَّن في كود JS غير مُستخرَج). هذا افتراضي معقول قابل للتجاوز عبر
  /// `Recitation.init(wsUrl: ...)`. يجب التحقق منه عند الحصول على API key.
  ///
  /// ⚠️ The exact endpoint is not definitively documented (embedded in JS code
  /// that was not extracted). This is a reasonable default, overridable via
  /// `Recitation.init(wsUrl: ...)`. Verify it once you have an API key.
  static const String defaultWsUrl = 'wss://qurani.ai/api/qrc/ws';

  /// استراتيجية المصادقة الافتراضية.
  static const QrcAuthStrategy defaultAuthStrategy =
      QrcAuthStrategy.queryParam;

  /// اسم معامل الاستعلام لِلمفتاح عند استخدام queryParam.
  /// Query-param name for the key when using queryParam strategy.
  static const String apiKeyQueryParam = 'api_key';

  /// زمن انتظار الاتصال الافتراضي (10 ثوانٍ).
  /// Default connection timeout (10 seconds).
  static const Duration connectTimeout = Duration(seconds: 10);
}
