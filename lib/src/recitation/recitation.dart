import 'dart:developer' show log;

import 'models/muaalem_config.dart';
import 'muaalem_client.dart';
import 'recitation_session.dart';

/// نقطة الدخول العامة لِميزة التسميع (تصحيح التلاوة) عبر خادم quran-muaalem.
///
/// Facade for the recitation-correction feature via a quran-muaalem server.
///
/// هذه الوحدة **اختيارية تماماً**: لا تُحمّل ولا تستهلك موارداً حتى تستدعي
/// [init] بِعنوان خادم quran-muaalem. من لا يستخدم التسميع، لا يتأثر إطلاقاً.
///
/// This module is **entirely optional**: not loaded and consumes no resources
/// until you call [init] with a quran-muaalem server URL.
///
/// ## الإعداد / Setup
///
/// شغّل خادم quran-muaalem على جهازك أو خادمك:
/// ```bash
/// pip install "quran-muaalem[engine]"
/// quran-muaalem-engine  # منفذ 8000 (النموذج)
/// quran-muaalem-app     # منفذ 8001 (HTTP API)
/// ```
///
/// ثم في تطبيقك:
/// ```dart
/// // 1) فعّل الوحدة مرة واحدة:
/// Recitation.init(serverUrl: 'http://localhost:8001');
///
/// // 2) أنشئ جلسة وابدأ التسجيل:
/// final session = Recitation.createSession();
/// await session.start();
/// // ... يتلو المستخدم ...
/// await session.stop();
/// print(session.result.value?.errors);  // أخطاء التجويد!
/// ```
class Recitation {
  Recitation._();

  static MuaalemClient? _client;
  static String? _serverUrl;

  /// هل الوحدة مهيّأة (تم تمرير عنوان خادم)؟
  /// Is the module initialized (a server URL was provided)?
  static bool get isInitialized => _client != null;

  /// عنوان الخادم الحالي (لِلقراءة فقط) أو null.
  /// The current server URL (read-only) or null.
  static String? get serverUrl => _serverUrl;

  /// هيّئ وحدة التسميع بِعنوان خادم quran-muaalem.
  ///
  /// Initialize the recitation module with a quran-muaalem server URL.
  ///
  /// [serverUrl] - عنوان خادم quran-muaalem (مثل `http://localhost:8001`
  ///   لِخادم محلي، أو `https://your-server.com` لِخادم بعيد).
  ///
  /// [serverUrl] - the quran-muaalem server URL (e.g. `http://localhost:8001`
  ///   for a local server, or `https://your-server.com` for a remote one).
  static void init({required String serverUrl}) {
    final trimmed = serverUrl.trim();
    if (trimmed.isEmpty) {
      log('Recitation.init: empty server URL — module stays uninitialized.',
          name: 'Recitation');
      return;
    }
    _client?.dispose();
    _client = MuaalemClient(baseUrl: trimmed);
    _serverUrl = trimmed;
    log('Recitation initialized. serverUrl=$trimmed', name: 'Recitation');
  }

  /// أعد ضبط الوحدة (نسيان الخادم).
  /// Reset the module (forget the server).
  static void reset() {
    _client?.dispose();
    _client = null;
    _serverUrl = null;
  }

  /// تحقّق من صحة الخادم (هل يعمل والنموذج محمّل؟).
  ///
  /// Check server health (is it running and the model loaded?).
  ///
  /// استدعِ هذا قبل [createSession] للتأكّد من أنّ الخادم جاهز.
  /// Call this before [createSession] to verify the server is ready.
  static Future<bool> isServerHealthy() async {
    if (_client == null) return false;
    return _client!.isHealthy();
  }

  /// أنشئ جلسة تسميع جديدة.
  ///
  /// Create a new recitation session.
  ///
  /// تتطلّب تهيئة مسبقة عبر [init]، وإلا تُطرح [StateError].
  /// Requires prior initialization via [init], otherwise throws [StateError].
  ///
  /// [config] - إعدادات المصحف (افتراضي: Hafs). عدّلها لِمصاحف أخرى.
  /// [config] - moshaf config (default: Hafs). Change for other moshafs.
  static RecitationSession createSession({
    MuaalemConfig config = const MuaalemConfig(),
  }) {
    _ensureInitialized();
    return RecitationSession(
      config: config,
      client: _client!,
    );
  }

  /// تحقّق من التهيئة، وإلا اطرح خطأ واضحاً.
  /// Ensure initialization, else throw a clear error.
  static void _ensureInitialized() {
    if (!isInitialized) {
      throw StateError(
        'Recitation is not initialized. Call '
        'Recitation.init(serverUrl: "http://localhost:8001") first.\n'
        'To run the quran-muaalem server:\n'
        '  pip install "quran-muaalem[engine]"\n'
        '  quran-muaalem-engine  # port 8000\n'
        '  quran-muaalem-app     # port 8001\n'
        'See: https://github.com/obadx/quran-muaalem',
      );
    }
  }
}
