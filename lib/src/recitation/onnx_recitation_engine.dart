/// محرّك تقييم تلاوة offline بِـ ONNX Runtime.
///
/// يُحمّل نموذج `muaalem_student.int8.onnx` (95MB) ويُشغّله على الجهاز
/// بِدون خادم. يُنتج:
/// - رأس phonemes (43 فئة) → فونيمات قرآنية متوقَّعة.
/// - 10 رؤوس صفات (3-4 فئات) → صفات التجويد لِكلّ فونيم.
///
/// التكامل:
/// ```dart
/// await Recitation.initOffline();
/// final session = Recitation.createSession();
/// await session.start();
/// // ... تلاوة ...
/// final result = await session.stop();
/// ```
library;

import 'dart:convert';
import 'dart:developer' show log;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'package:quran_audio/src/recitation/models/muaalem_config.dart';
import 'package:quran_audio/src/recitation/models/recitation_result.dart';
import 'package:quran_audio/src/recitation/recitation_engine.dart';
import 'package:quran_audio/src/recitation/wav_decoder.dart';

/// محرّك استدلال ONNX offline لِتقييم التلاوة.
///
/// يُحمّل النموذج من assets أو من مسار مُخصّص (بعد تنزيله من HuggingFace).
class OnnxRecitationEngine implements RecitationEngine {
  OnnxRecitationEngine({this.modelAssetPath, this.vocabAssetPath});

  /// مسار النموذج في assets (إن كان bundled) أو null لِـ مسار خارجي.
  final String? modelAssetPath;
  final String? vocabAssetPath;

  OrtSession? _session;
  Map<String, dynamic> _vocab = {};
  Map<int, String> _phonemeIdToToken = {};
  bool _initialized = false;
  String? _modelPath;
  List<String> _outputNames = [];

  /// هل المحرّك جاهز.
  @override
  Future<bool> isHealthy() async => _initialized && _session != null;

  // ── التهيئة ───────────────────────────────────────────────────

  /// تهيئة المحرّك — تحميل النموذج + vocab.
  ///
  /// تُطرح [Exception] بِرسالة واضحة عند الفشل (لِعرضها في الـ UI).
  Future<void> initialize() async {
    if (_initialized) return;

    log('OnnxRecitationEngine: initializing…', name: 'OnnxEngine');

    // 1) حلّ مسار النموذج (بِأولويّة واضحة)
    _modelPath = await _resolveModelPath();
    log('OnnxRecitationEngine: model path = $_modelPath', name: 'OnnxEngine');

    // 2) حمّل vocab
    await _loadVocab();
    log('OnnxRecitationEngine: vocab loaded (${_phonemeIdToToken.length} tokens)',
        name: 'OnnxEngine');

    // 3) أنشئ جلسة ONNX Runtime
    try {
      final opts = OrtSessionOptions();
      opts.setIntraOpNumThreads(2);
      opts.setInterOpNumThreads(1);
      _session = OrtSession.fromFile(File(_modelPath!), opts);
      _outputNames = _session!.outputNames;
      log('OnnxRecitationEngine: session created, ${_outputNames.length} outputs',
          name: 'OnnxEngine');
    } catch (e, s) {
      log('OnnxRecitationEngine: FAILED to create session: $e',
          name: 'OnnxEngine', stackTrace: s);
      throw Exception('تعذّر تحميل النموذج: $e');
    }

    _initialized = true;
    log('OnnxRecitationEngine: ready ✓', name: 'OnnxEngine');
  }

