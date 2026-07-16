// تبويب التسميع — تصحيح التلاوة offline (نموذج ONNX) أو online (خادم).
//
// يدعم وضعَين:
// 1) Offline: ينزّل نموذج ONNX (95MB) مرّة واحدة، ثمّ يعمل بدون إنترنت.
// 2) Online: خادم quran-muaalem (pip install "quran-muaalem[engine]").

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quran_audio/quran_audio.dart';

import '../theme.dart';
import '../widgets.dart';

/// رابط تنزيل النموذج من GitHub Release.
const _kModelUrl =
    'https://github.com/alheekmahlib/quran-muaalem-local/releases/download/student-v2/muaalem_student.int8.onnx';

/// حجم النموذج التقريبي (لِعرضه قبل التحميل).
const _kModelSizeMb = 95.3;

class RecitationTab extends StatefulWidget {
  const RecitationTab({super.key});

  @override
  State<RecitationTab> createState() => _RecitationTabState();
}

class _RecitationTabState extends State<RecitationTab> {
  // ── Online ──
  final _urlCtrl = TextEditingController(text: 'http://localhost:8001');

  // ─ـ مشترك ──
  final _isReady = false.obs;
  final _isRecording = false.obs;
  final _sessionState = RecitationState.idle.obs;
  final _result = Rx<RecitationResult?>(null);
  final _mode = 'none'.obs; // 'none' | 'offline' | 'online'
  RecitationSession? _session;

