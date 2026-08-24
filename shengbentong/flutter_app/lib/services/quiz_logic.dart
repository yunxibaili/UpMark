/// 判分纯逻辑 —— 无IO，可独立单元测试（T-104核心）
library;

import '../models/models.dart';

enum AnswerState { unanswered, correct, wrong }

class UserAnswer {
  final String display;      // 用户作答原文（选项字母串/√×/填空文本）
  final bool isCorrect;

  const UserAnswer({required this.display, required this.isCorrect});
}

class QuizLogic {
  QuizLogic._();

  /// 按题型统一判分入口。
  /// single: pick='A'；multiple: pick=['A','D']；
  /// judgment: pick=bool 或 '√'/'×'；blank: 用户整段输入（多空用｜分隔）。
  static UserAnswer evaluate(Question q, Object? pick) => switch (q.type) {
        QuestionType.singleChoice => _single(q.answer, pick),
        QuestionType.multipleChoice => _multiple(q.answer, pick),
        QuestionType.judgment => _judge(q.answer, pick),
        QuestionType.fillBlank => _blank(q, pick),
      };

  static String _norm(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').replaceAll('；', ';').toUpperCase();

  static UserAnswer _single(String answer, Object? pick) {
    final v = _norm((pick ?? '').toString());
    if (v.isEmpty) return const UserAnswer(display: '未作答', isCorrect: false);
    return UserAnswer(display: v, isCorrect: v == _norm(answer));
  }

  static UserAnswer _multiple(String answer, Object? pick) {
    final picks = (pick as List?)
            ?.map((e) => _norm(e.toString()))
            .where((e) => e.isNotEmpty)
            .toSet() ??
        <String>{};
    final sorted = (picks.toList()..sort()).join();
    final truth = (_norm(answer).split('')..sort()).join();
    if (sorted.isEmpty) {
      return const UserAnswer(display: '未作答', isCorrect: false);
    }
    return UserAnswer(display: sorted, isCorrect: sorted == truth);
  }

  static UserAnswer _judge(String answer, Object? pick) {
    final truth = _norm(answer) == 'T';

    final bool userBool;
    if (pick is bool) {
      userBool = pick;
    } else {
      final v = _norm((pick ?? '').toString());
      userBool = switch (v) {
        'TRUE' || '√' || '对' || '正确' => true,
        'FALSE' || '×' || 'X' || '错' || '错误' => false,
        '' => throw ArgumentError('未作答'),
        _ => throw FormatException('无法识别的判断答案: $pick'),
      };
    }
    return UserAnswer(display: userBool ? '√' : '×',
        isCorrect: userBool == truth);
  }

  static UserAnswer _blank(Question q, Object? pick) {
    final input = ((pick ?? '') as String).trim();
    if (input.isEmpty) {
      return const UserAnswer(display: '未作答', isCorrect: false);
    }
    final blankCount = RegExp('_{{3,}}').allMatches(q.stem).length;
    List<List<String>> expected;
    if (q.accepts != null && q.accepts!.isNotEmpty) {
      expected = q.accepts!;
    } else {
      final rawSegs = q.answer.split('｜');
      expected = [
        for (final seg in rawSegs)
          seg.split(';').map(_norm).where((a) => a.isNotEmpty).toList()
      ];
      if (expected.length != blankCount && blankCount > 1) {
        return UserAnswer(display: input, isCorrect: false);
      }
    }

    var userSegs = input.split('｜').map(_norm).toList();

    // 单空宽容：未按｜分隔但只有一空 → 直接整体比对
    if (userSegs.length != expected.length && expected.length > 1) {
      return UserAnswer(display: input, isCorrect: false);
    }

    for (var i = 0; i < expected.length; i++) {
      final alts = expected[i]
          .expand((a) => a.split(';'))
          .map(_norm)
          .where((a) => a.isNotEmpty)
          .toSet();
      final u = i < userSegs.length ? userSegs[i] : '';
      if (u.isNotEmpty && !alts.contains(u)) {
        return UserAnswer(display: input, isCorrect: false);
      }
    }
    return UserAnswer(display: input, isCorrect: true);
  }
}
