// تبويب دليل الاستخدام — شروحات كود ثنائية اللغة لكل ميزة في المكتبة.
//
// Guide tab — bilingual code explanations for every library feature.

import 'package:flutter/material.dart';

import '../widgets.dart';

class GuideTab extends StatelessWidget {
  const GuideTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        // التهيئة / Initialization
        SectionCard(
          titleAr: 'التهيئة',
          titleEn: 'Initialization',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeSnippet(
                descriptionAr: 'تهيئ المكتبة بالكامل في خطوة واحدة. ضعها في main قبل runApp.',
                descriptionEn:
                    'Initializes the entire library in one step. Call in main() before runApp().',
                code: '''await QuranAudio.init();''',
              ),
              SizedBox(height: 8),
              CodeSnippet(
                descriptionAr: 'مع تخصيص إشعارات النظام (اختياري).',
                descriptionEn:
                    'With custom system notification settings (optional).',
                code: '''await QuranAudio.init(
  enableSystemNotifications: true,
  androidNotificationChannelId: 'com.myapp.quran',
  androidNotificationChannelName: 'Quran Playback',
);''',
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // تشغيل السور / Play surahs
        SectionCard(
          titleAr: 'تشغيل السور',
          titleEn: 'Playing Surahs',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeSnippet(
                descriptionAr: 'تشغيل سورة كاملة (ملف MP3 واحد).',
                descriptionEn: 'Play a full surah (single MP3 file).',
                code: '''QuranAudio.playSurah(2);  // سورة البقرة''',
              ),
              SizedBox(height: 8),
              CodeSnippet(
                descriptionAr: 'التحكم: إيقاف/استئناف/تالي/سابق/إيقاف كامل.',
                descriptionEn: 'Controls: pause/resume/next/previous/stop.',
                code: '''QuranAudio.pause();
QuranAudio.resume();
QuranAudio.next();       // السورة التالية
QuranAudio.previous();   // السورة السابقة
QuranAudio.stop();''',
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // تشغيل الآيات / Play ayahs
        SectionCard(
          titleAr: 'تشغيل الآيات',
          titleEn: 'Playing Ayahs',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeSnippet(
                descriptionAr: 'تشغيل آية محددة — يأخذ رقم السورة ورقم الآية.',
                descriptionEn:
                    'Play a specific ayah — takes surah number & ayah number.',
                code: '''QuranAudio.playAyah(
  surah: 2,
  ayah: 255,        // آية الكرسي
  singleAyah: false // false = يتابع للآيات التالية
);''',
              ),
              SizedBox(height: 8),
              CodeSnippet(
                descriptionAr: 'تشغيل آية واحدة فقط ثم يتوقف.',
                descriptionEn: 'Play a single ayah then stop.',
                code: '''QuranAudio.playAyah(
  surah: 36, ayah: 1, singleAyah: true,
);''',
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // القرّاء والتحميل / Readers & Downloads
        SectionCard(
          titleAr: 'القرّاء والتحميل',
          titleEn: 'Readers & Downloads',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeSnippet(
                descriptionAr: 'تغيير القارئ حسب الفهرس.',
                descriptionEn: 'Change the reciter by index.',
                code: '''QuranAudio.setSurahReader(2);
QuranAudio.setAyahReader(1);''',
              ),
              SizedBox(height: 8),
              CodeSnippet(
                descriptionAr: 'تحميل سورة/آيات للعمل أوفلاين.',
                descriptionEn: 'Download a surah / ayahs for offline use.',
                code: '''await QuranAudio.downloadSurah(2);
await QuranAudio.downloadSurahAyahs(2);
final ready = await QuranAudio
    .isSurahDownloaded(2);''',
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // التكرار / Repeat
        SectionCard(
          titleAr: 'التكرار',
          titleEn: 'Repeat',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeSnippet(
                descriptionAr: 'تكرار الآية الحالية / السورة / نطاق محدد.',
                descriptionEn:
                    'Repeat current ayah / surah / a specific range.',
                code: '''QuranAudio.repeatAyah();
QuranAudio.repeatSurah();
QuranAudio.repeatAyahRange(
  fromAyah: 1, toAyah: 10, times: 3,
);
QuranAudio.disableRepeat();''',
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // القراءة التفاعلية / Reactive state
        SectionCard(
          titleAr: 'قراءة الحالة (GetX)',
          titleEn: 'Reading State (GetX)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeSnippet(
                descriptionAr:
                    'كل Obx يجب أن يقرأ .value مباشرة من الكنترولر في builder.',
                descriptionEn:
                    'Each Obx must read .value directly from the controller inside its builder.',
                code: '''final c = QuranAudio.surahController;
Obx(() => Text(
  c.isPlaying.value ? 'يعمل' : 'متوقف',
));''',
              ),
              SizedBox(height: 8),
              CodeSnippet(
                descriptionAr: 'شريط التقدّم عبر StreamBuilder.',
                descriptionEn: 'Progress bar via StreamBuilder.',
                code: '''StreamBuilder<PositionData>(
  stream: QuranAudio.positionDataStream,
  builder: (context, snap) {
    final d = snap.data;
    return Slider(
      value: d?.position.inSeconds.toDouble() ?? 0,
      max: d?.duration.inSeconds.toDouble() ?? 1,
      onChanged: (v) => QuranAudio
          .seek(Duration(seconds: v.toInt())),
    );
  },
);''',
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // التسميع / Recitation
        SectionCard(
          titleAr: 'التسميع (تصحيح التلاوة)',
          titleEn: 'Recitation Correction (optional)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeSnippet(
                descriptionAr: 'ميزة اختيارية — فعّلها بِمفتاح qurani.ai. بدونها '
                    'تعمل كل ميزات التشغيل بِالكامل.',
                descriptionEn: 'Optional feature — activate with a qurani.ai key. '
                    'Without it, all playback features still work fully.',
                code: '''Recitation.init(apiKey: 'YOUR_KEY');''',
              ),
              SizedBox(height: 8),
              CodeSnippet(
                descriptionAr: 'أنشئ جلسة تسميع واستمع للتصحيح الحيّ.',
                descriptionEn: 'Create a recitation session and listen to live feedback.',
                code: '''final session = Recitation.createSession(
  config: QrcConfig(
    chapterIndex: 1,
    verseIndex: 1,
  ),
);
session.feedbackStream.listen((fb) {
  print('correct: \${fb.isCorrect}, raw: \${fb.raw}');
});
await session.start();
// ... recite ...
await session.stop();''',
              ),
            ],
          ),
        ),
        SizedBox(height: 24),
      ],
    );
  }
}
