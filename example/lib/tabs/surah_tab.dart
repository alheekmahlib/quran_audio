// تبويب السور — تشغيل السور الكاملة + اختيار القارئ + قائمة كل السور.
//
// Surah tab — full-surah playback + reciter selection + all-surahs list.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:quran_audio/quran_audio.dart';

import '../theme.dart';
import '../widgets.dart';

class SurahTab extends StatelessWidget {
  const SurahTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = QuranAudio.surahController;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const NowPlayingCard(),
        const SizedBox(height: 16),

        // اختيار القارئ / Reader selection
        SectionCard(
          titleAr: 'اختيار القارئ',
          titleEn: 'Select Reciter',
          child: Obx(() => DropdownButtonFormField<int>(
                initialValue: QuranAudio.surahReaderIndex,
                decoration: const InputDecoration(labelText: 'القارئ / Reciter'),
                items: [
                  for (final r in QuranAudio.surahReaders)
                    DropdownMenuItem(value: r.index, child: Text(r.name)),
                ],
                onChanged: (i) => QuranAudio.setSurahReader(i ?? 0),
              )),
        ),
        const SizedBox(height: 16),

        // تشغيل سورة بسرعة / Quick surah play
        SectionCard(
          titleAr: 'تشغيل سورة',
          titleEn: 'Play a Surah',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in [1, 2, 18, 36, 55, 67, 112, 113, 114])
                ActionChip(
                  label: Text(QuranAudio.surah(n).name),
                  avatar: Obx(() => Icon(
                        c.currentSurahNumber.value == n && c.isPlaying.value
                            ? Icons.volume_up_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                        color: AppColors.accent,
                      )),
                  onPressed: () => QuranAudio.playSurah(n),
                  backgroundColor: AppColors.surfaceLight,
                  side: BorderSide(color: AppColors.muted.withValues(alpha: 0.3)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // كل السور / All surahs
        SectionCard(
          titleAr: 'كل السور',
          titleEn: 'All Surahs',
          child: Column(
            children: [
              for (final s in QuranAudio.allSurahs)
                Obx(() {
                  final isCurrent = c.currentSurahNumber.value == s.number;
                  final isPlayingNow = isCurrent && c.isPlaying.value;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: isCurrent
                          ? AppColors.accent.withValues(alpha: 0.2)
                          : AppColors.surfaceLight,
                      child: Text('${s.number}',
                          style: TextStyle(
                              fontSize: 13,
                              color: isCurrent
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                    ),
                    title: Text(s.name,
                        style: TextStyle(
                            fontWeight:
                                isCurrent ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text('${s.englishName} • ${s.ayahCount} آية',
                        style: const TextStyle(fontSize: 12)),
                    trailing: Icon(
                      isPlayingNow
                          ? Icons.volume_up_rounded
                          : Icons.play_arrow_rounded,
                      color: isPlayingNow ? AppColors.accent : AppColors.textMuted,
                      size: 20,
                    ),
                    onTap: () => QuranAudio.playSurah(s.number),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}
