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

/// نتيجة فكّ ترميز CTC مَع محاذاة الإطارات.
class _CtcDecodeResult {
  _CtcDecodeResult({required this.ids, required this.frameSpans});
  final List<int> ids; // معرّفات الفونيمات (بِدون blank)
  final List<_FrameSpan> frameSpans; // مدى الإطارات لِكلّ فونيم
}

/// مدى إطارات لِفونيم واحد (لِـ معرفة موضع فكّ ترميز الصفات).
class _FrameSpan {
  _FrameSpan({required this.startFrame, required this.endFrame});
  final int startFrame;
  final int endFrame;
}

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
    // ابنِ خريطة id → token لِكلّ رأس
    final phonemes = _vocab['phonemes'] as Map<String, dynamic>;
    _phonemeIdToToken = {
      for (final entry in phonemes.entries)
        (entry.value as num).toInt(): entry.key,
    };
    // خريطة لِرؤوس الصفات (id → token عربي بِأقواس)
    _sifatIdToToken = {};
    for (final head in _sifatHeadNames) {
      final headVocab = _vocab[head] as Map<String, dynamic>?;
      if (headVocab == null) continue;
      _sifatIdToToken[head] = {
        for (final e in headVocab.entries) (e.value as num).toInt(): e.key,
      };
    }
  }

  /// أسماء رؤوس الصفات الـ10 (تُطابق vocab_official.json).
  static const _sifatHeadNames = [
    'hams_or_jahr',
    'shidda_or_rakhawa',
    'tafkheem_or_taqeeq',
    'itbaq',
    'safeer',
    'qalqla',
    'tikraar',
    'tafashie',
    'istitala',
    'ghonna',
  ];

  /// خريطة head → {id → token عربي}.
  Map<String, Map<int, String>> _sifatIdToToken = {};

  // ── العقد (RecitationEngine) ─────────────────────────────────

  @override
  Future<RecitationResult> correctRecitation({
    required final Uint8List wavBytes,
    final MuaalemConfig config = const MuaalemConfig(),
    final double errorRatio = 0.1,
    final String? referenceText,
  }) async {
    if (!_initialized) await initialize();

    // 1) فكّ ترميز WAV
    final decoded = decodeWavBytes(wavBytes);
    if (decoded == null) {
      return const RecitationResult(noMatchMessage: 'تعذّر قراءة ملفّ الصوت');
    }

    // 2) شغّل الاستدلال
    final outputs = _runInference(decoded.samples);

    // 3) فكّ ترميز CTC greedy لِرأس phonemes + محاذاة الإطارات
    final nFrames =
        outputs['logits_0_phonemes']!.length ~/ 43; // vocab=43
    final decodeResult = _ctcGreedyDecodeAligned(
      outputs['logits_0_phonemes']!,
      nFrames,
    );
    final phonemeIds = decodeResult.ids;
    final predictedTokens =
        phonemeIds.map((id) => _phonemeIdToToken[id] ?? '?').join();
    final predictedPhonemes = predictedTokens.replaceAll('[PAD]', '').trim();

    // 4) فكّ ترميز رؤوس الصفات عند مواضع الفونيمات المتوقَّعة
    final sifatPerPhoneme = _decodeSifatAtPhonemes(outputs, decodeResult);

    // 5) ابنِ أخطاء التجويد من الصفات (تفصيل غني)
    final errors = _buildSifatErrorsRich(sifatPerPhoneme);

    // 6) إن أُعطي نصّ مرجعي، اعرضه كَـ uthmaniText مع الفونيمات
    if (referenceText != null && referenceText.isNotEmpty) {
      return RecitationResult(
        uthmaniText: referenceText,
        predictedPhonemes: predictedPhonemes,
        referencePhonemes: referenceText,
        errors: errors,
      );
    }

    // بدون نصّ مرجعي: الفونيمات + صفات الحروف فقط
    return RecitationResult(
      predictedPhonemes: predictedPhonemes,
      errors: errors,
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

  // ── فكّ ترميز CTC + محاذاة ─────────────────────────────────────

  /// فكّ ترميز CTC greedy مَع تتبّع موضع كلّ فونيم.
  ///
  /// نُحدّد لِكلّ فونيم مدى الإطارات التي تنبّأ فيها، ثمّ نأخذ
  /// وسط المدى لِـ فكّ ترميز الصفات بدقّة.
  _CtcDecodeResult _ctcGreedyDecodeAligned(
    final Float32List logits,
    final int nFrames,
  ) {
    const vocabSize = 43;
    if (nFrames == 0) {
      return _CtcDecodeResult(ids: const [], frameSpans: const []);
    }

    // أوّلاً: argmax لِكلّ إطار
    final frameArgmax = List<int>.filled(nFrames, 0);
    for (int f = 0; f < nFrames; f++) {
      int bestId = 0;
      double bestVal = logits[f * vocabSize];
      for (int v = 1; v < vocabSize; v++) {
        final val = logits[f * vocabSize + v];
        if (val > bestVal) {
          bestVal = val;
          bestId = v;
        }
      }
      frameArgmax[f] = bestId;
    }

    // ثانياً: ادمج المتكرّر وسجّل المدى
    final ids = <int>[];
    final spans = <_FrameSpan>[];
    int prev = -1;
    int runStart = 0;
    for (int f = 0; f < nFrames; f++) {
      final cur = frameArgmax[f];
      if (cur != prev) {
        if (prev != -1 && prev != 0) {
          // أغلق مدى الفونيم السابق
          ids.add(prev);
          spans.add(_FrameSpan(startFrame: runStart, endFrame: f - 1));
        }
        prev = cur;
        runStart = f;
      }
    }
    // آخر فونيم
    if (prev != -1 && prev != 0) {
      ids.add(prev);
      spans.add(_FrameSpan(startFrame: runStart, endFrame: nFrames - 1));
    }

    return _CtcDecodeResult(ids: ids, frameSpans: spans);
  }

  /// يفكّ ترميز رؤوس الصفات الـ10 عند موضع كلّ فونيم متوقَّع.
  ///
  /// يُعيد لِكلّ فونيم: قائمة بِـ {head: token} (صفات ذلك الفونيم).
  List<Map<String, String>> _decodeSifatAtPhonemes(
    final Map<String, Float32List> outputs,
    final _CtcDecodeResult decode,
  ) {
    // خريطة اسم الرأس في النموذج → اسم الرأس في vocab
    const outputToVocab = {
      'logits_1_hams_or_jahr': 'hams_or_jahr',
      'logits_2_shidda_or_rakhawa': 'shidda_or_rakhawa',
      'logits_3_tafkheem_or_taqeeq': 'tafkheem_or_taqeeq',
      'logits_4_itbaq': 'itbaq',
      'logits_5_safeer': 'safeer',
      'logits_6_qalqla': 'qalqla',
      'logits_7_tikraar': 'tikraar',
      'logits_8_tafashie': 'tafashie',
      'logits_9_istitala': 'istitala',
      'logits_10_ghonna': 'ghonna',
    };

    final result = <Map<String, String>>[];
    for (var p = 0; p < decode.ids.length; p++) {
      final span = decode.frameSpans[p];
      final midFrame = (span.startFrame + span.endFrame) ~/ 2;
      final sifat = <String, String>{};

      for (final entry in outputToVocab.entries) {
        final logits = outputs[entry.key];
        if (logits == null) continue;
        final vocabName = entry.value;
        final headVocab = _vocab[vocabName] as Map<String, dynamic>?;
        if (headVocab == null) continue;
        final vocabSize = headVocab.length;
        if (midFrame * vocabSize + vocabSize > logits.length) continue;

        // argmax عند الإطار الأوسط
        int bestId = 0;
        double bestVal = logits[midFrame * vocabSize];
        for (int v = 1; v < vocabSize; v++) {
          final val = logits[midFrame * vocabSize + v];
          if (val > bestVal) {
            bestVal = val;
            bestId = v;
          }
        }
        // حوّل id → token عربي
        if (bestId != 0) {
          final token = _sifatIdToToken[vocabName]?[bestId];
          if (token != null) {
            sifat[vocabName] = token;
          }
        }
      }
      result.add(sifat);
    }
    return result;
  }

  /// يبني أخطاء تجويد غنية من الصفات المُكتشَفة.
  ///
  /// يُنتج RecitationError واحد لِكلّ صفة "إيجابية" مُكتشَفة
  /// (مثل قلقلة، تفخيم، غنّة...) بِـ TajweedRule.
  List<RecitationError> _buildSifatErrorsRich(
    final List<Map<String, String>> sifatPerPhoneme,
  ) {
    // خريطة رأس الصفة → {اسم عربي، اسم إنجليزي}
    const sifatMeta = {
      'hams_or_jahr': ('الهمس والجهر', 'hams_or_jahr'),
      'shidda_or_rakhawa': ('الشدّة والرخاوة', 'shidda_or_rakhawa'),
      'tafkheem_or_taqeeq': ('التفخيم والترقيق', 'tafkheem_or_taqeeq'),
      'itbaq': ('الإطباق', 'itbaq'),
      'safeer': ('الصفير', 'safeer'),
      'qalqla': ('القلقلة', 'qalqla'),
      'tikraar': ('التكرار', 'tikraar'),
      'tafashie': ('التفشّي', 'tafashie'),
      'istitala': ('الاستطالة', 'istitala'),
      'ghonna': ('الغُنّة', 'ghonna'),
    };

    final errors = <RecitationError>[];
    for (var i = 0; i < sifatPerPhoneme.length; i++) {
      final sifat = sifatPerPhoneme[i];
      for (final entry in sifat.entries) {
        final headName = entry.key;
        final token = entry.value; // مثل "[مقلقل]"
        final meta = sifatMeta[headName];
        if (meta == null) continue;

        // تخطّي الصفات "السلبية" (لا صفير، لا قلقلة...) — ليست أخطاء
        if (token.contains('لا ')) continue;

        final rule = TajweedRule(
          nameAr: token,
          nameEn: meta.$2,
          correctnessType: 'sifa',
        );
        errors.add(RecitationError(
          errorType: 'tajweed',
          speechErrorType: 'replace',
          phPos: [i, i + 1],
          insertedTajweedRules: [rule],
        ));
      }
    }
    return errors;
  }
}
