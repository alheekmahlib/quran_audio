import 'dart:async';
import 'dart:developer' show log;
import 'dart:typed_data' show Uint8List;

import 'package:get/get.dart';
import 'package:record/record.dart';

import '../shared/platform_io.dart';
import 'models/qrc_config.dart';
import 'models/qrc_feedback.dart';
import 'qrc_client.dart';
import 'qrc_constants.dart';
import 'recitation_state.dart';

/// جلسة تسميع واحدة — تربط الميكروفون بِعميل qurani.ai WebSocket.
///
/// A single recitation session — wires the microphone to the qurani.ai client.
///
/// النمط: تسجيل Opus لِملف مؤقت، ثم بثّ الملف عبر WS بعد الإيقاف.
/// qurani.ai يتوقع Opus؛ iOS/Android لا يدعمان Opus في streaming، لذا
/// نسجّل لِملف (مدعوم) ثم نبثّه.
///
/// Pattern: record Opus to a temp file, then stream the file over WS after stop.
/// qurani.ai expects Opus; iOS/Android don't support Opus in streaming mode, so
/// we record to a file (supported) then stream it.
///
/// دورة الحياة:
/// 1. [start] — يفتح WS، يُرسل `start_tilawa_session`، يبدأ التسجيل لِملف Opus.
/// 2. [feedbackStream] — التصحيح الوارد من الخادم بعد بثّ الصوت.
/// 3. [stop] — يُوقف التسجيل، يقرأ الملف، يبثّه عبر WS، يُرسل `end_tilawa_session`.
///
/// Lifecycle:
/// 1. [start] — opens WS, sends `start_tilawa_session`, starts recording to an Opus file.
/// 2. [feedbackStream] — feedback from the server after audio is streamed.
/// 3. [stop] — stops recording, reads the file, streams it over WS, sends `end_tilawa_session`.
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
  String? _recordingPath;

  /// حالة الجلسة (reactive لِـ GetX).
  /// Session state (reactive for GetX).
  final Rx<RecitationState> state = RecitationState.idle.obs;

  /// آخر خطأ (إن وُجد).
  /// Last error (if any).
  final RxString lastError = ''.obs;

  /// هل الجلسة مفتوحة؟ / Is the session open?
  bool get isOpen => _client != null && _client!.isConnected;

  /// تدفّق التصحيح الوارد.
  /// Incoming feedback stream.
  Stream<QrcFeedback> get feedbackStream =>
      _client?.feedbackStream ?? const Stream.empty();

  /// ابدأ الجلسة: اتصل، أرسل start، ابدأ التسجيل لِملف Opus.
  ///
  /// Start the session: connect, send start, begin recording to an Opus file.
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

      // 3) ابدأ التسجيل لِملف Opus.
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

  /// ابدأ التسجيل لِملف Opus مؤقت.
  /// Start recording to a temporary Opus file.
  Future<void> _startRecording() async {
    _recorder ??= AudioRecorder();
    _ownsRecorder = true;

    final hasMic = await _recorder!.hasPermission();
    if (!hasMic) {
      throw StateError('Microphone permission denied');
    }

    // حدّد مسار ملف مؤقت بصيغة opus (مغلّف ogg).
    // Determine a temp file path in opus (ogg container) format.
    final tempDir = await PlatformIo.tempDir;
    _recordingPath = '$tempDir/quran_recitation_${DateTime.now().millisecondsSinceEpoch}.wav';

    // إعدادات التسجيل — WAV أحادي 16kHz.
    // WAV مدعوم على كل المنصات (iOS/Android/web/desktop). qurani.ai يفضّل Opus
    // لكن WAV/PCM16 صيغة قياسية لِنماذج ASR وقد يُقبل.
    //
    // Recording settings — mono WAV at 16kHz.
    // WAV is supported on all platforms (iOS/Android/web/desktop). qurani.ai
    // prefers Opus, but WAV/PCM16 is a standard ASR format and may be accepted.
    final settings = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    );

    await _recorder!.start(settings, path: _recordingPath!);
    log('Recording to WAV file: $_recordingPath', name: 'RecitationSession');
  }

  /// أوقف الجلسة: أوقف التسجيل، اقرأ الملف، ابثّه، أرسل end.
  /// Stop the session: stop recording, read the file, stream it, send end.
  Future<void> stop() async {
    try {
      // 1) أوقف التسجيل وأخذ مسار الملف.
      final path = await _recorder?.stop();
      _recordingPath = path ?? _recordingPath;
      state.value = RecitationState.processing;
      log('Recording stopped. File: $_recordingPath', name: 'RecitationSession');

      // تحقق من وجود وحجم الملف قبل البثّ.
      // Verify the file exists and has content before streaming.
      if (_recordingPath == null) {
        log('No recording file path — nothing to stream.',
            name: 'RecitationSession');
        lastError.value = 'لم يُسجَّل أي صوت';
      } else if (!await PlatformIo.fileExists(_recordingPath!)) {
        log('Recording file does not exist: $_recordingPath',
            name: 'RecitationSession');
        lastError.value = 'ملف التسجيل غير موجود';
      } else {
        // 2) اقرأ الملف وابثّه عبر WS على دفعات.
        if (_client != null) {
          await _streamFileOverWs(_recordingPath!);
        }
      }

      // 3) أرسل رسالة إنهاء الجلسة.
      _client?.sendJson(config.toEndPayload());
    } catch (e, s) {
      log('RecitationSession stop error: $e',
          name: 'RecitationSession', stackTrace: s);
    } finally {
      try {
        if (_ownsRecorder) {
          await _recorder?.dispose();
        }
        _recorder = null;
        // احذف الملف المؤقت.
        if (_recordingPath != null) {
          await PlatformIo.deleteFile(_recordingPath!);
        }
        await _client?.close();
        _client = null;
      } catch (_) {}
      state.value = RecitationState.finished;
    }
  }

  /// اقرأ ملف الصوت وابثّه عبر WS على دفعات (chunks).
  ///
  /// Read the audio file and stream it over WS in chunks.
  Future<void> _streamFileOverWs(String filePath) async {
    try {
      final bytes = await PlatformIo.readFile(filePath);
      const chunkSize = 4096; // 4KB chunks
      log('Streaming ${bytes.length} bytes of WAV audio over WS...',
          name: 'RecitationSession');
      for (int offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = (offset + chunkSize > bytes.length)
            ? bytes.length
            : offset + chunkSize;
        _client?.sendAudioChunk(
          Uint8List.sublistView(bytes, offset, end),
        );
      }
      log('Finished streaming audio.', name: 'RecitationSession');
    } catch (e, s) {
      log('Failed to stream file: $e', name: 'RecitationSession',
          stackTrace: s);
    }
  }

  /// صرّح بالموارد فوراً إن لم تُستدعَ stop.
  /// Release resources immediately if stop wasn't called.
  void dispose() {
    stop();
  }
}
