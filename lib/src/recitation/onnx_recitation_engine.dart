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
import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'package:quran_audio/src/recitation/models/muaalem_config.dart';
import 'package:quran_audio/src/recitation/models/recitation_result.dart';
import 'package:quran_audio/src/recitation/phoneme_aligner.dart';
import 'package:quran_audio/src/recitation/error_detector.dart';
import 'package:quran_audio/src/recitation/quran_phoneme_db.dart';
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
  OnnxRecitationEngine({
    this.modelAssetPath,
    this.vocabAssetPath,
    this.quranDbPath,
  });

  /// مسار النموذج (إن كان bundled) أو null لِـ مسار خارجي.
  final String? modelAssetPath;
  final String? vocabAssetPath;

  /// مسار قاعدة بيانات الفونيمات المرجعية (JSON.gz) أو null لِـ asset.
  final String? quranDbPath;

  OrtSession? _session;
  Map<String, dynamic> _vocab = {};
  Map<int, String> _phonemeIdToToken = {};
  bool _initialized = false;
  String? _modelPath;
  List<String> _outputNames = [];
  final QuranPhonemeDb _quranDb = QuranPhonemeDb();

  /// هل المحرّك جاهز.
  @override
  Future<bool> isHealthy() async => _initialized && _session != null;

  /// (offline) نصّ آية عثماني من DB.
  @override
  String? getVerseText({required int suraIdx, required int ayaIdx}) {
    if (!_quranDb.isLoaded) return null;
    return _quranDb.getReference(suraIdx: suraIdx, ayaIdx: ayaIdx)?.uthmani;
  }

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

    // 2ب) حمّل قاعدة بيانات الفونيمات المرجعية (1.4MB)
    try {
      await _quranDb.load(filePath: quranDbPath);
      log('OnnxRecitationEngine: quran DB loaded (${_quranDb.verseCount} verses)',
          name: 'OnnxEngine');
    } catch (e) {
      log('OnnxRecitationEngine: quran DB load failed (offline compare disabled): $e',
          name: 'OnnxEngine', level: 900);
      // لا نفشل — الـDB اختياري (نُنتج فونيمات فقط)
    }

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
    // ابنِ خريطة id → token لِرأس phonemes.
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
    final int? suraIdx,
    final int? ayaIdx,
    final String? referenceText,
  }) async {
    if (!_initialized) await initialize();

    // 1) فكّ ترميز WAV
    final decoded = decodeWavBytes(wavBytes);
    if (decoded == null) {
      return const RecitationResult(noMatchMessage: 'تعذّر قراءة ملفّ الصوت');
    }

    // 🔍 تشخيص: سجّل خصائص الصوت الوارد لِكشف مشاكل الإدخال.
    // Audio diagnostics: log incoming signal characteristics.
    final samples = decoded.samples;
    final nSamples = samples.length;
    double minV = samples.isNotEmpty ? samples[0] : 0;
    double maxV = samples.isNotEmpty ? samples[0] : 0;
    double sumSq = 0;
    int nonZero = 0;
    for (final s in samples) {
      if (s < minV) minV = s;
      if (s > maxV) maxV = s;
      sumSq += s * s;
      if (s.abs() > 1e-4) nonZero++;
    }
    final rms = nSamples > 0 ? sqrt(sumSq / nSamples) : 0.0;
    log('OnnxRecitationEngine: audio in — '
        'samples=$nSamples (${(nSamples / decoded.sampleRate).toStringAsFixed(1)}s) '
        'sr=${decoded.sampleRate} '
        'min=${minV.toStringAsFixed(3)} max=${maxV.toStringAsFixed(3)} '
        'rms=${rms.toStringAsFixed(4)} nonZero=$nonZero',
        name: 'OnnxEngine');

    // 1ب) قصّ الصمت من البداية والنهاية (VAD trim).
    //
    // النموذج يخطئ في أول كلمة عند بدء التسجيل بِـ صمت متدرّج (نمط ASR
    // معروف: سماع 'ءَ زَ' بدل 'بِ س' في البسملة). القصّ يُغذّي النموذج
    // الكلام مباشرةً من أوّل صوت مسموع.
    //
    // Trim leading/trailing silence so the model hears speech from the very
    // first frame instead of a fading-in start (fixes first-word errors).
    final int vadStart;
    final int vadEnd;
    final peak = maxV.abs() > minV.abs() ? maxV.abs() : minV.abs();
    {
      const windowMs = 100; // نافذة فحص 100ms
      final win = decoded.sampleRate * windowMs ~/ 1000;
      final nWin = nSamples ~/ win;
      if (nWin >= 3 && peak > 1e-6) {
        // عتبات مُتكيّفة مع كلّ تسجيل:
        // - البداية 8%: الضجيج وضغط الزرّ قبل الكلام.
        // - النهاية 3% + هامش 3 نوافذ: الحرف الأخير (نون/ميم خفيفة عند
        //   الوقف) طاقته منخفضة بِـ الطبيعة — عتبة البداية نفسها كانت
        //   تقصّه! (قصّت 4s من تسجيل 7.6s وأسقطت نون «العالمين»).
        double maxWinE = 0;
        final winE = Float64List(nWin);
        for (var w = 0; w < nWin; w++) {
          double e = 0;
          for (var i = w * win; i < (w + 1) * win; i++) {
            e += samples[i] * samples[i];
          }
          winE[w] = e;
          if (e > maxWinE) maxWinE = e;
        }
        final startThr = maxWinE * 0.08;
        final endThr = maxWinE * 0.03;
        var first = 0;
        while (first < nWin && winE[first] < startThr) {
          first++;
        }
        var last = nWin - 1;
        while (last > first && winE[last] < endThr) {
          last--;
        }
        // هوامش أمان: نافذة قبل البداية، و3 نوافذ (300ms) بعد آخر صوت
        // خفيف — لِـ عدم قطع الحرف الأخير.
        final startW = first > 0 ? first - 1 : 0;
        var endW = last + 3; // 3 نوافذ هامش نهاية
        if (endW > nWin - 1) endW = nWin - 1;
        vadStart = startW * win;
        vadEnd = (endW + 1) * win > nSamples ? nSamples : (endW + 1) * win;
      } else {
        vadStart = 0;
        vadEnd = nSamples;
      }
    }
    final trimmed = (vadStart == 0 && vadEnd == nSamples)
        ? samples
        : Float64List.sublistView(samples, vadStart, vadEnd);
    final nTrim = trimmed.length;
    if (nTrim < nSamples) {
      final trimmedSec = (nSamples - nTrim) / decoded.sampleRate;
      final finalSec = nTrim / decoded.sampleRate;
      log('OnnxRecitationEngine: VAD trim '
          '${nSamples - nTrim} samples (${trimmedSec.toStringAsFixed(2)}s) '
          '→ $nTrim samples (${finalSec.toStringAsFixed(1)}s)',
          name: 'OnnxEngine');
    }

    // 1ج) تطبيع السعة لِمطابقة توزيع بيانات التدريب.
    //
    // النموذج دُرِّب على تسجيلات everyayah النظيفة بِـ RMS ~0.05-0.10 وَpeak
    // ~0.5-0.9. ميكروفون المحاكي (مع autoGain/noiseSuppress) يُنتج صوتاً
    // خافتاً جدّاً (RMS ~0.007، peak ~0.04) — النموذج يتصرّف وكأنّه صمت.
    //
    // الحلّ: peak-normalize لِـ 0.7 (سعة قويّة لكنها آمنة من clipping)،
    // ثمّ طبّق gain إضافيّ إذا كان RMS لا يزال منخفضاً.
    //
    // The model was trained on clean everyayah audio (RMS ~0.05-0.10). The
    // simulator mic produces very faint audio (RMS ~0.007), so the model
    // treats it as silence. Fix: peak-normalize to 0.7, then boost if RMS
    // is still low.
    final Float64List normalized;
    if (peak < 1e-6) {
      // صمت تامّ — لا شيء نُطبّقه عليه.
      normalized = trimmed;
    } else {
      // Scale لِـ peak = 0.7.
      final scale = 0.7 / peak;
      normalized = Float64List(nTrim);
      for (var i = 0; i < nTrim; i++) {
        normalized[i] = trimmed[i] * scale;
      }
      // تحقّق: إن كان RMS بعد الـ scaling لا يزال منخفضاً (< 0.03)،
      // ارفعه لِـ 0.06 (نطاق التدريب).
      double sumSq2 = 0;
      for (final s in normalized) {
        sumSq2 += s * s;
      }
      final rms2 = sqrt(sumSq2 / nTrim);
      if (rms2 < 0.03) {
        final boost = 0.06 / (rms2 < 1e-6 ? 1e-6 : rms2);
        final cappedBoost = boost > 20.0 ? 20.0 : boost;
        for (var i = 0; i < nTrim; i++) {
          var v = normalized[i] * cappedBoost;
          if (v > 1.0) v = 1.0;
          if (v < -1.0) v = -1.0;
          normalized[i] = v;
        }
        log('OnnxRecitationEngine: normalized (peak 0.7, boost '
            '${cappedBoost.toStringAsFixed(2)}x)',
            name: 'OnnxEngine');
      } else {
        log('OnnxRecitationEngine: normalized (peak 0.7, rms '
            '${rms2.toStringAsFixed(4)} ok)',
            name: 'OnnxEngine');
      }
    }

    // 2) شغّل الاستدلال
    final outputs = _runInference(normalized);

    // 3) فكّ ترميز CTC greedy لِرأس phonemes + محاذاة الإطارات
    final nFrames =
        outputs['logits_0_phonemes']!.length ~/ 43; // vocab=43

    // 🔍 تشخيص: افحص الـ logits الأوّلى لِتحديد ما إذا كان النموذج يُنتج
    // all-blanks (id=0) بثقة عالية، أم أنّ هناك فونيمات.
    {
      const vocabSize = 43;
      final log0 = outputs['logits_0_phonemes']!;
      final lim = nFrames < 8 ? nFrames : 8;
      final sample = <String>[];
      for (var f = 0; f < lim; f++) {
        int bestId = 0;
        double bestVal = log0[f * vocabSize];
        for (var v = 1; v < vocabSize; v++) {
          final v2 = log0[f * vocabSize + v];
          if (v2 > bestVal) { bestVal = v2; bestId = v; }
        }
        sample.add('$bestId(${bestVal.toStringAsFixed(1)})');
      }
      // أعلى logit عبر كلّ الإطارات لِكشف التشتّت.
      double maxLogit = -1e9;
      for (var i = 0; i < log0.length; i++) {
        if (log0[i] > maxLogit) maxLogit = log0[i];
      }
      log('OnnxRecitationEngine: logits0 — '
          'nFrames=$nFrames frames[:8]=${sample.join(' ')} '
          'globalMax=${maxLogit.toStringAsFixed(2)}',
          name: 'OnnxEngine');
    }

    final decodeResult = _ctcGreedyDecodeAligned(
      outputs['logits_0_phonemes']!,
      nFrames,
    );
    final phonemeIds = decodeResult.ids;
    final predictedTokens =
        phonemeIds.map((id) => _phonemeIdToToken[id] ?? '?').join();
    final predictedPhonemes = predictedTokens.replaceAll('[PAD]', '').trim();
    log('OnnxRecitationEngine: decoded → ${phonemeIds.length} ids: '
        '$predictedPhonemes',
        name: 'OnnxEngine');

    // 4) المسار الكامل: إن أُعطي suraIdx/ayaIdx وَالـDB محمّلة،
    //    استخدم المحاذاة الجماعيّة + كشّاف الأخطاء المُطابق لِـ الخادم.
    if (suraIdx != null && ayaIdx != null && _quranDb.isLoaded) {
      final ref = _quranDb.getReference(suraIdx: suraIdx, ayaIdx: ayaIdx);
      if (ref != null) {
        // تجميع المدود + محاذاة جماعيّة (مثل chunck_phonemes + Levenshtein).
        final refGroups = chunkPhonemes(ref.phonemeIds);
        final predGroups = chunkPhonemes(phonemeIds);
        final ops = alignGroups(refGroups, predGroups);
        final stats = computeGroupStats(ops);
        log('OnnxRecitationEngine: group-aligned ${ref.verseKey} — '
            'refGroups=${refGroups.length} predGroups=${predGroups.length} $stats',
            name: 'OnnxEngine');

        // رفض بِـ 0 تطابقات (تلاوة غير مفهومة).
        if (stats.matches == 0 && stats.totalOps > 0) {
          return RecitationResult(
            uthmaniText: ref.uthmani,
            predictedPhonemes: predictedPhonemes,
            noMatchMessage:
                'لم يتمكّن النموذج من التعرّف على التلاوة. حاول مرّة أخرى '
                'بِالتحدّث بِـوضوح أقرب من الميكروفون.',
          );
        }

        // كشّاف الأخطاء الجماعيّ (مُطابق لِـ explain_error الخادم).
        final errors = buildErrorsFromAlignment(
          ops: ops,
          referenceVerse: ref,
          phonemeIdToToken: _phonemeIdToToken,
        );

        log('OnnxRecitationEngine: errors → ${errors.length} '
            '(tajweed=${errors.where((e) => e.errorType == "tajweed").length}, '
            'normal=${errors.where((e) => e.errorType == "normal").length}, '
            'tashkeel=${errors.where((e) => e.errorType == "tashkeel").length})',
            name: 'OnnxEngine');

        return RecitationResult(
          uthmaniText: ref.uthmani,
          predictedPhonemes: predictedPhonemes,
          referencePhonemes: ref.phonemes,
          errors: errors,
          start: SurahAyahPosition(suraIdx: suraIdx, ayaIdx: ayaIdx),
          end: SurahAyahPosition(suraIdx: suraIdx, ayaIdx: ayaIdx),
        );
      }
      log('OnnxRecitationEngine: verse $suraIdx:$ayaIdx not in DB',
          name: 'OnnxEngine', level: 900);
    }

    // 5) مسار بسيط: لا DB → أعد الفونيمات فقط (بدون أخطاء مُلفّقة).
    if (referenceText != null && referenceText.isNotEmpty) {
      return RecitationResult(
        uthmaniText: referenceText,
        predictedPhonemes: predictedPhonemes,
        referencePhonemes: referenceText,
      );
    }

    return RecitationResult(
      predictedPhonemes: predictedPhonemes,
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
}

