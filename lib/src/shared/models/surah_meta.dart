/// نموذج بيانات السورة الوصفية - يحمل معلومات السورة بدون نصوص الآيات.
///
/// Surah metadata model — holds surah info without ayah text (keeps the asset small).
class SurahMeta {
  /// رقم السورة (1..114) / Surah number.
  final int number;

  /// اسم السورة بالعربية / Arabic surah name.
  final String name;

  /// الاسم الإنجليزي / English name.
  final String englishName;

  /// ترجمة الاسم الإنجليزي / English translation of the name.
  final String englishNameTranslation;

  /// نوع الوحي (مكية/مدنية) / Revelation type.
  final String revelationType;

  /// عدد آيات السورة / Number of ayahs in the surah.
  final int ayahCount;

  const SurahMeta({
    required this.number,
    required this.name,
    required this.englishName,
    required this.englishNameTranslation,
    required this.revelationType,
    required this.ayahCount,
  });

  factory SurahMeta.fromJson(Map<String, dynamic> json) {
    return SurahMeta(
      number: json['number'] as int,
      name: json['name'] as String,
      englishName: json['englishName'] as String,
      englishNameTranslation: json['englishNameTranslation'] as String? ?? '',
      revelationType: json['revelationType'] as String? ?? '',
      ayahCount: json['ayahCount'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'number': number,
        'name': name,
        'englishName': englishName,
        'englishNameTranslation': englishNameTranslation,
        'revelationType': revelationType,
        'ayahCount': ayahCount,
      };

  @override
  String toString() =>
      'SurahMeta(number: $number, name: $name, ayahCount: $ayahCount)';
}
