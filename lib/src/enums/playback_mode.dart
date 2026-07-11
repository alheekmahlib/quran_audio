/// نمط التشغيل النشط - يحدد أي نظام يتحكم بالمشغل الصوتي المشترك.
///
/// Active playback mode — determines which system owns the shared audio player.
enum PlaybackMode {
  /// نظام السور (ملف MP3 واحد لكل سورة كاملة) / Surah system (one MP3 per full surah).
  surah,

  /// نظام الآيات (ملف MP3 لكل آية) / Ayah system (one MP3 per ayah).
  ayah,

  /// لا يوجد تشغيل نشط / No active playback.
  none,
}
