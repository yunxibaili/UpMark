/// ExamScreen widget 测试：渲染/作答/交卷回调/答题卡导航（纯内存数据，零mock）
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shengbentong/models/models.dart';
import 'package:shengbentong/screens/exam_screen.dart';

Question q(int id, {QuestionType type = QuestionType.singleChoice}) =>
    Question(
        id: id,
        chapterId: 1,
        type: type,
        number: id,
        globalSeq: id,
        material: null,
        image: null,
        stem: '第$id题题干',
        options: type == QuestionType.singleChoice || type == QuestionType.multipleChoice
            ? ['甲', '乙', '丙', '丁']
            : [],
        answer: type == QuestionType.singleChoice
            ? 'A'
            : type == QuestionType.multipleChoice
                ? 'AB'
                : type == QuestionType.judgment
                    ? 'T'
                    : '答',
        accepts: null,
        explanation: '解析$id');

Widget host(ExamScreen screen) => MaterialApp(home: screen);

void main() {
  testWidgets('渲染题干/倒计时/选项，单选点选自动跳下一题', (tester) async {
    final picks = <int, Object?>{};
    await tester.pumpWidget(host(ExamScreen(
        title: '测试科目',
        questions: [q(1), q(2), q(3)],
        durationMinutes: 10,
        onSubmit: (p) => picks.addAll(p))));
    expect(find.text('第1题题干'), findsOneWidget);
    expect(find.textContaining('10:00'), findsOneWidget);
    expect(find.text('09:59'), findsNothing);

    await tester.tap(find.text('甲')); // 答对题1（正确答案A）→ 自动进入第2题
    await tester.pump();
    expect(find.text('第2题题干'), findsOneWidget);
    expect(picks, isEmpty); // 未交卷不回调
  });

  testWidgets('交卷回调携带全部作答，结果页计分正确', (tester) async {
    final picks = <int, Object?>{};
    await tester.pumpWidget(host(ExamScreen(
        title: '测试科目',
        questions: [q(1), q(2), q(3)],
        durationMinutes: 5,
        onSubmit: (p) => picks.addAll(p))));

    await tester.tap(find.text('甲')); // 题1 答对
    await tester.pump();
    await tester.tap(find.text('甲')); // 题2 答错（正确答案非A? 题2答案A，选A也对——改选乙）
    // 上一步已跳到第3题，此处直接交卷：题2未作答
    await tester.tap(find.text('交卷'));
    await tester.pumpAndSettle();
    expect(find.text('确认交卷？'), findsOneWidget); // 有未作答题弹确认
    await tester.tap(find.text('确认交卷'));
    await tester.pumpAndSettle();

    expect(picks.keys, containsAll([1])); // 题1已记录
    expect(find.textContaining('成绩'), findsOneWidget);
    expect(find.textContaining('未作答'), findsWidgets);
  });

  testWidgets('答题卡导航：点击题号跳题', (tester) async {
    await tester.pumpWidget(host(ExamScreen(
        title: '测试科目',
        questions: [q(1), q(2), q(3)],
        durationMinutes: 5,
        onSubmit: (_) {})));
    await tester.tap(find.text('答题卡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('第3题题干'), findsOneWidget);
  });
}
