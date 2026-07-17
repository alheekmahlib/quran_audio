/// محاذاة فونيمات (Levenshtein / Wagner-Fischer).
///
/// تُقارن قائمتَي فونيمات (متوقَّع vs مرجعي) وتُنتج قائمة عمليّات
/// (match/insert/delete/replace) مع مواضعها.
///
/// الطبقة 2 من خطّة مقارنة التجويد.
library;

/// عمليّة محاذاة واحدة.
class AlignOp {
  AlignOp({
    required this.type,
    this.refId,
    this.predId,
    required this.refIdx,
    required this.predIdx,
  });

  /// 'match' | 'insert' | 'delete' | 'replace'
  final String type;

  /// معرّف الفونيم المرجعي (null لِـ insert).
  final int? refId;

  /// معرّف الفونيم المتوقَّع (null لِـ delete).
  final int? predId;

  /// الموضع في المرجع (0-based). لِـ insert = موضع الإدراج.
  final int refIdx;

  /// الموضع في المتوقَّع (0-based). لِـ delete = موضع الحذف.
  final int predIdx;

  @override
  String toString() => '$type(ref=$refId@$refIdx, pred=$predId@$predIdx)';
}

/// يحاذي قائمتَي فونيمات ويُعيد قائمة العمليّات.
///
/// [reference] الفونيمات المرجعية الصحيحة.
/// [predicted] الفونيمات المتوقَّعة من النموذج.
///
/// يُعيد قائمة AlignOp مرتّبة حسب التسلّسل الزمني.
List<AlignOp> alignPhonemes(
  List<int> reference,
  List<int> predicted,
) {
  final n = reference.length;
  final m = predicted.length;

  if (n == 0 && m == 0) return const [];

  // جدول المسافات (Wagner-Fischer).
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (int i = 0; i <= n; i++) {
    dp[i][0] = i;
  }
  for (int j = 0; j <= m; j++) {
    dp[0][j] = j;
  }

  for (int i = 1; i <= n; i++) {
    for (int j = 1; j <= m; j++) {
      if (reference[i - 1] == predicted[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1]; // match (cost 0)
      } else {
        dp[i][j] = 1 + [
          dp[i - 1][j], // delete
          dp[i][j - 1], // insert
          dp[i - 1][j - 1], // replace
        ].reduce((a, b) => a < b ? a : b);
      }
    }
  }

  // Backtrack لِاستخراج العمليّات.
  final ops = <AlignOp>[];
  int i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && reference[i - 1] == predicted[j - 1]) {
      ops.add(AlignOp(
        type: 'match',
        refId: reference[i - 1],
        predId: predicted[j - 1],
        refIdx: i - 1,
        predIdx: j - 1,
      ));
      i--;
      j--;
    } else if (i > 0 && (j == 0 || dp[i - 1][j] <= dp[i][j - 1])) {
      // delete: فونيم مرجعي مفقود في المتوقَّع
      ops.add(AlignOp(
        type: 'delete',
        refId: reference[i - 1],
        predId: null,
        refIdx: i - 1,
        predIdx: j,
      ));
      i--;
    } else if (j > 0 && (i == 0 || dp[i - 1][j] > dp[i][j - 1])) {
      // insert: فونيم زائد في المتوقَّع
      ops.add(AlignOp(
        type: 'insert',
        refId: null,
        predId: predicted[j - 1],
        refIdx: i,
        predIdx: j - 1,
      ));
      j--;
    } else {
      // replace: فونيم مختلف
      ops.add(AlignOp(
        type: 'replace',
        refId: reference[i - 1],
        predId: predicted[j - 1],
        refIdx: i - 1,
        predIdx: j - 1,
      ));
      i--;
      j--;
    }
  }

  return ops.reversed.toList(growable: false);
}

/// إحصاءات المحاذاة.
class AlignStats {
  AlignStats({required this.matches, required this.insertions,
      required this.deletions, required this.replacements});
  final int matches;
  final int insertions;
  final int deletions;
  final int replacements;

  int get totalOps => matches + insertions + deletions + replacements;
  int get errors => insertions + deletions + replacements;

  /// نسبة التطابق (0.0 - 1.0).
  double get accuracy => totalOps == 0 ? 0 : matches / totalOps;

  @override
  String toString() =>
      'matches=$matches, ins=$insertions, del=$deletions, rep=$replacements '
      '(${(accuracy * 100).toStringAsFixed(1)}%)';
}

/// احسب إحصاءات سريعة من قائمة ops.
AlignStats computeStats(List<AlignOp> ops) {
  int m = 0, ins = 0, del = 0, rep = 0;
  for (final op in ops) {
    switch (op.type) {
      case 'match':
        m++;
        break;
      case 'insert':
        ins++;
        break;
      case 'delete':
        del++;
        break;
      case 'replace':
        rep++;
        break;
    }
  }
  return AlignStats(
    matches: m, insertions: ins, deletions: del, replacements: rep);
}
