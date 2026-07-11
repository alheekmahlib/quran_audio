import 'package:just_audio/just_audio.dart';

/// بيانات الموضع المدمجة - تُستخدم في seek bar لعرض الموضع/المدة الكلية.
///
/// Combined position data — used by the seek bar (position / buffered / duration).
class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  const PositionData(
    this.position,
    this.bufferedPosition,
    this.duration,
  );

  factory PositionData.fromPlayerState(PlayerState state) {
    return const PositionData(
      Duration.zero,
      Duration.zero,
      Duration.zero,
    );
  }

  @override
  String toString() =>
      'PositionData(position: $position, buffered: $bufferedPosition, duration: $duration)';
}
