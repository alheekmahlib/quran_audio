import '../../enums/repeat_mode.dart';

/// إعدادات التكرار - تحدد ما يحدث عند انتهاء التشغيل الحالي.
///
/// Repeat configuration — defines behavior when the current playback completes.
class RepeatConfig {
  final RepeatMode mode;

  /// للنطاق: أول آية في النطاق / For range mode: first ayah in the range.
  final int? fromAyah;

  /// للنطاق: آخر آية في النطاق / For range mode: last ayah in the range.
  final int? toAyah;

  /// عدد مرات التكرار (null = لانهائي) / Repeat count (null = infinite).
  final int? times;

  /// عدد التكرارات المنفّذة حتى الآن / Repeats completed so far.
  int currentCount;

  /// مُنشئ داخلي للـ factories (لأن currentCount قابل للتغيير، لا يمكن const).
  RepeatConfig._(this.mode)
      : fromAyah = null,
        toAyah = null,
        times = null,
        currentCount = 0;

  /// مُنشئ عام.
  RepeatConfig({
    this.mode = RepeatMode.off,
    this.fromAyah,
    this.toAyah,
    this.times,
    this.currentCount = 0,
  });

  /// تكوين افتراضي بدون تكرار / Default config with no repeat.
  factory RepeatConfig.off() => RepeatConfig._(RepeatMode.off);

  /// تكوين تكرار آية واحدة / Config for repeating a single ayah.
  factory RepeatConfig.one() => RepeatConfig._(RepeatMode.one);

  /// تكوين تكرار سورة كاملة / Config for repeating a full surah.
  factory RepeatConfig.surah() => RepeatConfig._(RepeatMode.surah);

  /// تكوين تكرار نطاق من الآيات / Config for repeating an ayah range.
  factory RepeatConfig.range({
    required int fromAyah,
    required int toAyah,
    int? times,
  }) =>
      RepeatConfig(
        mode: RepeatMode.range,
        fromAyah: fromAyah,
        toAyah: toAyah,
        times: times,
      );

  /// هل اكتمل عدد التكرارات؟ / Has the repeat count been exhausted?
  bool get isExhausted {
    if (times == null) return false; // لانهائي / infinite
    return currentCount >= times!;
  }

  /// زيادة عدّاد التكرار / Increment the repeat counter.
  void increment() => currentCount++;

  RepeatConfig copyWith({
    RepeatMode? mode,
    int? fromAyah,
    int? toAyah,
    int? times,
    int? currentCount,
  }) {
    return RepeatConfig(
      mode: mode ?? this.mode,
      fromAyah: fromAyah ?? this.fromAyah,
      toAyah: toAyah ?? this.toAyah,
      times: times ?? this.times,
      currentCount: currentCount ?? this.currentCount,
    );
  }

  @override
  String toString() =>
      'RepeatConfig(mode: $mode, fromAyah: $fromAyah, toAyah: $toAyah, '
      'times: $times, currentCount: $currentCount)';
}