  /// يحلّ مسار النموذج بِأولويّة:
  /// 1. مسار خارجي مُمرّر (modelAssetPath) إن وُجد.
  /// 2. المسار الافتراضي في مجلد التطبيق (بعد تنزيله من Release).
  /// 3. من assets (لو كان bundled — غير مُستخدَم حالياً).
  ///
  /// تُطرح [Exception] واضحة إن لم يُعثر على النموذج.
  Future<String> _resolveModelPath() async {
    // 1) مسار خارجي مُمرّر صراحةً (الأولويّة القصوى)
    if (modelAssetPath != null && modelAssetPath!.isNotEmpty) {
      final f = File(modelAssetPath!);
      if (await f.exists()) {
        log('OnnxRecitationEngine: using provided model: ${modelAssetPath!} '
            '(${await f.length()} bytes)',
            name: 'OnnxEngine');
        return modelAssetPath!;
      }
      log('OnnxRecitationEngine: provided path does not exist: ${modelAssetPath!}',
          name: 'OnnxEngine', level: 900);
    }

    // 2) المسار الافتراضي (تنزيل المستخدم من Release)
    final appDir = await getApplicationSupportDirectory();
    // ندعم كلا الاسمَين: qdq (جديد) و int8 (قديم)
    for (final name in [
      'muaalem_student.qdq.onnx',
      'muaalem_student.int8.onnx',
    ]) {
      final p = '${appDir.path}/$name';
      final f = File(p);
      if (await f.exists() && await f.length() > 1024 * 1024) {
        log('OnnxRecitationEngine: using downloaded model: $p '
            '(${await f.length()} bytes)',
            name: 'OnnxEngine');
        return p;
      }
    }

    // 3) من assets (fallback — يتطلّب أن يكون bundled في pubspec)
    final defaultPath = '${appDir.path}/muaalem_student.qdq.onnx';
    try {
      final bytes = await rootBundle.load('assets/models/muaalem_student.qdq.onnx');
      await File(defaultPath).writeAsBytes(bytes.buffer.asUint8List());
      log('OnnxRecitationEngine: extracted from assets to $defaultPath',
          name: 'OnnxEngine');
      return defaultPath;
    } catch (e) {
      log('OnnxRecitationEngine: model NOT FOUND. provided=${modelAssetPath!}, '
          'default=$defaultPath, assets=missing',
          name: 'OnnxEngine', level: 1000);
      throw Exception(
        'النموذج غير موجود. حمّله أولاً عبر زر "تنزيل النموذج".\n'
        'المسار المتوقّع: $defaultPath\n'
        'التفاصيل: $e',
      );
    }
  }

  Future<void> _loadVocab() async {
    String vocabJson;
    final vocabPath = vocabAssetPath;
    if (vocabPath != null && File(vocabPath).existsSync()) {
      vocabJson = await File(vocabPath).readAsString();
    } else {
      vocabJson = await rootBundle.loadString('assets/models/vocab_official.json');
    }
    _vocab = jsonDecode(vocabJson) as Map<String, dynamic>;
    // ابنِ خريطة id → token لِرأس phonemes
    final phonemes = _vocab['phonemes'] as Map<String, dynamic>;
    _phonemeIdToToken = {
      for (final entry in phonemes.entries)
        (entry.value as num).toInt(): entry.key,
    };
  }

  // ── العقد (RecitationEngine) ─────────────────────────────────

  @override
  Future<RecitationResult> correctRecitation({
    required final Uint8List wavBytes,
    final MuaalemConfig config = const MuaalemConfig(),
    final double errorRatio = 0.1,
  }) async {
    if (!_initialized) await initialize();

    // 1) فكّ ترميز WAV
    final decoded = decodeWavBytes(wavBytes);
    if (decoded == null) {
      return const RecitationResult(noMatchMessage: 'تعذّر قراءة ملفّ الصوت');
    }

    // 2) شغّل الاستدلال
    final outputs = _runInference(decoded.samples);

    // 3) فكّ ترميز CTC greedy لِرأس phonemes
    final phonemeIds = _ctcGreedyDecode(outputs['logits_0_phonemes']!);
    final predictedTokens =
        phonemeIds.map((id) => _phonemeIdToToken[id] ?? '?').join();
    final predictedPhonemes = predictedTokens.replaceAll('[PAD]', '').trim();

    // 4) فكّ ترميز رؤوس الصفات (10 رؤوس)
    final sifat = _decodeSifatHeads(outputs, phonemeIds);

    // 5) ابنِ RecitationResult
    // ملاحظة: التطابق مع النصّ المرجعي يتطلّب فهرس قرآني محلي (غير bundled).
    // حالياً نُعيد الفونيمات + الصفات المتوقَّعة. التطابق الكامل يتطلّب
    // تمرير النصّ المرجعي من التطبيق المُستهلك.
    return RecitationResult(
      predictedPhonemes: predictedPhonemes,
      errors: _buildSifatErrors(sifat),
    );
  }

