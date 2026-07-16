import 'dart:developer' show log;

import 'models/muaalem_config.dart';
import 'muaalem_client.dart';
import 'onnx_recitation_engine.dart';
import 'recitation_engine.dart';
import 'recitation_session.dart';

/// نقطة الدخول العامة لِميزة التسميع (تصحيح التلاوة).
///
/// Facade for the recitation-correction feature.
///
/// تدعم الوحدة محرّكَين:
/// - **Online** (افتراضي): خادم [quran-muaalem](https://github.com/obadx/quran-muaalem)
///   عبر [init] + [serverUrl].
/// - **Offline**: نموذج ONNX محلي (95MB) يُحمَّل على الجهاز عبر
///   [initOffline] — لا يحتاج خادماً ولا إنترنت.
///
/// هذه الوحدة **اختيارية تماماً**: لا تُحمّل ولا تستهلك موارداً حتى تستدعي
/// [init] أو [initOffline].
///
/// ## Online / Setup
///
/// ```bash
/// pip install "quran-muaalem[engine]"
/// quran-muaalem-engine  # منفذ 8000 (النموذج)
/// quran-muaalem-app     # منفذ 8001 (HTTP API)
/// ```
///
/// ```dart
/// Recitation.init(serverUrl: 'http://localhost:8001');
/// final session = Recitation.createSession();
/// await session.start();
/// // ... تلاوة ...
/// await session.stop();
/// print(session.result.value?.errors);
/// ```
///
/// ## Offline / Setup
///
/// ```dart
/// await Recitation.initOffline();  // يحمل النموذج من assets
/// final session = Recitation.createSession();
/// await session.start();
/// // ... تلاوة (بدون إنترنت!) ...
/// await session.stop();
/// print(session.result.value?.predictedPhonemes);
/// ```
class Recitation {
  Recitation._();

  static RecitationEngine? _engine;
  static String? _serverUrl;
  static bool _isOffline = false;

  /// هل الوحدة مهيّأة؟
  /// Is the module initialized?
  static bool get isInitialized => _engine != null;

  /// هل المحرّك offline (ONNX)؟
  /// Is the engine offline (ONNX)?
  static bool get isOffline => _isOffline;

  /// عنوان الخادم (online) أو null.
  /// The server URL (online) or null.
  static String? get serverUrl => _serverUrl;

  // ── Online ──────────────────────────────────────────────────

  /// هيّئ وحدة التسميع بِخادم quran-muaalem (online).
  ///
  /// Initialize the recitation module with a quran-muaalem server (online).
  ///
  /// [serverUrl] - عنوان الخادم (مثل `http://localhost:8001`).
  static void init({required String serverUrl}) {
    final trimmed = serverUrl.trim();
    if (trimmed.isEmpty) {
      log('Recitation.init: empty server URL — module stays uninitialized.',
          name: 'Recitation');
      return;
    }
    _engine?.dispose();
    _engine = MuaalemClient(baseUrl: trimmed);
    _serverUrl = trimmed;
    _isOffline = false;
    log('Recitation initialized (online). serverUrl=$trimmed',
        name: 'Recitation');
  }

  // ── Offline ─────────────────────────────────────────────────

  /// هيّئ وحدة التسميع بِنموذج ONNX محلي (offline — لا إنترنت).
  ///
  /// Initialize the recitation module with a local ONNX model (offline).
  ///
  /// [modelPath] - مسار النموذج (إن null، يُحمَّل من assets).
  /// [vocabPath] - مسار vocab (إن null، من assets).
  ///
  /// يعمل على الأجهزة المحمولة وسطح المكتب (لا يدعم الويب).
  static Future<void> initOffline({
    String? modelPath,
    String? vocabPath,
  }) async {
    _engine?.dispose();
    final onnxEngine = OnnxRecitationEngine(
      modelAssetPath: modelPath,
      vocabAssetPath: vocabPath,
    );
    await onnxEngine.initialize();
    _engine = onnxEngine;
    _serverUrl = null;
    _isOffline = true;
    log('Recitation initialized (offline, ONNX).', name: 'Recitation');
  }

  // ── مشترك ───────────────────────────────────────────────────

  /// أعد ضبط الوحدة (نسيان المحرّك).
  /// Reset the module (forget the engine).
  static void reset() {
    _engine?.dispose();
    _engine = null;
    _serverUrl = null;
    _isOffline = false;
  }

  /// تحقّق من جاهزية المحرّك.
  ///
  /// Check engine health (server online / model offline).
  static Future<bool> isEngineHealthy() async {
    if (_engine == null) return false;
    return _engine!.isHealthy();
  }

  /// تحقّق من صحة الخادم (متوافق مع الإصدارات السابقة — للـ online).
  ///
  /// Check server health (backward-compatible alias for [isEngineHealthy]).
  static Future<bool> isServerHealthy() => isEngineHealthy();

  /// أنشئ جلسة تسميع جديدة.
  ///
  /// Create a new recitation session.
  ///
  /// تتطلّب تهيئة مسبقة عبر [init] أو [initOffline].
  static RecitationSession createSession({
    MuaalemConfig config = const MuaalemConfig(),
  }) {
    _ensureInitialized();
    return RecitationSession(
      config: config,
      engine: _engine!,
    );
  }

  static void _ensureInitialized() {
    if (!isInitialized) {
      throw StateError(
        'Recitation is not initialized. Call one of:\n'
        '  Recitation.init(serverUrl: "http://localhost:8001")  // online\n'
        '  await Recitation.initOffline()                       // offline\n'
        '\n'
        'Online server setup:\n'
        '  pip install "quran-muaalem[engine]"\n'
        '  quran-muaalem-engine && quran-muaalem-app\n'
        'Offline model: bundled in assets/models/',
      );
    }
  }
}
