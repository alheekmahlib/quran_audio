/// رسائل methods.* الصادرة لِـ qurani.ai QRC.
///
/// Outbound `methods.*` messages for the qurani.ai QRC.
///
/// ملاحظة: qurani.ai لا توثّق قائمة كاملة. المؤكَّد فقط مدرج هنا؛ الباقي
/// يُضاف عند التوثيق.
///
/// Note: qurani.ai does not publish a full list. Only the confirmed method is
/// listed here; others should be added once documented.
enum QrcMethod {
  /// بدء جلسة تلاوة — يُرسل مرة واحدة فقط لِكل جلسة. (موثّق / confirmed)
  startTilawaSession;

  /// قيمة السلسلة كما تُرسل على السلك (wire string).
  /// The wire string sent over the socket.
  String get wire => switch (this) {
        startTilawaSession => 'StartTilawaSession',
        // TODO(qurani.ai): أضف 'EndTilawaSession' / 'Ping' عند توثيقها.
      };
}
