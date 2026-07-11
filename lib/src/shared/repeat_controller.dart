import '../enums/repeat_mode.dart';
import 'models/repeat_config.dart';

/// متحكّم التكرار - يقرّر ما يحدث عند اكتمال التشغيل الحالي.
///
/// Repeat controller — decides what happens when the current playback completes.
class RepeatController {
  RepeatController();

  RepeatConfig _config = RepeatConfig.off();
  RepeatConfig get config => _config;
  RepeatMode get mode => _config.mode;

  /// فعّل نمط التكرار / Set the repeat mode.
  void setMode(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        _config = RepeatConfig.off();
        break;
      case RepeatMode.one:
        _config = RepeatConfig.one();
        break;
      case RepeatMode.surah:
        _config = RepeatConfig.surah();
        break;
      case RepeatMode.range:
        // للنطاق استخدم setRange / for range use setRange
        _config = RepeatConfig.off();
        break;
    }
  }

  /// فعّل تكرار آية واحدة / Enable single-ayah repeat.
  void setOne() => _config = RepeatConfig.one();

  /// فعّل تكرار السورة / Enable full-surah repeat.
  void setSurah() => _config = RepeatConfig.surah();

  /// فعّل تكرار نطاق آيات / Enable ayah-range repeat.
  void setRange({required int fromAyah, required int toAyah, int? times}) {
    _config = RepeatConfig.range(
      fromAyah: fromAyah,
      toAyah: toAyah,
      times: times,
    );
  }

  /// أوقف التكرار / Disable repeat.
  void off() => _config = RepeatConfig.off();

  /// هل التكرار مفعّل؟ / Is repeat enabled?
  bool get isEnabled => _config.mode != RepeatMode.off;

  /// عند اكتمال آية/سورة - يقرّر الإجراء المطلوب.
  ///
  /// Called when playback completes. Returns the action to take.
  RepeatAction onCompleted({
    required int currentSurah,
    required int currentAyah,
  }) {
    switch (_config.mode) {
      case RepeatMode.off:
        return const RepeatActionProceedNext();
      case RepeatMode.one:
        return const RepeatActionReplayCurrent();
      case RepeatMode.surah:
        return const RepeatActionReplaySurah();
      case RepeatMode.range:
        final reachedEnd = currentAyah >= (_config.toAyah ?? currentAyah);
        if (reachedEnd) {
          if (_config.isExhausted) {
            return const RepeatActionStop();
          }
          _config.increment();
          return RepeatActionReplayRange(fromAyah: _config.fromAyah!);
        }
        return const RepeatActionProceedNext();
    }
  }
}

/// إجراء التكرار المُقترح / The suggested repeat action.
sealed class RepeatAction {
  const RepeatAction();
}

/// تابع للتالي (آية/سورة تالية) / Proceed to next.
class RepeatActionProceedNext extends RepeatAction {
  const RepeatActionProceedNext();
}

/// أعِد تشغيل الحالي / Replay current.
class RepeatActionReplayCurrent extends RepeatAction {
  const RepeatActionReplayCurrent();
}

/// أعِد تشغيل السورة من البداية / Replay surah from start.
class RepeatActionReplaySurah extends RepeatAction {
  const RepeatActionReplaySurah();
}

/// أعِد تشغيل من آية معيّنة (نطاق) / Replay from a specific ayah (range).
class RepeatActionReplayRange extends RepeatAction {
  final int fromAyah;
  const RepeatActionReplayRange({required this.fromAyah});
}

/// توقف / Stop.
class RepeatActionStop extends RepeatAction {
  const RepeatActionStop();
}
