/// رسائل methods.* الصادرة لِـ qurani.ai QRC (موثّقة).
///
/// Outbound `methods.*` messages for the qurani.ai QRC (documented).
enum QrcMethod {
  /// بدء جلسة تلاوة — يُرسل مرة واحدة فقط لِكل جلسة.
  startTilawaSession,

  /// إنهاء الجلسة (اختياري — إغلاق WS كافٍ، لكن هذا تنظيف صريح).
  endTilawaSession;

  /// قيمة السلسلة كما تُرسل على السلك (wire string).
  /// الوثائق تُشير إلى PascalCase في كود JS (`methods.START_TILAWA_SESSION`).
  ///
  /// The wire string. The JS docs reference PascalCase
  /// (`methods.START_TILAWA_SESSION`).
  String get wire => switch (this) {
        startTilawaSession => 'StartTilawaSession',
        endTilawaSession => 'EndTilawaSession',
      };
}
