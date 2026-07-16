/// مكتبة تشغيل صوتي للقرآن الكريم - لوجيك فقط بدون UI.
///
/// تدعم نظامين منفصلين:
/// - [SurahAudioController]: تشغيل السور الكاملة (ملف MP3 واحد لكل سورة).
/// - [AyahAudioController]: تشغيل الآيات المفردة (ملف MP3 لكل آية).
///
/// كل نظام له قرّاؤه وروابطه المستقلة، ويتشاركان مشغّلاً صوتياً واحداً.
///
/// مثال سريع للاستخدام:
/// ```dart
/// await GetStorage.init();
/// await QuranMetadata.instance.load();
/// await SurahAudioController.instance.init();
///
/// // تشغيل سورة:
/// SurahAudioController.instance.playSurah(surahNumber: 2);
///
/// // تشغيل آية:
/// AyahAudioController.instance.playAyah(surahNumber: 2, ayahNumber: 255);
/// ```
library quran_audio;

// محرك الصوت و Enums
export 'src/engine/audio_engine.dart';
export 'src/enums/download_scope.dart';
export 'src/enums/playback_mode.dart';
export 'src/enums/repeat_mode.dart';

// النماذج
export 'src/shared/models/reader_info.dart';
export 'src/shared/models/surah_meta.dart';
export 'src/shared/models/position_data.dart';
export 'src/shared/models/repeat_config.dart';

// الطبقة المشتركة
export 'src/shared/quran_audio.dart' show QuranAudio;
export 'src/shared/quran_metadata.dart';
export 'src/shared/download_service.dart';
export 'src/shared/repeat_controller.dart';
export 'src/shared/audio_handler.dart';
export 'src/shared/media_item_builder.dart';
export 'src/shared/audio_art.dart';

// القرّاء وبنّاءو الروابط
export 'src/surah_audio/surah_readers.dart';
export 'src/surah_audio/surah_url_builder.dart';
export 'src/ayah_audio/ayah_readers.dart';
export 'src/ayah_audio/ayah_url_builder.dart';

// الكنترولرات
export 'src/surah_audio/surah_audio_controller.dart';
export 'src/ayah_audio/ayah_audio_controller.dart';

// الثوابت
export 'src/constants/quran_constants.dart';
export 'src/constants/storage_keys.dart';

// التسميع (تصحيح التلاوة) — وحدة اختيارية.
// Recitation correction — optional module.
// يدعم وضعَين: online (خادم quran-muaalem) و offline (نموذج ONNX محلي 95MB).
// Supports two modes: online (quran-muaalem server) and offline (local ONNX).
export 'src/recitation/recitation.dart';
export 'src/recitation/recitation_engine.dart';
export 'src/recitation/recitation_session.dart';
export 'src/recitation/recitation_state.dart';
export 'src/recitation/onnx_recitation_engine.dart';
export 'src/recitation/wav_decoder.dart';
export 'src/recitation/muaalem_client.dart';
export 'src/recitation/models/muaalem_config.dart';
export 'src/recitation/models/recitation_result.dart';

// إعادة تصدير حزم الصوت الأساسية لراحة المستخدم
export 'package:just_audio/just_audio.dart';
export 'package:audio_service/audio_service.dart';
