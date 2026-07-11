// Widgets مشتركة لإعادة الاستخدام — أزرار التحكم وبطاقة التشغيل.
//
// Shared reusable widgets — control buttons & player card.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:quran_audio/quran_audio.dart';

import 'theme.dart';

/// زر تحكم دائري بحجم لمس كافٍ (≥48dp) وتأثير لمسي ناعم.
///
/// Circular control button with adequate touch target (≥48dp) and soft feedback.
class ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final double size;
  final Color? color;

  const ControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.isPrimary = false,
    this.size = 48,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.accent, AppColors.accentLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: AppColors.softGlow(color: AppColors.accent, blur: 24),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: size + 8,
              height: size + 8,
              child: Icon(icon, color: Colors.white, size: size * 0.5),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceLight,
        shape: BoxShape.circle,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: color ?? AppColors.textPrimary, size: size * 0.45),
          ),
        ),
      ),
    );
  }
}

/// شريط التقدّم مع عرض الوقت الحالي/الكلي.
///
/// Progress bar with current/total time display.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: QuranAudio.positionDataStream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final pos = data?.position ?? Duration.zero;
        final dur = data?.duration ?? Duration.zero;
        final canSeek = dur.inSeconds > 0;

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.surfaceLight,
                thumbColor: Colors.white,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: pos.inMilliseconds
                    .toDouble()
                    .clamp(0, dur.inMilliseconds.toDouble().clamp(1, double.infinity)),
                max: dur.inMilliseconds.toDouble().clamp(1, double.infinity),
                onChanged: canSeek
                    ? (v) => QuranAudio.seek(Duration(milliseconds: v.toInt()))
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(pos),
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  Text(_fmt(dur),
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

/// صف أزرار التحكم الرئيسية (سابق/تشغيل-إيقاف/تالي/توقف).
///
/// Main control buttons row (prev/play-pause/next/stop).
class ControlRow extends StatelessWidget {
  const ControlRow({super.key});

  @override
  Widget build(BuildContext context) {
    // اقرأ قيم .value مباشرة داخل Obx حتى يلتقطها GetX.
    // Read .value directly inside Obx so GetX can track them.
    return Obx(() {
      // المسّ كل كنترولر ليقرأ .value ضمن نطاق Obx.
      final surahPlaying = QuranAudio.surahController.isPlaying.value;
      final ayahPlaying = QuranAudio.ayahController.isPlaying.value;
      final playing = surahPlaying || ayahPlaying;
      final hasActive = QuranAudio.hasActivePlayback;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ControlButton(
            icon: Icons.skip_previous_rounded,
            onPressed: hasActive ? QuranAudio.previous : null,
            size: 52,
          ),
          const SizedBox(width: 16),
          ControlButton(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onPressed: hasActive ? QuranAudio.togglePlayPause : null,
            isPrimary: true,
            size: 64,
          ),
          const SizedBox(width: 16),
          ControlButton(
            icon: Icons.skip_next_rounded,
            onPressed: hasActive ? QuranAudio.next : null,
            size: 52,
          ),
          const SizedBox(width: 12),
          ControlButton(
            icon: Icons.stop_rounded,
            onPressed: hasActive ? QuranAudio.stop : null,
            size: 44,
            color: AppColors.destructive,
          ),
        ],
      );
    });
  }
}

/// شريط معلومات صغير (label + value) للأكواد والشروحات.
///
/// Small info row (label + value) for code snippets and docs.
class InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const InfoChip({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.muted.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// كتلة كود تشرح دالة المكتبة (عربي + إنجليزي).
///
/// Code block explaining a library function (Arabic + English).
class CodeSnippet extends StatelessWidget {
  final String descriptionAr;
  final String descriptionEn;
  final String code;

  const CodeSnippet({
    super.key,
    required this.descriptionAr,
    required this.descriptionEn,
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16162B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(descriptionAr,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
          const SizedBox(height: 2),
          Text(descriptionEn,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  height: 1.3,
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F23),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              code,
              style: const TextStyle(
                color: AppColors.accentLight,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة قسم بعنوان ثنائي اللغة.
///
/// Section card with bilingual title.
class SectionCard extends StatelessWidget {
  final String titleAr;
  final String titleEn;
  final Widget child;

  const SectionCard({
    super.key,
    required this.titleAr,
    required this.titleEn,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titleAr,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(titleEn,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// بطاقة التشغيل الحالية — تعرض السورة/الآية الحالية + أزرار التحكم + شريط التقدّم.
/// مشتركة بين تبويبَي السور والآيات.
///
/// Now-playing card — shows the current surah/ayah + controls + progress bar.
/// Shared between the surah and ayah tabs.
class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({super.key});

  @override
  Widget build(BuildContext context) {
    // اقرأ قيم .value مباشرة داخل Obx حتى يلتقطها GetX.
    // Read .value directly inside Obx so GetX can track them.
    return Obx(() {
      // المسّ كلا الكنترولر ليقرأ .value ضمن نطاق Obx.
      final surahNo = QuranAudio.surahController.currentSurahNumber.value;
      final ayahNo = QuranAudio.ayahController.currentAyahInSurah.value;
      final meta = QuranAudio.surah(surahNo);
      final isAyah = QuranAudio.isAyahMode;

      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            children: [
              // أيقونة دائرية + اسم السورة
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.2),
                      AppColors.primaryLight.withValues(alpha: 0.3),
                    ],
                  ),
                ),
                child: const Icon(Icons.auto_stories_rounded,
                    color: AppColors.accent, size: 32),
              ),
              const SizedBox(height: 12),
              Text(meta.name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (isAyah)
                Text('$ayahNo / ${meta.ayahCount}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14))
              else
                Text('${meta.englishName} • ${meta.ayahCount} آية',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 18),
              const ControlRow(),
              const SizedBox(height: 8),
              const ProgressBar(),
            ],
          ),
        ),
      );
    });
  }
}
