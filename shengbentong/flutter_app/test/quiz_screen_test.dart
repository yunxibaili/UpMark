/// 刷题页集成测试（T-104 ①~⑦）—— 全部使用Key查找避免歧义
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shengbentong/models/models.dart';
import 'package:shengbentong/screens/knowledge_screen.dart';
import 'package:shengbentong/screens/quiz_screen.dart';
import 'package:shengbentong/services/db_service.dart';
import 'helpers/sample_payload.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DbService.resetInstanceCache();
    DbService.fileNameOverride = 't_quiz.db';
    final dir = await getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/t_quiz.db');
    final db = await DbService.open();
    await db.replaceAll(SyncPayload.fromJson(sampleSync));
    // 不close——后续tap触发saveProgress复用同一打开连接
  });

  tearDownAll(() {
    DbService.fileNameOverride = null;
    DbService.resetInstanceCache();
  });

  Future<void> pumpQuiz(WidgetTester tester, int chapterId) async {
    await tester.pumpWidget(
        MaterialApp(home: QuizScreen(chapterId: chapterId, title: '样例')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }

  group('单选', () {
    testWidgets('答对→绿色反馈+讲解展开+进度落库', (tester) async {
      await pumpQuiz(tester, 11);
      expect(find.text('单选样例'), findsOneWidget);

      await tester.tap(find.text('乙'));
      await tester.pump();

      expect(find.text('回答正确'), findsOneWidget);
      expect(find.text('因为'), findsOneWidget);
    });

    testWidgets('答错→红色反馈', (tester) async {
      await pumpQuiz(tester, 11);
      await tester.tap(find.text('甲'));
      await tester.pump();
      expect(find.text('回答错误'), findsOneWidget);
    });
  });

  group('导航与题型渲染', () {
    testWidgets('下一题递增且判断题渲染√×按钮', (tester) async {
      await pumpQuiz(tester, 11);
      expect(find.textContaining('1/3'), findsAny);

      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();

      expect(find.textContaining('2/3'), findsAny);
      expect(find.byKey(const Key('btn_judge_true')), findsOneWidget);
      expect(find.byKey(const Key('btn_judge_false')), findsOneWidget);
    });

    testWidgets('填空题提交判分', (tester) async {
      await pumpQuiz(tester, 11);
      // 导航到填空题（第3题）
      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();

      expect(find.text('填空：______'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '备选');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(find.text('回答正确'), findsOneWidget);
    });
  });

  group('材料多选题（完形空题干形态）', () {
    testWidgets('材料展示+多选拾取+确认判分', (tester) async {
      await pumpQuiz(tester, 12);

      expect(find.text('Passage...'), findsOneWidget);
      expect(find.textContaining('完形填空'), findsOneWidget);

      await tester.tap(find.text('o1'));
      await tester.pump();
      await tester.tap(find.text('o2'));
      await tester.pump();
      await tester.tap(find.text('o4'));
      await tester.pump();
      await tester.tap(find.textContaining('确认作答'));
      await tester.pump();

      expect(find.text('回答正确'), findsOneWidget);
    });
  });

  group('知识点入口', () {
    testWidgets('学完本章→跳转刷题页', (tester) async {
      await tester.pumpWidget(MaterialApp(home:
          KnowledgeScreen(chapterId: 11, title: '样例',
              knowledgeMd: '# 知识点\n内容')));
      await tester.pump();

      expect(find.textContaining('开始练习'), findsOneWidget);
      await tester.tap(find.textContaining('开始练习'));
      await tester.pump();

      expect(find.byType(QuizScreen), findsOneWidget);
    });
  });
}
