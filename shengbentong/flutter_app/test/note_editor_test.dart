/// T-123 笔记编辑器测试：保存/题目绑定/工具栏/预览/删除/返回自动保存
///
/// 涉及真实 IO 的用例（sqflite ffi / 文件拷贝）整体包 tester.runAsync，
/// 避免假异步环境死锁；纯 UI 断言照常用 pump/pumpAndSettle。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shengbentong/models/models.dart';
import 'package:shengbentong/screens/note_editor_screen.dart';
import 'package:shengbentong/services/db_service.dart';
import 'helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DbService db;
  late Directory tmpDir;

  setUp(() async {
    db = await openTestDb('t_note_editor.db');
    tmpDir = await Directory.systemTemp.createTemp('note_editor_test');
  });
  tearDown(() async {
    await db.close();
    // 图片句柄释放可能滞后，重试删除
    for (var i = 0; i < 5; i++) {
      try {
        if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  Widget host({Note? initial, int? questionId,
      Future<String?> Function(ImageSource)? pick}) => MaterialApp(
          home: NoteEditorScreen(db: db, databasesDir: tmpDir.path,
              initial: initial, questionId: questionId, pickImage: pick));

  testWidgets('全局笔记：填标题与正文，保存落库', (tester) async {
    await tester.pumpWidget(host());
    await tester.enterText(find.byKey(const Key('field_note_title')), '指针易错点');
    await tester.enterText(
        find.byKey(const Key('field_note_md')), '**重点** 内容');
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('保存'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final notes = await tester.runAsync(() => db.allNotes());
    expect(notes!.length, 1);
    expect(notes.single.title, '指针易错点');
    expect(notes.single.contentMd, '**重点** 内容');
    expect(notes.single.questionId, isNull);
  });

  testWidgets('题目笔记：无标题框；工具栏插代码围栏；保存绑定 question_id',
      (tester) async {
    await tester.pumpWidget(host(questionId: 555));
    expect(find.byKey(const Key('field_note_title')), findsNothing);
    await tester.enterText(find.byKey(const Key('field_note_md')), 'x');
    await tester.tap(find.byKey(const Key('btn_fence')));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('保存'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final n = await tester.runAsync(() => db.noteOfQuestion(555));
    expect(n, isNotNull);
    expect(n!.contentMd, contains('```c'));
    expect(n.questionId, 555);
  });

  testWidgets('插图流程：底单选相册 → 注入选图 → noteimg 引用入正文且文件入库',
      (tester) async {
    var picked = false;
    await tester.pumpWidget(host(pick: (source) async {
      picked = true;
      final f = File('${tmpDir.path}/picked.png');
      await f.writeAsBytes([8, 8, 8]);
      return f.path;
    }));
    // 路由动画走假时钟、文件IO走真实时间——必须交替 pump+delay 推进整条链路
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('btn_image')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // 底单展开动画
      if (find.text('从相册选择').evaluate().isNotEmpty) {
        await tester.tap(find.text('从相册选择'));
      }
      final mdFinder = find.byKey(const Key('field_note_md'));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final ctrl = tester.widget<TextField>(mdFinder).controller!;
        if (ctrl.text.contains('noteimg://')) break;
      }
    });
    await tester.pumpAndSettle();
    expect(picked, isTrue);
    final ctrl =
        tester.widget<TextField>(find.byKey(const Key('field_note_md')))
            .controller!;
    expect(ctrl.text, contains('![](noteimg://'));
    final imgDir = Directory('${tmpDir.path}/upmark_note_images');
    final copied = await tester.runAsync(() async {
      final ok = await imgDir.exists();
      return ok ? await imgDir.list().length : 0;
    });
    expect(copied, 1);
  });

  testWidgets('预览 Tab 渲染 NoteMarkdownView', (tester) async {
    await tester.pumpWidget(host(initial:
        Note(id: 'pv1', title: 't', contentMd: '# 标题一\n\n正文**加粗**')));
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane_preview')), findsOneWidget);
    expect(find.textContaining('标题一'), findsOneWidget);
  });

  testWidgets('删除：确认后本地墓碑化', (tester) async {
    await tester.runAsync(() => db.saveNote(id: 'del1',
        title: '旧笔记', contentMd: 'c'));
    await tester.pumpWidget(host(initial:
        Note(id: 'del1', title: '旧笔记', contentMd: 'c')));
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle(); // 确认对话框
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final tombstones = await tester.runAsync(() => db.tombstonedNotes());
    expect(tombstones!.map((n) => n.id), contains('del1'));
  });

  testWidgets('返回时未保存修改自动静默落库', (tester) async {
    // 直接推裸编辑器（不再包 MaterialApp），保证 PopScope 注册到同一 Navigator
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) =>
        Scaffold(body: Center(child: FilledButton(
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(
                builder: (_) => NoteEditorScreen(
                    db: db, databasesDir: tmpDir.path))),
            child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field_note_title')), '自动存');
    await tester.enterText(find.byKey(const Key('field_note_md')), '内容');
    // 触发与系统返回等价的 pop（走 PopScope 自动保存）；假时钟+真实IO交替推进
    await tester.runAsync(() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final notes = await db.allNotes();
        if (notes.any((n) => n.title == '自动存')) break;
      }
    });
    await tester.pumpAndSettle();
    final notes = await tester.runAsync(() => db.allNotes());
    expect(notes!.map((n) => n.title), contains('自动存'));
  });
}
