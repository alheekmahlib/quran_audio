// تبويب التسميع — تصحيح التلاوة عبر qurani.ai.
//
// Recitation tab — Quran recitation correction via qurani.ai.
//
// ⚠️ تنبيه: بعض تفاصيل qurani.ai (عنوان wss الدقيق، بنية الاستجابة، نطاقات
// hafz_level/tajweed_level) غير موثّقة بالكامل. هذا التبويب يقدّم الهيكل
// الكامل مع TODO واضحة للأجزاء غير المؤكَّدة — تُكمل عند الحصول على API key
// والاختبار الحيّ.
//
// ⚠️ Note: some qurani.ai details (exact wss URL, response schema, ranges for
// hafz_level/tajweed_level) are not fully documented. This tab provides the
// full structure with clear TODOs for the unconfirmed parts — to be completed
// once you have an API key and live testing.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:quran_audio/quran_audio.dart';

import '../theme.dart';
import '../widgets.dart';

class RecitationTab extends StatefulWidget {
  const RecitationTab({super.key});

  @override
  State<RecitationTab> createState() => _RecitationTabState();
}

class _RecitationTabState extends State<RecitationTab> {
  final _apiKeyCtrl = TextEditingController();
  int _surah = 1;
  int _ayah = 1;
  RecitationSession? _session;
  final _feedbacks = <QrcFeedback>[].obs;
  final _isRecording = false.obs;
  // حالة تفاعلية لِتهيئة التسميع (بديل عن static getter في Obx).
  // Reactive flag for recitation init (replaces the static getter in Obx).
  final _isReady = false.obs;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _session?.dispose();
    super.dispose();
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _startSession() async {
    if (!Recitation.isInitialized) {
      Get.snackbar('خطأ', 'أدخل مفتاح API أولاً وحفظه',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (!await _ensureMicPermission()) {
      Get.snackbar('صلاحية', 'يجب منح إذن الميكروفون لِلتسميع',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(_feedbacks.clear);
    _session = Recitation.createSession(
      config: QrcConfig(chapterIndex: _surah, verseIndex: _ayah),
    );
    _session!.feedbackStream.listen((fb) {
      _feedbacks.insert(0, fb); // الأحدث أولاً
    });
    _session!.state.listen((s) {
      _isRecording.value = s == RecitationState.recording;
      if (s.isError) {
        Get.snackbar('خطأ', _session!.lastError.value,
            snackPosition: SnackPosition.BOTTOM);
      }
    });
    await _session!.start();
  }

  Future<void> _stopSession() async {
    await _session?.stop();
    _isRecording.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // قسم مفتاح API / API key section
        SectionCard(
          titleAr: 'مفتاح qurani.ai',
          titleEn: 'qurani.ai API Key',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'يُحصَل على المفتاح من لوحة تحكم qurani.ai بعد الاشتراك. '
                'بدونه لا تعمل ميزة التسميع.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _apiKeyCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: 'your-qurani-ai-key',
                        prefixIcon: Icon(Icons.key_rounded, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      Recitation.init(apiKey: _apiKeyCtrl.text.trim());
                      _isReady.value = Recitation.isInitialized; // تحديث تفاعلي
                      Get.snackbar(
                        'تم',
                        _isReady.value ? 'تم تفعيل التسميع' : 'مفتاح فارغ',
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Obx(() => InfoChip(
                    label: 'الحالة',
                    value: _isReady.value ? 'مفعّل' : 'غير مفعّل',
                    icon: _isReady.value
                        ? Icons.check_circle_rounded
                        : Icons.lock_outline,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // إن لم يُفعّل، اعرض رسالة وتوقّف.
        // If not enabled, show a message and stop here.
        Obx(() {
          if (!_isReady.value) {
            return const SectionCard(
              titleAr: 'التسميع معطّل',
              titleEn: 'Recitation Disabled',
              child: Text(
                'أدخل مفتاح API بالأعلى واضغط "حفظ" لِتفعيل التسميع.\n'
                'حتى بدون تفعيله، تعمل بِكامل ميزات التشغيل الصوتي.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
            );
          }
          return Column(
            children: [
              // اختيار السورة/الآية / Surah & ayah selection
              SectionCard(
            titleAr: 'اختيار الآية',
            titleEn: 'Select Ayah',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _surah,
                        decoration: const InputDecoration(
                          labelText: 'السورة',
                          prefixIcon:
                              Icon(Icons.menu_book_rounded, size: 20),
                        ),
                        items: [
                          for (final s in QuranAudio.allSurahs)
                            DropdownMenuItem(
                              value: s.number,
                              child: Text('${s.number}. ${s.name}'),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _surah = v ?? 1;
                          _ayah = 1;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: DropdownButtonFormField<int>(
                        initialValue: _ayah,
                        decoration: const InputDecoration(
                          labelText: 'الآية',
                        ),
                        items: [
                          for (int i = 1;
                              i <= QuranAudio.ayahCountOf(_surah);
                              i++)
                            DropdownMenuItem(value: i, child: Text('$i')),
                        ],
                        onChanged: (v) => setState(() => _ayah = v ?? 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                InfoChip(
                  label: 'المختار',
                  value: '${QuranAudio.surah(_surah).name} $_surah:$_ayah',
                  icon: Icons.check_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // زر التسجيل / Record button
          SectionCard(
            titleAr: 'التلاوة',
            titleEn: 'Recite',
            child: Column(
              children: [
                Obx(() {
                  final recording = _isRecording.value;
                  return FilledButton.icon(
                    onPressed: recording ? _stopSession : _startSession,
                    icon: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
                    label: Text(recording ? 'إيقاف' : 'ابدأ التسميع'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          recording ? AppColors.destructive : AppColors.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Obx(() {
                  final s = _session?.state.value ?? RecitationState.idle;
                  return Text(
                    'الحالة: ${s.name}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // عرض التصحيح الحيّ / Live feedback display
          SectionCard(
            titleAr: 'التصحيح الحيّ',
            titleEn: 'Live Feedback',
            child: Obx(() {
              if (_feedbacks.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'لا تصحيح بعد. ابدأ التسميع لِرؤية الملاحظات هنا.',
                      style: TextStyle(color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final fb in _feedbacks.take(20))
                    Card(
                      color: AppColors.surfaceLight,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          fb.isCorrect == true
                              ? Icons.check_circle_rounded
                              : fb.isCorrect == false
                                  ? Icons.error_rounded
                                  : Icons.info_rounded,
                          color: fb.isCorrect == true
                              ? AppColors.success
                              : fb.isCorrect == false
                                  ? AppColors.destructive
                                  : AppColors.accent,
                          size: 20,
                        ),
                        title: Text(
                          fb.message ??
                              fb.event ??
                              fb.score?.toStringAsFixed(1) ??
                              'رسالة',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          fb.raw.toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: AppColors.textMuted),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
            ],
          );
        }),
      ],
    );
  }
}
