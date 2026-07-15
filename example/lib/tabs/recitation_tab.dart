// تبويب التسميع — تصحيح التلاوة عبر خادم quran-muaalem.
//
// Recitation tab — Quran recitation correction via a quran-muaalem server.
//
// المكتبة عميل HTTP فقط — المستخدم يُشغّل خادم quran-muaalem على جهازه:
//   pip install "quran-muaalem[engine]"
//   quran-muaalem-engine  # منفذ 8000 (النموذج)
//   quran-muaalem-app     # منفذ 8001 (HTTP API)
// ثم يُمرّر العنوان هنا.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:quran_audio/quran_audio.dart';

import '../theme.dart';
import '../widgets.dart';

class RecitationTab extends StatefulWidget {
  const RecitationTab({super.key});

  @override
  State<RecitationTab> createState() => _RecitationTabState();
}

class _RecitationTabState extends State<RecitationTab> {
  final _urlCtrl = TextEditingController(text: 'http://localhost:8001');
  final _isReady = false.obs;
  final _isRecording = false.obs;
  final _sessionState = RecitationState.idle.obs;
  final _result = Rx<RecitationResult?>(null);
  RecitationSession? _session;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _session?.dispose();
    super.dispose();
  }

  Future<void> _saveServer() async {
    Recitation.init(serverUrl: _urlCtrl.text.trim());
    _isReady.value = Recitation.isInitialized;
    final healthy = _isReady.value ? await Recitation.isServerHealthy() : false;
    Get.snackbar(
      'حالة الخادم',
      _isReady.value
          ? (healthy
              ? 'متّصل ✓ — الخادم يعمل'
              : 'الخادم لا يستجيب — تأكّد من تشغيل quran-muaalem')
          : 'عنوان فارغ',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _startSession() async {
    if (!Recitation.isInitialized) {
      Get.snackbar('خطأ', 'أدخل عنوان الخادم أولاً واحفظه',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    _result.value = null;
    _isRecording.value = true;
    _session = Recitation.createSession();
    _session!.state.listen((s) {
      _isRecording.value = s == RecitationState.recording;
      _sessionState.value = s;
      if (s == RecitationState.finished) {
        _result.value = _session!.result.value;
      }
    });
    await _session!.start();
  }

  Future<void> _stopSession() async {
    _isRecording.value = false;
    await _session?.stop();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          titleAr: 'خادم quran-muaalem',
          titleEn: 'quran-muaalem Server',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'المكتبة عميل HTTP فقط. شغّل خادم quran-muaalem على جهازك:\n'
                'pip install "quran-muaalem[engine]"\n'
                'quran-muaalem-engine  # port 8000\n'
                'quran-muaalem-app     # port 8001',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.6),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'http://localhost:8001',
                        prefixIcon: Icon(Icons.dns_rounded, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saveServer,
                    child: const Text('حفظ'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Obx(() => InfoChip(
                    label: 'الحالة',
                    value: _isReady.value ? 'مُهيّأ' : 'غير مُهيّأ',
                    icon: _isReady.value
                        ? Icons.check_circle_rounded
                        : Icons.cloud_off_rounded,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Obx(() {
          if (!_isReady.value) {
            return const SectionCard(
              titleAr: 'التسميع معطّل',
              titleEn: 'Recitation Disabled',
              child: Text(
                'أدخل عنوان الخادم بالأعلى واضغط "حفظ" لِتفعيل التسميع.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
            );
          }
          return Column(
            children: [
              // زر التسجيل / Record button
              SectionCard(
                titleAr: 'التلاوة',
                titleEn: 'Recite',
                child: Column(
                  children: [
                    Obx(() {
                      final recording = _isRecording.value;
                      final processing =
                          _sessionState.value == RecitationState.processing;
                      return FilledButton.icon(
                        onPressed: processing
                            ? null
                            : (recording ? _stopSession : _startSession),
                        icon: Icon(processing
                            ? Icons.hourglass_top_rounded
                            : recording
                                ? Icons.stop_rounded
                                : Icons.mic_rounded),
                        label: Text(processing
                            ? 'جارٍ التصحيح...'
                            : recording
                                ? 'إيقاف'
                                : 'ابدأ التسميع'),
                        style: FilledButton.styleFrom(
                          backgroundColor: processing
                              ? AppColors.surfaceLight
                              : recording
                                  ? AppColors.destructive
                                  : AppColors.accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Obx(() {
                      final s = _sessionState.value;
                      final label = switch (s) {
                        RecitationState.idle => 'جاهز',
                        RecitationState.connecting => 'جارٍ الاتصال...',
                        RecitationState.recording => 'يسجّل — تلا الآن',
                        RecitationState.paused => 'متوقّف مؤقتاً',
                        RecitationState.processing => 'يُعالج الخادم الصوت...',
                        RecitationState.error => 'خطأ',
                        RecitationState.finished => 'انتهى',
                      };
                      return Text('الحالة: $label',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12));
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // عرض النتيجة / Result display
              SectionCard(
                titleAr: 'التصحيح',
                titleEn: 'Correction',
                child: Obx(() {
                  final res = _result.value;
                  if (res == null) {
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
                  return _ResultView(result: res);
                }),
              ),
            ],
          );
        }),
      ],
    );
  }
}

/// عرض نتيجة التصحيح بِتفصيل غني.
/// Rich display of the correction result.
class _ResultView extends StatelessWidget {
  const _ResultView({required this.result});
  final RecitationResult result;

  @override
  Widget build(BuildContext context) {
    if (!result.hasMatch) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded,
                size: 40, color: AppColors.textMuted),
            const SizedBox(height: 8),
            Text(
              result.noMatchMessage ?? 'لا تطابق في القرآن',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // النص العثماني + الموضع
        if (result.uthmaniText != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.uthmaniText!,
                  style: const TextStyle(fontSize: 20, height: 1.8),
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 6),
                Text(
                  'الآية: ${result.start?.suraIdx ?? "?"}:${result.start?.ayaIdx ?? "?"}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ملخّص الأخطاء
        _ErrorSummaryBar(result: result),
        const SizedBox(height: 12),

        // قائمة الأخطاء
        if (result.errors.isEmpty)
          const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
              SizedBox(width: 8),
              Text('ممتاز! لا أخطاء تجويد.',
                  style: TextStyle(color: AppColors.success)),
            ],
          )
        else
          ...result.errors.map((e) => _ErrorCard(error: e)),
      ],
    );
  }
}

class _ErrorSummaryBar extends StatelessWidget {
  const _ErrorSummaryBar({required this.result});
  final RecitationResult result;

  @override
  Widget build(BuildContext context) {
    final tajweed = result.tajweedErrors.length;
    final normal = result.normalErrors.length;
    final tashkeel = result.tashkeelErrors.length;
    final total = result.errors.length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        InfoChip(
          label: 'إجمالي',
          value: '$total',
          icon: Icons.error_outline_rounded,
        ),
        if (tajweed > 0)
          InfoChip(
            label: 'تجويد',
            value: '$tajweed',
            icon: Icons.music_note_rounded,
          ),
        if (normal > 0)
          InfoChip(
            label: 'نطق',
            value: '$normal',
            icon: Icons.record_voice_over_rounded,
          ),
        if (tashkeel > 0)
          InfoChip(
            label: 'تشكيل',
            value: '$tashkeel',
            icon: Icons.text_fields_rounded,
          ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});
  final RecitationError error;

  @override
  Widget build(BuildContext context) {
    final isTajweed = error.errorType == 'tajweed';
    return Card(
      color: AppColors.surfaceLight,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isTajweed ? Icons.music_note_rounded : Icons.error_rounded,
                  size: 18,
                  color: isTajweed ? AppColors.accent : AppColors.destructive,
                ),
                const SizedBox(width: 6),
                Text(
                  error.description,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
            if (error.expectedPh != null || error.predictedPh != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (error.expectedPh != null)
                    _phChip('المتوقَّع', error.expectedPh!, AppColors.success),
                  if (error.predictedPh != null)
                    _phChip('الفعلي', error.predictedPh!, AppColors.destructive),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _phChip(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        Text(value,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            textDirection: TextDirection.rtl),
      ],
    );
  }
}
