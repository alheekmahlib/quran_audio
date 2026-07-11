// تبويب الآيات — تشغيل آية محددة بإدخال يدوي + أمثلة سريعة + التكرار.
//
// Ayah tab — play a specific ayah via manual input + quick examples + repeat.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:quran_audio/quran_audio.dart';

import '../theme.dart';
import '../widgets.dart';

class AyahTab extends StatelessWidget {
  const AyahTab({super.key});

  @override
  Widget build(BuildContext context) {
    // متحكمات الإدخال اليدوي / Manual input controllers
    final surahCtrl = TextEditingController(text: '2');
    final ayahCtrl = TextEditingController(text: '255');
    final c = QuranAudio.ayahController;

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
                initialValue: QuranAudio.ayahReaderIndex,
                decoration: const InputDecoration(labelText: 'القارئ / Reciter'),
                items: [
                  for (final r in QuranAudio.ayahReaders)
                    DropdownMenuItem(value: r.index, child: Text(r.name)),
                ],
                onChanged: (i) => QuranAudio.setAyahReader(i ?? 0),
              )),
        ),
        const SizedBox(height: 16),

        // الإدخال اليدوي لرقم السورة والآية / Manual surah & ayah input
        SectionCard(
          titleAr: 'تشغيل آية محددة',
          titleEn: 'Play a Specific Ayah',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // رقم السورة / Surah number
                  Expanded(
                    child: TextField(
                      controller: surahCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'رقم السورة',
                        hintText: '1 - 114',
                        prefixIcon: Icon(Icons.menu_book_rounded, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // رقم الآية / Ayah number
                  Expanded(
                    child: TextField(
                      controller: ayahCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'رقم الآية',
                        hintText: 'Ayah #',
                        prefixIcon: Icon(Icons.format_quote_rounded, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // نمط التشغيل: آية واحدة أم متابعة / Play mode toggle
              Obx(() => SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false,
                          icon: Icon(Icons.playlist_play_rounded, size: 18),
                          label: Text('متابعة')),
                      ButtonSegment(
                          value: true,
                          icon: Icon(Icons.looks_one_rounded, size: 18),
                          label: Text('آية واحدة')),
                    ],
                    selected: {c.playSingleAyah.value},
                    onSelectionChanged: (v) => c.playSingleAyah.value = v.first,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? AppColors.accent.withValues(alpha: 0.2)
                              : AppColors.surfaceLight),
                      foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? AppColors.accent
                              : AppColors.textSecondary),
                    ),
                  )),
              const SizedBox(height: 14),
              // زر التشغيل / Play button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () {
                    final s = int.tryParse(surahCtrl.text) ?? 0;
                    final a = int.tryParse(ayahCtrl.text) ?? 0;
                    if (!QuranAudio.metadata.isValidSurah(s)) {
                      Get.snackbar('خطأ', 'رقم السورة يجب أن يكون 1 - 114',
                          snackPosition: SnackPosition.BOTTOM);
                      return;
                    }
                    if (!QuranAudio.metadata.isValidAyah(s, a)) {
                      final max = QuranAudio.ayahCountOf(s);
                      Get.snackbar('خطأ', 'رقم الآية يجب أن يكون 1 - $max',
                          snackPosition: SnackPosition.BOTTOM);
                      return;
                    }
                    QuranAudio.playAyah(
                      surah: s,
                      ayah: a,
                      singleAyah: c.playSingleAyah.value,
                    );
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('تشغيل / Play'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // عرض معلومات الآية المدخلة / Show input ayah info
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: surahCtrl,
                builder: (context, surahVal, _) {
                  return ValueListenableBuilder<TextEditingValue>(
                    valueListenable: ayahCtrl,
                    builder: (context, ayahVal, _) {
                      final s = int.tryParse(surahVal.text) ?? 0;
                      final a = int.tryParse(ayahVal.text) ?? 0;
                      if (s < 1 || a < 1) return const SizedBox.shrink();
                      final valid = QuranAudio.metadata.isValidAyah(s, a);
                      if (!valid) {
                        return const Text(
                          '⚠ رقم غير صالح / Invalid number',
                          style: TextStyle(
                              color: AppColors.destructive, fontSize: 12),
                        );
                      }
                      return Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          InfoChip(
                              label: 'السورة',
                              value: QuranAudio.surah(s).name,
                              icon: Icons.menu_book_rounded),
                          InfoChip(
                              label: 'UQ',
                              value: '#${QuranAudio.uqNumberOf(s, a)}',
                              icon: Icons.tag_rounded),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // أمثلة سريعة / Quick examples
        SectionCard(
          titleAr: 'أمثلة سريعة',
          titleEn: 'Quick Examples',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('آية الكرسي 2:255'),
                onPressed: () => QuranAudio.playAyah(surah: 2, ayah: 255),
                backgroundColor: AppColors.surfaceLight,
                side: BorderSide(color: AppColors.muted.withValues(alpha: 0.3)),
              ),
              ActionChip(
                label: const Text('الفاتحة 1:1'),
                onPressed: () =>
                    QuranAudio.playAyah(surah: 1, ayah: 1, singleAyah: false),
                backgroundColor: AppColors.surfaceLight,
                side: BorderSide(color: AppColors.muted.withValues(alpha: 0.3)),
              ),
              ActionChip(
                label: const Text('يس 36:1 (واحدة)'),
                onPressed: () =>
                    QuranAudio.playAyah(surah: 36, ayah: 1, singleAyah: true),
                backgroundColor: AppColors.surfaceLight,
                side: BorderSide(color: AppColors.muted.withValues(alpha: 0.3)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // التكرار / Repeat
        const SectionCard(
          titleAr: 'التكرار',
          titleEn: 'Repeat',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: Text('إيقاف / Off'),
                onPressed: QuranAudio.disableRepeat,
                avatar: Icon(Icons.repeat_rounded, size: 16),
                backgroundColor: AppColors.surfaceLight,
              ),
              ActionChip(
                label: Text('آية / One'),
                onPressed: QuranAudio.repeatAyah,
                avatar: Icon(Icons.repeat_one_rounded, size: 16),
                backgroundColor: AppColors.surfaceLight,
              ),
              ActionChip(
                label: Text('السورة / Surah'),
                onPressed: QuranAudio.repeatSurah,
                avatar: Icon(Icons.repeat_rounded, size: 16),
                backgroundColor: AppColors.surfaceLight,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
