/// نموذج معلومات القارئ - يحمل بيانات قارئ واحد (للسور أو الآيات).
///
/// Reader info model — holds data for a single reciter (surah or ayah).
class ReaderInfo {
  /// رقم تعريف القارئ / Reader identifier.
  final int index;

  /// اسم القارئ بالعربية / Reciter name in Arabic.
  final String name;

  /// مسار القارئ داخل الرابط (مجلد القارئ) / Reader path segment in the URL.
  final String readerNamePath;

  /// رابط المصدر الأساسي للصوت / Base audio source URL.
  final String url;

  const ReaderInfo({
    required this.index,
    required this.name,
    required this.readerNamePath,
    required this.url,
  });

  /// إنشاء كائن من Map / Create from Map.
  factory ReaderInfo.fromMap(Map<String, dynamic> map) {
    return ReaderInfo(
      index: map['index'] as int,
      name: map['name'] as String,
      readerNamePath: map['readerNamePath'] as String,
      url: map['url'] as String,
    );
  }

  /// تحويل الكائن إلى Map / Convert to Map.
  Map<String, dynamic> toMap() {
    return {
      'index': index,
      'name': name,
      'readerNamePath': readerNamePath,
      'url': url,
    };
  }

  ReaderInfo copyWith({
    int? index,
    String? name,
    String? readerNamePath,
    String? url,
  }) {
    return ReaderInfo(
      index: index ?? this.index,
      name: name ?? this.name,
      readerNamePath: readerNamePath ?? this.readerNamePath,
      url: url ?? this.url,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReaderInfo &&
        other.index == index &&
        other.name == name &&
        other.readerNamePath == readerNamePath &&
        other.url == url;
  }

  @override
  int get hashCode => Object.hash(index, name, readerNamePath, url);

  @override
  String toString() =>
      'ReaderInfo(index: $index, name: $name, readerNamePath: $readerNamePath, url: $url)';
}