  @override
  void dispose() {
    _session?.release();
    _session = null;
    _initialized = false;
  }

  // ── الاستدلال ─────────────────────────────────────────────────

  /// يشغّل النموذج وُيعيد مُخرجاته الخام (11 رأس logits).
  Map<String, Float32List> _runInference(final Float64List samples) {
    // حضّر المدخلات: audio (1, N) + attention_mask (1, N)
    final n = samples.length;
    final audio = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList(samples),
      [1, n],
    );
    final mask = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(List<int>.filled(n, 1)),
      [1, n],
    );

    final inputs = <String, OrtValue>{
      'audio': audio,
      'attention_mask': mask,
    };

    final runOpts = OrtRunOptions();
    // run يُعيد List<OrtValue?> مرتّبة حسب outputNames
    final outputs = _session!.run(runOpts, inputs, _outputNames);
    final result = <String, Float32List>{};
    for (var i = 0; i < outputs.length; i++) {
      final out = outputs[i];
      if (out == null) continue;
      final tensor = out as OrtValueTensor;
      final data = tensor.value as List;
      result[_outputNames[i]] = _flattenToFloat32(data);
      out.release();
    }
    audio.release();
    mask.release();
    runOpts.release();
    return result;
  }

  Float32List _flattenToFloat32(final List<dynamic> data) {
    final flat = <double>[];
    void recurse(final List<dynamic> d) {
      for (final item in d) {
        if (item is List) {
          recurse(item);
        } else if (item is num) {
          flat.add(item.toDouble());
        }
      }
    }
    recurse(data);
    return Float32List.fromList(flat);
  }

  // ── فكّ ترميز CTC ─────────────────────────────────────────────

  /// فكّ ترميز CTC greedy: argmax لِكلّ إطار → دمج المتكرّر → إسقاط blank.
  ///
  /// logits 1D بطول frames×vocab (لِعيّنة واحدة).
  List<int> _ctcGreedyDecode(final Float32List logits) {
    // logits مُسطّح: [frames × vocab]. نحتاج vocab size لِرأس phonemes = 43.
    const vocabSize = 43;
    final nFrames = logits.length ~/ vocabSize;
    if (nFrames == 0) return [];

    final result = <int>[];
    int prev = -1;
    for (int f = 0; f < nFrames; f++) {
      // ابحث عن أعلى احتمال في هذا الإطار
      int bestId = 0;
      double bestVal = logits[f * vocabSize];
      for (int v = 1; v < vocabSize; v++) {
        final val = logits[f * vocabSize + v];
        if (val > bestVal) {
          bestVal = val;
          bestId = v;
        }
      }
      // ادمج المتكرّر
      if (bestId != prev) {
        result.add(bestId);
      }
      prev = bestId;
    }
    // أسقط blank (id=0)
    return result.where((id) => id != 0).toList();
  }

  /// يفكّ ترميز رؤوس الصفات الـ10 لِكلّ فونيم متوقَّع.
  Map<String, List<int>> _decodeSifatHeads(
    final Map<String, Float32List> outputs,
    final List<int> phonemeFrames,
  ) {
    final sifat = <String, List<int>>{};
    // أسماء رؤوس الصفات (مطابقة لِـ النموذج)
    final sifatHeads = [
      'logits_1_hams_or_jahr',
      'logits_2_shidda_or_rakhawa',
      'logits_3_tafkheem_or_taqeeq',
      'logits_4_itbaq',
      'logits_5_safeer',
      'logits_6_qalqla',
      'logits_7_tikraar',
      'logits_8_tafashie',
      'logits_9_istitala',
      'logits_10_ghonna',
    ];
    // الفونيمات مُحاذاة مع الإطارات تقريبياً (نأخذ وسط كلّ فونيم)
    // تنفيذ مبسّط: نأخذ توقّعات الصفات عند الإطارات الوسطى.
    // تنفيذ كامل يتطلّب محاذاة إطار↔فونيم — مرحلة لاحقة.
    for (final head in sifatHeads) {
      sifat[head] = []; // placeholder
    }
    return sifat;
  }

  /// يبني قائمة أخطاء من الصفات (placeholder — مرحلة لاحقة).
  List<RecitationError> _buildSifatErrors(
    final Map<String, List<int>> sifat,
  ) {
    return const [];
  }
}
