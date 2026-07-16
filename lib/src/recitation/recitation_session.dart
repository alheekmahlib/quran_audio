import 'dart:async';
import 'dart:developer' show log;

import 'package:get/get.dart';
import 'package:record/record.dart';

import '../shared/platform_io.dart';
import 'models/muaalem_config.dart';
import 'models/recitation_result.dart';
import 'recitation_engine.dart';
import 'recitation_state.dart';

/// جلسة تسميع واحدة — تسجّل WAV، تُرسله لِلمحرّك (online أو offline)،
/// تستلم التصحيح.
///
/// A single recitation session — records WAV, sends it to the engine (online
/// or offline), receives the correction.
///
/// النمط **batch** (وليس streaming): يُسجّل الصوت كاملاً في ملف مؤقّت أثناء
/// التلاوة، ثم عند الإيقاف يُمرّره لِلمحرّك ويستلم النتيجة. هذا أبسط
/// وأكثر موثوقية من streaming.
///
/// **Batch** pattern (not streaming): records the full audio to a temp file
/// during recitation, then on stop passes it to the engine and receives the
/// result. Simpler and more reliable than streaming.
class RecitationSession {
  RecitationSession({
    required this.config,
    required RecitationEngine engine,
    AudioRecorder? recorder,
  })  : _engine = engine,
        _recorder = recorder;

  /// إعدادات المصحف (Hafs افتراضياً).
  /// Moshaf config (Hafs by default).
  final MuaalemConfig config;
  final RecitationEngine _engine;
  AudioRecorder? _recorder;
  bool _ownsRecorder = false;
  String? _recordingPath;

  /// حالة الجلسة (reactive لِـ GetX).
  /// Session state (reactive for GetX).
  final Rx<RecitationState> state = RecitationState.idle.obs;

  /// آخر خطأ (إن وُجد).
  /// Last error (if any).
  final RxString lastError = ''.obs;

  /// نتيجة التصحيح (بعد stop).
  /// Correction result (after stop).
  final Rx<RecitationResult?> result = Rx<RecitationResult?>(null);

  /// ابدأ التسجيل.
  ///
  /// Start recording.
  ///
  /// يُسجّل WAV (16kHz mono) إلى ملف مؤقّت. لا يُرسل شيئاً لِلخادم حتى [stop].
  /// Records WAV (16kHz mono) to a temp file. Doesn't send anything to the
  /// server until [stop].
  Future<void> start() async {
    if (state.value.isActive) {
      log('RecitationSession already active', name: 'RecitationSession');
      return;
    }
    try {
      result.value = null;
      lastError.value = '';
      _recorder ??= AudioRecorder();
      _ownsRecorder = true;

      final hasMic = await _recorder!.hasPermission();
      if (!hasMic) {
        throw StateError('Microphone permission denied');
      }

      // WAV 16kHz mono — مدخل quran-muaalem المتوقَّع.
      // WAV 16kHz mono — quran-muaalem's expected input.
      const settings = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      );

      // أنشئ مساراً مؤقّتاً لِملف WAV (record v6 يتطلّب path مُسبقاً).
      // Create a temp path for the WAV file (record v6 requires a path upfront).
      final dir = await PlatformIo.tempDir;
      _recordingPath = '$dir/recitation_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder!.start(settings, path: _recordingPath!);
      state.value = RecitationState.recording;
      log('RecitationSession started recording: $_recordingPath',
          name: 'RecitationSession');
    } catch (e, s) {
      state.value = RecitationState.error;
      lastError.value = e.toString();
      log('RecitationSession start failed: $e',
          name: 'RecitationSession', stackTrace: s);
    }
  }

  /// أوقف التسجيل ومرّر الصوت لِلمحرّك لِلتصحيح.
  ///
  /// Stop recording and pass the audio to the engine for correction.
  ///
  /// يقرأ ملف WAV كاملاً، يُمرّره لِلمحرّك (online: HTTP، offline: ONNX)،
  /// ويخزّن النتيجة في [result].
  /// Reads the full WAV file, passes it to the engine (online: HTTP,
  /// offline: ONNX), and stores the result in [result].
  Future<void> stop() async {
    try {
      state.value = RecitationState.processing;
      _recordingPath = await _recorder?.stop() ?? _recordingPath;
      log('RecitationSession stopped. Sending to server...',
          name: 'RecitationSession');

      if (_recordingPath == null) {
        throw StateError('No recording file');
      }

      // اقرأ ملف WAV كاملاً.
      // Read the full WAV file.
      final wavBytes = await PlatformIo.readFile(_recordingPath!);
      log('RecitationSession: read ${wavBytes.length} bytes',
          name: 'RecitationSession');

      // مرّر لِلمحرّك (online: خادم، offline: ONNX).
      // Pass to the engine (online: server, offline: ONNX).
      result.value = await _engine.correctRecitation(
        wavBytes: wavBytes,
        config: config,
      );

      log('RecitationSession done: ${result.value}',
          name: 'RecitationSession');
      state.value = RecitationState.finished;
    } catch (e, s) {
      state.value = RecitationState.error;
      lastError.value = e.toString();
      log('RecitationSession stop error: $e',
          name: 'RecitationSession', stackTrace: s);
    } finally {
      // تنظيف: احذف الملف المؤقّت وتصرّف بالمسجّل.
      // Cleanup: delete the temp file and dispose the recorder.
      if (_recordingPath != null) {
        try {
          await PlatformIo.deleteFile(_recordingPath!);
        } catch (_) {}
      }
      if (_ownsRecorder) {
        try {
          await _recorder?.dispose();
        } catch (_) {}
      }
      _recorder = null;
    }
  }

  /// صرّح بالموارد فوراً إن لم تُستدعَ stop.
  /// Dispose resources immediately if stop wasn't called.
  void dispose() {
    if (state.value == RecitationState.recording) {
      stop();
    }
  }
}
