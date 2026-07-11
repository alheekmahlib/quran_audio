// مثال احترافي لاستخدام مكتبة quran_audio
//
// Professional example for the quran_audio library
//
// يوضّح:
//  - تهيئة المكتبة في خطوة واحدة.
//  - تشغيل سورة كاملة / آية محددة (بإدخال يدوي لرقم السورة والآية).
//  - التحكم (تشغيل/إيقاف/تالي/سابق/تقديم).
//  - اختيار القارئ + شريط التقدّم + التكرار.
//  - شروحات ثنائية اللغة (عربي/إنجليزي) لكل دالة.
//
// كل العمليات عبر الواجهة الموحّدة `QuranAudio`.
// All operations via the unified `QuranAudio` facade.
//
// التبويبات مقسّمة لملفات منفصلة في lib/tabs/:
// The tabs are split into separate files in lib/tabs/:
//   - surah_tab.dart      : تشغيل السور الكاملة / full-surah playback
//   - ayah_tab.dart       : تشغيل الآيات بإدخال يدوي / ayah playback + manual input
//   - guide_tab.dart      : دليل الاستخدام / usage guide
//   - recitation_tab.dart : التسميع (تصحيح التلاوة) / recitation correction

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:quran_audio/quran_audio.dart';

import 'tabs/ayah_tab.dart';
import 'tabs/guide_tab.dart';
import 'tabs/recitation_tab.dart';
import 'tabs/surah_tab.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // تهيئة المكتبة بالكامل في خطوة واحدة / Initialize in one step
  await QuranAudio.init();
  runApp(const QuranAudioExampleApp());
}

class QuranAudioExampleApp extends StatelessWidget {
  const QuranAudioExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Quran Audio Example',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            children: [
              Text('القرآن الصوتي', style: TextStyle(fontSize: 18)),
              Text('Quran Audio',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.normal)),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'السور'),
              Tab(text: 'الآيات'),
              Tab(text: 'تسميع'),
              Tab(text: 'دليل الاستخدام'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            SurahTab(),
            AyahTab(),
            RecitationTab(),
            GuideTab(),
          ],
        ),
      ),
    );
  }
}
