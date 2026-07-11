import 'dart:async';
import 'dart:developer' show log;
import 'dart:typed_data' show Uint8List;

import 'package:get/get.dart';
import 'package:record/record.dart';

import 'models/qrc_config.dart';
import 'models/qrc_feedback.dart';
import 'qrc_client.dart';
import 'qrc_constants.dart';
import 'recitation_state.dart';

/// جلسة تسميع واحدة — تربط الميكروفون بِعميل qurani.ai WebSocket.
///
/// A single recitation session — wires the microphone to the qurani.ai client.
///
/// دورة الحياة:
/// 1. [start] — يفتح WS، يُرسل `StartTilawaSession`، يبدأ التسجيل ويبثّ القطع.
/// 2. [feedbackStream] — بثّ التصحيح الحيّ الوارد من الخادم.
/// 3. [stop] — يُوقف التسجيل ويُغلق الجلسة.
///
/// Lifecycle:
/// 1. [start] — opens WS, sends `StartTilawaSession`, starts recording & streaming chunks.
/// 2. [feedbackStream] — live feedback stream from the server.
/// 3. [stop] — stops recording and closes the session.
class RecitationSession {
  RecitationSession({
    required this.config,
    required String apiKey,
    String? wsUrl,
    QrcAuthStrategy? authStrategy,
    AudioRecorder? recorder,
  })  : _apiKey = apiKey,
        _wsUrl = wsUrl,
        _authStrategy = authStrategy,
        _recorder = recorder;

  final QrcConfig config;
  final String _apiKey;
  final String? _wsUrl;
  final QrcAuthStrategy? _authStrategy;

  QrcClient? _client;
  AudioRecorder? _recorder;
  bool _ownsRecorder = false;
  StreamSubscription? _audioSub;

  /// حالة الجلسة (reactive لِـ GetX).
  /// Session state (reactive for GetX).
  final Rx<RecitationState> state = RecitationState.idle.obs;

  /// آخر خطأ (إن وُجد).
  /// Last error (if any).
  final RxString lastError = ''.obs;

  /// هل الجلسة مفتوحة؟ / Is the session open?
  bool get isOpen => _client != null && _client!.isConnected;

  /// تدفّق التصحيح الحيّ.
  /// Live feedback stream.
  Stream<QrcFeedback> get feedbackStream =>
      _client?.feedbackStream ?? const Stream.empty();

  /// ابدأ الجلسة: اتصل، أرسل start، ابدأ التسجيل والبثّ.
  ///
  /// Start the session: connect, send start, begin recording & streaming.
  Future<void> start() async {
    if (state.value.isActive) {
      log('RecitationSession already active', name: 'RecitationSession');
      return;
    }
    try {
      state.value = RecitationState.connecting;
      lastError.value = '';

      // 1) أنشئ العميل واتصل.
      _client = QrcClient(
        apiKey: _apiKey,
        wsUrl: _wsUrl,
        authStrategy: _authStrategy,
      );
      await _client!.connect();

      // 2) أرسل رسالة بدء الجلسة (مرة واحدة).
      _client!.sendJson(config.toStartPayload());

      // 3) ابدأ التسجيل وبثّ القطع.
      await _startRecording();

      state.value = RecitationState.recording;
      log('RecitationSession started: $config', name: 'RecitationSession');
    } catch (e, s) {
      state.value = RecitationState.error;
      lastError.value = e.toString();
      log('RecitationSession start failed: $e',
          name: 'RecitationSession', stackTrace: s);
    }
  }

  /// ابدأ التسجيل وبثّ القطع الصوتية عبر WS.
  /// Start recording and stream audio chunks over WS.
  Future<void> _startRecording() async {
    // أنشئ مُسجّلاً إن لم يُمرَّر من الخارج.
    _recorder ??= AudioRecorder();
    _ownsRecorder = true;

    // تحقق/اطلب صلاحية الميكروفون. record.hasPermission يطلب الإذن تلقائياً.
    // Check/request mic permission. record.hasPermission requests it automatically.
    final hasMic = await _recorder!.hasPermission();
    if (!hasMic) {
      throw StateError('Microphone permission denied');
    }

    // إعدادات التسجيل. وضع التسجيل المتدفّق (startStream) على iOS/Android يدعم
    // PCM فقط (لا يدعم Opus/AAC في الـ streaming — يلزم تسجيل لِملف). لذلك
    // نستخدم pcm16 أحادي القناة بِمعدّل 16kHz (مطابق لِمتطلبات معظم نماذج ASR).
    //
    // Recording settings. The streaming mode (startStream) on iOS/Android only
    // supports PCM (no Opus/AAC in streaming — that requires file recording).
    // So we use mono pcm16 at 16kHz (matches most ASR model requirements).
    //
    // TODO(qurani.ai): إن تطلّب الخادم صيغة ضغط (Opus/WebM)، يمكن التحويل لِملف
    // مؤقت ثم بثّه، أو استخدام حزمة ffmpeg لِإعادة الترميز. راجع وثائق الخادم.
    //
    // TODO(qurani.ai): if the server requires compressed audio (Opus/WebM),
    // consider writing to a temp file then streaming it, or use an ffmpeg
    // package to re-encode. Check the server docs.
    final settings = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    );

    // ابثث القطع الثنائية عبر WS.
    final stream = await _recorder!.startStream(settings);
    _audioSub = stream.listen(
      (Uint8List chunk) {
        _client?.sendAudioChunk(chunk);
      },
      onError: (e, s) => log('Recorder stream error: $e',
          name: 'RecitationSession', stackTrace: s),
    );
  }

  /// أوقف التسجيل (دون إغلاق الاتصال — قابل للاستئناف).
  /// Stop recording (without closing the connection — resumable).
  Future<void> pause() async {
    await _audioSub?.cancel();
    _audioSub = null;
    await _recorder?.stop();
    if (state.value == RecitationState.recording) {
      state.value = RecitationState.paused;
    }
  }

  /// أوقف الجلسة تماماً وأصدر الموارد.
  /// Stop the session entirely and release resources.
  Future<void> stop() async {
    try {
      // أوقف التسجيل أولاً.
      await _audioSub?.cancel();
      _audioSub = null;
      await _recorder?.stop();

      // أرسل رسالة إنهاء الجلسة (تنظيف صريح موثّق).
      // Send the end-session message (explicit documented cleanup).
      _client?.sendJson(config.toEndPayload());
    } catch (e, s) {
      log('RecitationSession stop (pre-close) error: $e',
          name: 'RecitationSession', stackTrace: s);
    }
    try {
      if (_ownsRecorder) {
        await _recorder?.dispose();
      }
      _recorder = null;
      await _client?.close();
      _client = null;
    } catch (e, s) {
      log('RecitationSession stop error: $e',
          name: 'RecitationSession', stackTrace: s);
    } finally {
      state.value = RecitationState.finished;
    }
  }

  /// صرّح بالموارد فوراً إن لم تُستدعَ stop.
  /// Release resources immediately if stop wasn't called.
  void dispose() {
    stop();
  }
}
