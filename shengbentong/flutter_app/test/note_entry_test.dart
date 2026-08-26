/// T-124 笔记入口接线测试：刷题页笔记回调 + 全局笔记列表（空态/列表/长按删除）
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shengbentong/models/models.dart';
import 'package:shengbentong/screens/notes_home_screen.dart';
import 'package:shengbentong/screens/quiz_screen.dart';
import 'package:shengbentong/services/db_service.dart';
import 'helpers/test_db.dart';

Question _mkSingle({required int id}) => Question(
    id: id, chapterId: 11, type: QuestionType.singleChoice,
    number: id, globalSeq: id, stem: '题$id',
    options: ['甲', '乙', '丙', '丁'], answer: 'B', explanation: '因为');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('QuizScreen 本题笔记入口', () {
    testWidgets('未传 onOpenNote 时不显示入口；传入后点击携带当前题目id',
        (tester) async {
      final ids = <int>[];
      final qs = [_mkSingle(id: 1), _mkSingle(id: 2)];
      await tester.pumpWidget(MaterialApp(home:
          QuizScreen(title: 't', questions: qs)));
      expect(find.byTooltip('本题笔记'), findsNothing);

      await tester.pumpWidget(MaterialApp(home:
          QuizScreen(title: 't', questions: qs,
              onOpenNote: (qid) async => ids.add(qid))));
      await tester.tap(find.byTooltip('本题笔记'));
      await tester.pump();
      expect(ids, [1]);

      // 翻到第二题再点
      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();
      await tester.tap(find.byTooltip('本题笔记'));
      await tester.pump();
      expect(ids, [1, 2]);
    });
  });

  group('NotesHomeScreen', () {
    late DbService db;
    late Directory tmpDir;

    setUp(() async {
      db = await openTestDb('t_notes_home.db');
      tmpDir = await Directory.systemTemp.createTemp('notes_home_test');
    });
    tearDown(() async {
      await db.close();
      for (var i = 0; i < 5; i++) {
        try {
          if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    });

    Widget host() => MaterialApp(home:
        NotesHomeScreen(db: db, databasesDir: tmpDir.path));

    testWidgets('空态提示', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(host());
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      });
      expect(find.textContaining('还没有笔记'), findsOneWidget);
    });

    testWidgets('列表展示标题/摘要/题目标签，长按弹删除确认', (tester) async {
      // 预置数据与首帧在真实IO环境完成
      await tester.runAsync(() async {
        await db.saveNote(
            id: 'g1', title: '全局篇', contentMd: '**指针** 重点');
        await db.saveNote(
            id: 'q1', title: '', contentMd: '题目相关', questionId: 9001);
        await tester.pumpWidget(host());
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
      });
      expect(find.text('全局篇'), findsOneWidget);
      expect(find.textContaining('指针 重点'), findsOneWidget);
      expect(find.text('题目笔记'), findsOneWidget);

      // 长按→确认框：纯假异步段（无真实IO）
      await tester.longPress(find.byKey(const Key('note_item_g1')));
      await tester.pumpAndSettle();
      expect(find.text('删除这条笔记？'), findsOneWidget);
      // 取消不动数据（端到端墓碑流转由 note_editor_test 删除用例覆盖）
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note_item_g1')), findsOneWidget);
    });
  });
}
