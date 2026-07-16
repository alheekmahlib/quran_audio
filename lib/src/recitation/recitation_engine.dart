/// واجهة مجرّدة لِمحرّك تقييم التلاوة.
///
/// تتيح للمكتبة العمل بِـ محرّكَين:
/// - [MuaalemClient] (online): يتواصل مع خادم quran-muaalem.
/// - [OnnxRecitationEngine] (offline): يشغّل نموذج ONNX محليّاً.
///
/// العقد الوحيد: [correctRecitation] يأخذ صوت WAV (16kHz mono) وُيعيد
/// [RecitationResult] بِنفس بنية الخادم.
library;

import 'dart:typed_data';

import 'package:quran_audio/src/recitation/models/muaalem_config.dart';
import 'package:quran_audio/src/recitation/models/recitation_result.dart';

/// محرّك تقييم التلاوة (online أو offline).
abstract interface class RecitationEngine {
  /// يُقيّم تلاوةً من بيانات WAV.
  ///
  /// [wavBytes] بيانات ملفّ WAV (16kHz mono).
  /// [config] إعدادات المصحف (Hafs/Warsh، أطوال المدود...).
  /// [errorRatio] نسبة التسامح في المطابقة (0-1).
  /// [referenceText] (اختياري، offline) نصّ الآية العثماني المُتوقَّع —
  ///   إن أُعطي، يُقارن النموذج الفونيمات المتوقَّعة بِفونيمات النصّ المرجعي
  ///   ويُنتج أخطاء تجويد مُفصّلة. إن لم يُعطَ، يُعيد الفونيمات المتوقَّعة فقط.
  Future<RecitationResult> correctRecitation({
    required final Uint8List wavBytes,
    final MuaalemConfig config = const MuaalemConfig(),
    final double errorRatio = 0.1,
    final String? referenceText,
  });

  /// هل المحرّك جاهز لِلاستخدام؟ (خادم صحّي / نموذج محمّل).
  Future<bool> isHealthy();

  /// تحرير الموارد.
  void dispose();
}