  // ── Offline: تحميل النموذج ──
  final _downloadProgress = 0.0.obs; // 0.0 - 1.0
  final _isDownloading = false.obs;
  final _modelDownloaded = false.obs;
  String? _modelPath;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _checkModelExists();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _session?.dispose();
    super.dispose();
  }

  // ═══════════════════════ Offline: Model Download ═══════════════════════

  /// مسار النموذج المحلي (بعد التحميل).
  Future<String> get _localModelPath async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/muaalem_student.int8.onnx';
  }

  /// تحقّق إن كان النموذج محمّلاً مُسبقاً.
  Future<void> _checkModelExists() async {
    final path = await _localModelPath;
    final file = File(path);
    if (await file.exists() && await file.length() > 80 * 1024 * 1024) {
      _modelPath = path;
      _modelDownloaded.value = true;
    }
  }

  /// ينزّل النموذج من GitHub Release.
  Future<void> _downloadModel() async {
    if (_isDownloading.value || _modelDownloaded.value) return;
    _isDownloading.value = true;
    _downloadProgress.value = 0;
    _downloadError = null;

    try {
      final path = await _localModelPath;
      final dio = Dio();
      await dio.download(
        _kModelUrl,
        path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _downloadProgress.value = received / total;
          }
        },
      );
      _modelPath = path;
      _modelDownloaded.value = true;
      Get.snackbar(
        'تمّ التحميل',
        'النموذج جاهز (${_kModelSizeMb.toStringAsFixed(1)}MB)\n'
        'اضغط "تفعيل" لِبدء التسميع offline',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      _downloadError = e.toString();
      Get.snackbar(
        'فشل التحميل',
        'تعذّر تنزيل النموذج. تحقّق من الإنترنت.\n$e',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
    } finally {
      _isDownloading.value = false;
    }
  }

  /// يُفعّل الوضع Offline.
  Future<void> _activateOffline() async {
    if (_modelPath == null) return;
    try {
      await Recitation.initOffline(modelPath: _modelPath);
      _mode.value = 'offline';
      _isReady.value = Recitation.isInitialized;
      Get.snackbar(
        'Offline جاهز',
        'النموذج محمّل على الجهاز. التسميع يعمل بدون إنترنت!',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('خطأ', 'تعذّر تحميل النموذج: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ═══════════════════════ Online: Server ═══════════════════════

  Future<void> _saveServer() async {
    Recitation.init(serverUrl: _urlCtrl.text.trim());
    _isReady.value = Recitation.isInitialized;
    _mode.value = 'online';
    final healthy =
        _isReady.value ? await Recitation.isServerHealthy() : false;
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

  // ═══════════════════════ Session ═══════════════════════

  Future<void> _startSession() async {
    if (!Recitation.isInitialized) {
      Get.snackbar('خطأ', 'فعّل الوضع offline أو online أولاً',
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

  void _resetMode() {
    Recitation.reset();
    _mode.value = 'none';
    _isReady.value = false;
    _result.value = null;
  }

  // ═══════════════════════ UI ═══════════════════════

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── اختيار الوضع ──
        _modeSelector(),
        const SizedBox(height: 16),

        // ── محتوى حسب الوضع ──
        Obx(() {
          if (_mode.value == 'offline') return _offlineActive();
          if (_mode.value == 'online') return _onlineActive();
          return _setupPrompt();
        }),
      ],
    );
  }

  // ── شريط اختيار الوضع ──
  Widget _modeSelector() {
    return SectionCard(
      titleAr: 'وضع التسميع',
      titleEn: 'Recitation Mode',
      child: Obx(() {
        if (_mode.value != 'none') {
          // وضع نشط — اعرض زر إعادة الضبط
          return Row(
            children: [
              Icon(
                _mode.value == 'offline'
                    ? Icons.phone_android_rounded
                    : Icons.cloud_rounded,
                color: AppColors.success,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _mode.value == 'offline'
                      ? 'Offline — نموذج محلي (بدون إنترنت)'
                      : 'Online — خادم quran-muaalem',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: _resetMode,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('تغيير'),
              ),
            ],
          );
        }
        // لا وضع نشط — اعرض خيارَين
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'اختر طريقة التسميع:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            // خيار Offline (مُوصى به)
            _modeOptionCard(
              icon: Icons.phone_android_rounded,
              titleAr: 'Offline — على الجهاز',
              titleEn: 'On-device model',
              subtitle:
                  'يُنزّل نموذجاً (${_kModelSizeMb.toStringAsFixed(1)}MB) مرّة واحدة، '
                  'ثمّ يعمل بدون إنترنت. الأنسب لِلاستخدام اليومي.',
              color: AppColors.accent,
              recommended: true,
              onTap: () => setState(() {}), // يُظهر قسم التحميل أدناه
            ),
            const SizedBox(height: 8),
            // خيار Online
            _modeOptionCard(
              icon: Icons.cloud_rounded,
              titleAr: 'Online — خادم',
              titleEn: 'Server-based',
              subtitle:
                  'يتطلّب خادم quran-muaalem على جهازك أو خادمك. أعلى دقّة '
                  'لكن يحتاج إعداداً واتصالاً.',
              color: AppColors.textSecondary,
              onTap: _saveServer,
            ),
          ],
        );
      }),
    );
  }

  Widget _modeOptionCard({
    required IconData icon,
    required String titleAr,
    required String titleEn,
    required String subtitle,
    required Color color,
    bool recommended = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: recommended
              ? Border.all(color: color.withValues(alpha: 0.4), width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(titleAr,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (recommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('مُوصى به',
                              style:
                                  TextStyle(color: color, fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── قسم التحميل (offline) ──
  Widget _setupPrompt() {
    return Obx(() {
      if (_modelDownloaded.value) {
        // النموذج محمّل — اعرض زر التفعيل
        return SectionCard(
          titleAr: 'تفعيل التسميع Offline',
          titleEn: 'Activate Offline Recitation',
          child: Column(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 40),
              const SizedBox(height: 8),
              const Text('النموذج محمّل وجاهز لِلاستخدام.',
                  style: TextStyle(color: AppColors.success)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _activateOffline,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('تفعيل التسميع Offline'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ),
        );
      }

      if (_isDownloading.value) {
        // تحميل جارٍ
        return SectionCard(
          titleAr: 'جارٍ تنزيل النموذج',
          titleEn: 'Downloading Model',
          child: Column(
            children: [
              Obx(() => LinearProgressIndicator(
                    value: _downloadProgress.value,
                    backgroundColor: AppColors.surfaceLight,
                    color: AppColors.accent,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  )),
              const SizedBox(height: 12),
              Obx(() => Text(
                    '${(_downloadProgress.value * 100).toInt()}% — '
                    '${(_downloadProgress.value * _kModelSizeMb).toStringAsFixed(1)}MB '
                    '/ ${_kModelSizeMb.toStringAsFixed(1)}MB',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                  )),
              const SizedBox(height: 8),
              Text(
                'النموذج كبير (${_kModelSizeMb.toStringAsFixed(0)}MB). '
                'سيستغرق التحميل عدّة دقائق حسب سرعة الإنترنت.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }

      // جاهز لِلتحميل
      return SectionCard(
        titleAr: 'تنزيل نموذج التجويد',
        titleEn: 'Download Tajweed Model',
        child: Column(
          children: [
            const Icon(Icons.download_rounded,
                size: 40, color: AppColors.accent),
            const SizedBox(height: 8),
            Text(
              'نموذج تجويد offline (${_kModelSizeMb.toStringAsFixed(1)}MB).\n'
              'يُنزَّل مرّة واحدة فقط، ثمّ يعمل بدون إنترنت.',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (_downloadError != null) ...[
              const SizedBox(height: 8),
              Text(_downloadError!,
                  style: const TextStyle(
                      color: AppColors.destructive, fontSize: 11),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _downloadModel,
              icon: const Icon(Icons.cloud_download_rounded),
              label: Text(
                  'تنزيل النموذج (${_kModelSizeMb.toStringAsFixed(1)}MB)'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 12),
            // رابط بديل لِـ Online
            TextButton.icon(
              onPressed: _saveServer,
              icon: const Icon(Icons.cloud_rounded, size: 18),
              label: const Text('أو استخدم خادم quran-muaalem'),
            ),
          ],
        ),
      );
    });
  }

  // ── Offline نشط — أزرار التلاوة ──
  Widget _offlineActive() {
    return _recitationControls(isOffline: true);
  }

  // ── Online نشط — إعداد الخادم + أزرار التلاوة ──
  Widget _onlineActive() {
    return Column(
      children: [
        SectionCard(
          titleAr: 'خادم quran-muaalem',
          titleEn: 'Server',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'pip install "quran-muaalem[engine]"\n'
                'quran-muaalem-engine && quran-muaalem-app',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 11, height: 1.6),
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        _recitationControls(isOffline: false),
      ],
    );
  }

  // ── أزرار التلاوة + النتيجة (مشترك) ──
  Widget _recitationControls({required bool isOffline}) {
    return Column(
      children: [
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
                  RecitationState.processing =>
                    isOffline ? 'النموذج يحلّل الصوت...' : 'يُعالج الخادم الصوت...',
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
            return _ResultView(result: res, isOffline: isOffline);
          }),
        ),
      ],
    );
  }
}

// ═══════════════════════ عرض النتيجة ═══════════════════════

/// عرض نتيجة التصحيح.
class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.isOffline});
  final RecitationResult result;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    // في الوضع Offline، قد لا يكون هناك تطابق كامل (noMatch)، لكنّ
    // predictedPhonemes يكون موجوداً. نُظهره دائماً.
    if (result.predictedPhonemes != null &&
        result.predictedPhonemes!.isNotEmpty &&
        !result.hasMatch) {
      return _OfflinePhonemesView(
        phonemes: result.predictedPhonemes!,
      );
    }

    if (!result.hasMatch) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded,
                size: 40, color: AppColors.textMuted),
            const SizedBox(height: 8),
            Text(
              result.noMatchMessage ?? 'لا تطابق',
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
        _ErrorSummaryBar(result: result),
        const SizedBox(height: 12),
        if (result.errors.isEmpty)
          const Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 20),
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

/// عرض الفونيمات المتوقَّعة في الوضع Offline.
class _OfflinePhonemesView extends StatelessWidget {
  const _OfflinePhonemesView({required this.phonemes});
  final String phonemes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.graphic_eq_rounded,
                color: AppColors.accent, size: 20),
            const SizedBox(width: 8),
            const Text('الفونيمات المتوقَّعة',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${phonemes.length} رمز',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            phonemes,
            style: const TextStyle(
              fontSize: 18,
              height: 1.8,
              fontFamily: 'monospace',
            ),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'ملاحظة: هذا النموذج المُقطَّر offline. يُخرج الفونيمات + صفات التجويد. '
          'التطابق الكامل مع النصّ المرجعي يتطلّب تحديثات قادمة.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.5),
        ),
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
                  color:
                      isTajweed ? AppColors.accent : AppColors.destructive,
                ),
                const SizedBox(width: 6),
                Text(
                  error.description,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
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
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        Text(value,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            textDirection: TextDirection.rtl),
      ],
    );
  }
}
