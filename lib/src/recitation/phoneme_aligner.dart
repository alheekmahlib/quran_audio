/// محاذاة فونيمات بِـ تجميع المدود (Group-Based Alignment).
///
/// الطبقة 2 المُحسَّنة: بدل محاذاة فونيمات مسطّحة، نُجمّع كلّ حرف + حركته +
/// مدّه في "وحدة واحدة" (Phoneme Group)، ثمّ نُحاذي الوحدات. هكذا:
/// - المدّ `اااا` يُعامل كَـ وحدة واحدة (لا 4 فونيمات منفصلة).
/// - الأخطاء تُحدَّد على مستوى الكلمة/الحرف، لا الإطار.
/// - يُطابق منطق خادم quran-muaalem.
library;

/// مجموعة فونيمات (حرف أساسي + حركته + مدّه).
class PhonemeGroup {
  PhonemeGroup({
    required this.ids,
    required this.baseId,
    required this.startIdx,
    required this.endIdx,
    this.isMadd = false,
  });

  /// كلّ معرّفات الفونيمات في المجموعة (مثلاً [29, 29, 29] لِـ مدّ ألف 3).
  final List<int> ids;

  /// المعرّف الأساسي (أوّل حرف، يُستخدم لِلمحاذاة).
  final int baseId;

  /// موضع البداية في القائمة الأصليّة (0-based).
  final int startIdx;

  /// موضع النهاية (exclusive).
  final int endIdx;

  /// هل هذه مجموعة مدّ (طول > 1)؟
  final bool isMadd;

  /// طول المجموعة (عدد الفونيمات).
  int get length => ids.length;

  @override
  String toString() => 'Group(base=$baseId, len=$length, madd=$isMadd)';
}

/// يُجمّع قائمة معرّفات فونيمات مسطّحة إلى مجموعات.
///
/// القاعدة: كلّ حرف ساكن/متحرّك يُشكّل مجموعة. الحروف المتكرّرة المتجاورة
/// (مثل ااا) تُدمج في مجموعة واحدة (مدّ).
List<PhonemeGroup> chunkPhonemes(List<int> ids) {
  if (ids.isEmpty) return const [];

  final groups = <PhonemeGroup>[];
  int i = 0;
  while (i < ids.length) {
    final baseId = ids[i];
    int j = i + 1;
    // ادمج كلّ الفونيمات المتكرّرة المتجاورة
    while (j < ids.length && ids[j] == baseId) {
      j++;
    }
    groups.add(PhonemeGroup(
      ids: ids.sublist(i, j),
      baseId: baseId,
      startIdx: i,
      endIdx: j,
      isMadd: (j - i) > 1,
    ));
    i = j;
  }
  return groups;
}

/// عمليّة محاذاة على مستوى المجموعات.
class GroupAlignOp {
  GroupAlignOp({
    required this.type,
    required this.refGroup,
    required this.predGroup,
  });

  /// 'match' | 'insert' | 'delete' | 'replace'
  final String type;

  /// المجموعة المرجعيّة (null لِـ insert).
  final PhonemeGroup? refGroup;

  /// المجموعة المتوقَّعة (null لِـ delete).
  final PhonemeGroup? predGroup;

  @override
  String toString() =>
      '$type(ref=${refGroup?.baseId}@${refGroup?.startIdx}, '
      'pred=${predGroup?.baseId}@${predGroup?.startIdx})';
}

/// يحاذي مجموعتي فونيمات (مرجعيّة vs متوقَّعة) على مستوى المجموعة.
///
/// يستخدم Wagner-Fischer على `baseId` لِكلّ مجموعة.
List<GroupAlignOp> alignGroups(
  List<PhonemeGroup> refGroups,
  List<PhonemeGroup> predGroups,
) {
  final n = refGroups.length;
  final m = predGroups.length;
  if (n == 0 && m == 0) return const [];

  // جدول المسافات
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (int i = 0; i <= n; i++) {
    dp[i][0] = i;
  }
  for (int j = 0; j <= m; j++) {
    dp[0][j] = j;
  }

  for (int i = 1; i <= n; i++) {
    for (int j = 1; j <= m; j++) {
      if (refGroups[i - 1].baseId == predGroups[j - 1].baseId) {
        dp[i][j] = dp[i - 1][j - 1]; // match
      } else {
        dp[i][j] = 1 + [
          dp[i - 1][j],
          dp[i][j - 1],
          dp[i - 1][j - 1],
        ].reduce((a, b) => a < b ? a : b);
      }
    }
  }

  // Backtrack
  final ops = <GroupAlignOp>[];
  int i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 &&
        refGroups[i - 1].baseId == predGroups[j - 1].baseId) {
      ops.add(GroupAlignOp(
        type: 'match',
        refGroup: refGroups[i - 1],
        predGroup: predGroups[j - 1],
      ));
      i--;
      j--;
    } else if (i > 0 && (j == 0 || dp[i - 1][j] <= dp[i][j - 1])) {
      ops.add(GroupAlignOp(
        type: 'delete',
        refGroup: refGroups[i - 1],
        predGroup: null,
      ));
      i--;
    } else if (j > 0 && (i == 0 || dp[i - 1][j] > dp[i][j - 1])) {
      ops.add(GroupAlignOp(
        type: 'insert',
        refGroup: null,
        predGroup: predGroups[j - 1],
      ));
      j--;
    } else {
      ops.add(GroupAlignOp(
        type: 'replace',
        refGroup: refGroups[i - 1],
        predGroup: predGroups[j - 1],
      ));
      i--;
      j--;
    }
  }

  return ops.reversed.toList(growable: false);
}

/// إحصاءات المحاذاة.
class AlignStats {
  AlignStats({
    required this.matches,
    required this.insertions,
    required this.deletions,
    required this.replacements,
  });
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

/// احسب إحصاءات سريعة من قائمة عمليّات المجموعات.
AlignStats computeGroupStats(List<GroupAlignOp> ops) {
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
    matches: m,
    insertions: ins,
    deletions: del,
    replacements: rep,
  );
}
