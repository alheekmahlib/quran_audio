/// رسائل methods.* الصادرة لِـ qurani.ai QRC (موثّقة).
///
/// Outbound `methods.*` messages for the qurani.ai QRC (documented).
enum QrcMethod {
  /// بدء جلسة تلاوة — يُرسل مرة واحدة فقط لِكل جلسة.
  startTilawaSession,

  /// إنهاء الجلسة (اختياري — إغلاق WS كافٍ، لكن هذا تنظيف صريح).
  endTilawaSession;

  /// قيمة السلسلة كما تُرسل على السلك (wire string) — مطابقة لِـ qurani.ai JS.
  String get wire => switch (this) {
        startTilawaSession => 'start_tilawa_session',
        endTilawaSession => 'end_tilawa_session',
      };
}
