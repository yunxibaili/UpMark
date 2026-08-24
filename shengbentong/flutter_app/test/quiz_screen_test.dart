/// 刷题页集成测试（T-104）—— 纯内存Question，零IO零FakeAsync
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shengbentong/models/models.dart';
import 'package:shengbentong/screens/knowledge_screen.dart';
import 'package:shengbentong/screens/quiz_screen.dart';

Question mkSingle({String answer = 'B'}) => Question(
    id: 1, chapterId: 11, type: QuestionType.singleChoice,
    number: 1, globalSeq: 1, stem: '单选样例',
    options: ['甲', '乙', '丙', '丁'], answer: answer, explanation: '因为');

Question mkJudge({bool truth = false}) => Question(
    id: 2, chapterId: 11, type: QuestionType.judgment,
    number: 2, globalSeq: 2, stem: '判断样例。',
    options: [], answer: truth ? 'T' : 'F', explanation: '判断解析');

Question mkBlank({required List<List<String>> accepts}) => Question(
    id: 3, chapterId: 11, type: QuestionType.fillBlank,
    number: 3, globalSeq: 3, stem: '填空：______',
    options: [], answer: '', accepts: accepts, explanation: '填空解析');

Question mkMultiWithMaterial() => Question(
    id: 4, chapterId: 12, type: QuestionType.multipleChoice,
    number: 4, globalSeq: 4, material: 'Passage...',
    stem: '', options: ['o1', 'o2', 'o3', 'o4'],
    answer: 'ABD', explanation: '多选解析');

void main() {
  group('单选题', () {
    testWidgets('渲染题干+四选项+答对→绿色反馈+讲解展开', (tester) async {
      await tester.pumpWidget(MaterialApp(home:
          QuizScreen(title: 't', questions: [mkSingle()])));
      await tester.pump();

      expect(find.text('单选样例'), findsOneWidget);
      expect(find.text('甲'), findsOneWidget);

      await tester.tap(find.text('乙'));
      await tester.pump();

      expect(find.text('回答正确'), findsOneWidget);
      expect(find.text('因为'), findsOneWidget);
    });

    testWidgets('答错→红色反馈', (tester) async {
      await tester.pumpWidget(MaterialApp(home:
          QuizScreen(title: 't', questions: [mkSingle()])));
      await tester.tap(find.text('甲'));
      await tester.pump();
      expect(find.text('回答错误'), findsOneWidget);
    });
  });

  group('判断题', () {
    testWidgets('渲染√×按钮并判分', (tester) async {
      await tester.pumpWidget(MaterialApp(home:
          QuizScreen(title: 't', questions: [mkJudge(truth: false)])));
      await tester.pump();

      expect(find.text('判断样例。'), findsOneWidget);
      expect(find.text('正确'), findsOneWidget);
      expect(find.text('错误'), findsOneWidget);

      await tester.tap(find.text('错误'));
      await tester.pump();
      expect(find.text('回答正确'), findsOneWidget);
    });
  });

  group('填空题', () {
    testWidgets('提交备选答案命中', (tester) async {
      final q = mkBlank(accepts: [['答案', '备选']]);
      await tester.pumpWidget(MaterialApp(home:
          QuizScreen(title: 't', questions: [q])));
      await tester.pump();

      expect(find.text('填空：______'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '备选');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(find.text('回答正确'), findsOneWidget);
    });

    testWidgets('双空题用｜分隔提交', (tester) async {
      final q = mkBlank(accepts: [['编译'], ['链接']]);
      // 手动设置stem含两个空位
      final q2 = Question(
          id: q.id, chapterId: q.chapterId, type: q.type,
          number: q.number, globalSeq: q.globalSeq,
          stem: '第一______第二______',
          options: q.options, answer: '', accepts: q.accepts,
          explanation: '');
      await tester.pumpWidget(MaterialApp(home:
          QuizScreen(title: 't', questions: [q2])));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '编译｜链接');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(find.text('回答正确'), findsOneWidget);
    });
  });

  group('材料多选题（完形空题干形态）', () {
    testWidgets('材料展示+多选拾取+确认判分', (tester) async {
      await tester.pumpWidget(MaterialApp(home:
          QuizScreen(title: 't', questions: [mkMultiWithMaterial()])));
      await tester.pump();

      expect(find.text('Passage...'), findsOneWidget);
      expect(find.textContaining('完形填空'), findsAny);

      await tester.tap(find.text('o1'));
      await tester.pump();
      await tester.tap(find.text('o2'));
      await tester.pump();
      await tester.tap(find.text('o4'));
      await tester.pump();

      final confirm = find.textContaining('确认作答');
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();

      expect(find.text('回答正确'), findsOneWidget);   // ABD
    });
  });

  group('导航', () {
    testWidgets('下一题/上一题切换且题号递增', (tester) async {
      final qs = [mkSingle(), mkSingle(answer: 'C'),
                  mkJudge(truth: true)];
      await tester.pumpWidget(MaterialApp(home:
          QuizScreen(title: 't', questions: qs)));
      await tester.pump();

      expect(find.textContaining('1/3'), findsAny);
      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();
      expect(find.textContaining('2/3'), findsAny);
      await tester.tap(find.byKey(const Key('btn_prev')));
      await tester.pump();
      expect(find.textContaining('1/3'), findsAny);
    });
  });

  group('知识点入口', () {
    testWidgets('学完本章→跳转刷题页', (tester) async {
      await tester.pumpWidget(MaterialApp(home:
          KnowledgeScreen(title: '样例', knowledgeMd: '# 第一章知识点',
              questions: [mkSingle()])));
      await tester.pump();

      expect(find.textContaining('开始练习'), findsOneWidget);
      expect(find.text('本章无练习题'), findsNothing);

      await tester.tap(find.textContaining('开始练习'));
      await tester.pumpAndSettle();

      expect(find.text('单选样例'), findsOneWidget);
    });

    testWidgets('无题目时按钮禁用', (tester) async {
      await tester.pumpWidget(MaterialApp(home:
          KnowledgeScreen(title: '样例', knowledgeMd: null, questions: [])));
      await tester.pump();

      expect(find.text('本章无练习题'), findsOneWidget);
      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '本章无练习题'));
      expect(btn.onPressed, isNull);
    });
  });
}
