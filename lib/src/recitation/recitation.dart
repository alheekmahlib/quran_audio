import 'dart:developer' show log;

import 'models/qrc_config.dart';
import 'qrc_constants.dart';
import 'recitation_session.dart';

/// نقطة الدخول العامة لِميزة التسميع (تصحيح التلاوة) عبر qurani.ai.
///
/// Facade for the recitation-correction feature via qurani.ai.
///
/// هذه الوحدة **اختيارية تماماً**: لا تُحمّل ولا تستهلك موارداً حتى تستدعي
/// [init] بِمفتاح API صالح. من لا يستخدم التسميع، لا يتأثر إطلاقاً.
///
/// This module is **entirely optional**: it is not loaded and consumes no
/// resources until you call [init] with a valid API key. Users who don't use
/// recitation are completely unaffected.
///
/// مثال:
/// ```dart
/// // 1) فعّل الوحدة مرة واحدة (اختياري لِمن لا يستخدم التسميع):
/// Recitation.init('YOUR_QURANI_AI_API_KEY');
///
/// // 2) أنشئ جلسة:
/// final session = Recitation.createSession(
///   config: QrcConfig(chapterIndex: 1, verseIndex: 1),
/// );
/// session.feedbackStream.listen((fb) => print(fb.raw));
/// await session.start();
/// // ... يتلو المستخدم ...
/// await session.stop();
/// ```
class Recitation {
  Recitation._();

  static String? _apiKey;
  static String? _wsUrl;
  static QrcAuthStrategy? _authStrategy;

  /// هل الوحدة مهيّأة (تم تمرير API key)؟
  /// Is the module initialized (an API key was provided)?
  static bool get isInitialized => _apiKey != null && _apiKey!.isNotEmpty;

  /// المفتاح الحالي (لِلقراءة فقط) أو null.
  /// The current key (read-only) or null.
  static String? get apiKey => _apiKey;

  /// هيّئ وحدة التسميع بِمفتاح API.
  ///
  /// Initialize the recitation module with an API key.
  ///
  /// [apiKey] - مفتاح qurani.ai (يُحصَل عليه من https://qurani.ai/en/dashboard).
  /// [wsUrl] - تجاوز عنوان WebSocket الافتراضي (إن عُرف العنوان الدقيق).
  ///   راجع [QrcConstants.defaultWsUrl].
  /// [authStrategy] - كيفية إرسال المفتاح عبر WS. افتراضي: query param.
  ///   راجع [QrcAuthStrategy].
  ///
  /// استدعِ هذا مرة واحدة قبل [createSession]. بدونها ترفض الوحدة العمل.
  ///
  /// Call this once before [createSession]. Without it the module refuses to operate.
  static void init({
    required String apiKey,
    String? wsUrl,
    QrcAuthStrategy? authStrategy,
  }) {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      log('Recitation.init: empty API key — module stays uninitialized.',
          name: 'Recitation');
      return;
    }
    _apiKey = trimmed;
    _wsUrl = wsUrl;
    _authStrategy = authStrategy;
    log('Recitation initialized. wsUrl=${wsUrl ?? "(default)"}, '
        'authStrategy=${authStrategy ?? "(default)"}',
        name: 'Recitation');
  }

  /// أعد ضبط الوحدة (نسيان المفتاح).
  /// Reset the module (forget the key).
  static void reset() {
    _apiKey = null;
    _wsUrl = null;
    _authStrategy = null;
  }

  /// أنشئ جلسة تسميع جديدة.
  ///
  /// Create a new recitation session.
  ///
  /// تتطلّب تهيئة مسبقة عبر [init]، وإلا تُطرح [StateError].
  /// Requires prior initialization via [init], otherwise throws [StateError].
  static RecitationSession createSession({required QrcConfig config}) {
    _ensureInitialized();
    return RecitationSession(
      config: config,
      apiKey: _apiKey!,
      wsUrl: _wsUrl,
      authStrategy: _authStrategy,
    );
  }

  /// تحقّق من التهيئة، وإلا اطرح خطأ واضحاً.
  /// Ensure initialization, else throw a clear error.
  static void _ensureInitialized() {
    if (!isInitialized) {
      throw StateError(
        'Recitation is not initialized. Call Recitation.init(apiKey: ...) '
        'first with your qurani.ai API key. '
        'Get one at https://qurani.ai/en/dashboard',
      );
    }
  }
}
