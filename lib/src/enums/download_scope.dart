/// نطاق التحميل عند استخدامه مع `playAyah(downloadFirst: true)`.
///
/// Download scope when used with `playAyah(downloadFirst: true)`.
enum DownloadScope {
  /// حمّل الآية الحالية فقط (الافتراضي).
  /// Download only the current ayah (default).
  single,

  /// حمّل كل آيات السورة (للـ playlist في نظام الآيات).
  /// Download all ayahs of the surah (for playlists in the ayah system).
  surah,
}
