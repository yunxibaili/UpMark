/// T-126 Live Preview 编辑器测试：块切换/写回/回车新块/撤销/工具栏/预览/删除/返回自动保存
///
/// 涉及真实 IO 的用例（sqflite ffi / 文件拷贝）包 tester.runAsync，
/// 假时钟+真实IO 交替推进（pump+delay 交错），避免死锁。
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

  TextEditingController editingCtrl(WidgetTester tester) =>
      tester.widget<TextField>(find.descendant(
          of: find.byKey(const Key('live_editing_block')),
          matching: find.byType(TextField))).controller!;

  testWidgets('空文档：出现一个可编辑空块（含 × 删除钮）', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live_editing_block')), findsNothing);
    // 点渲染块进入编辑
    await tester.tap(find.byKey(const Key('live_block_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live_editing_block')), findsOneWidget);
    expect(find.byKey(const Key('btn_delete_empty_block')), findsOneWidget);
  });

  testWidgets('全局笔记：标题+正文（Live 编辑）保存落库', (tester) async {
    await tester.pumpWidget(host());
    await tester.enterText(
        find.byKey(const Key('field_note_title')), 'Live笔记');
    await tester.tap(find.byKey(const Key('live_block_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('live_editing_block')), '**重点**内容');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('btn_save')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final notes = await tester.runAsync(() => db.allNotes());
    expect(notes!.single.title, 'Live笔记');
    expect(notes.single.contentMd, '**重点**内容');
  });

  testWidgets('块尾回车 → 新建段落块（Typora 行为）', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('live_block_0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('live_editing_block')),
        '第一段\n'); // 末尾回车
    await tester.pumpAndSettle();
    // 第一段成为渲染块，新空段落块进入编辑态
    expect(find.text('第一段'), findsOneWidget);
    expect(find.byKey(const Key('live_block_0')), findsOneWidget);
    expect(find.byKey(const Key('live_editing_block')), findsOneWidget);
    expect(editingCtrl(tester).text, '');
  });

  testWidgets('撤销：输入后 undo 清空文档内容', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('live_block_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('live_editing_block')), 'some text');
    await tester.pumpAndSettle();
    // 失焦提交（产生撤销快照）
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live_editing_block')), findsNothing,
        reason: '失焦后应退出编辑态');
    await tester.tap(find.byKey(const Key('btn_undo')));
    await tester.pumpAndSettle();
    // 撤销后回到空文档：渲染块无文本
    expect(find.text('some text'), findsNothing);
  });

  testWidgets('工具栏作用于当前编辑块：围栏插入', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('live_block_0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('live_editing_block')), 'x');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn_fence')));
    await tester.pumpAndSettle();
    expect(editingCtrl(tester).text, 'x```c\n\n```');
  });

  testWidgets('题目笔记：无标题框；保存绑定 question_id', (tester) async {
    await tester.pumpWidget(host(questionId: 555));
    expect(find.byKey(const Key('field_note_title')), findsNothing);
    await tester.tap(find.byKey(const Key('live_block_0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('live_editing_block')), '题解');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('btn_save')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final n = await tester.runAsync(() => db.noteOfQuestion(555));
    expect(n, isNotNull);
    expect(n!.contentMd, '题解');
    expect(n.questionId, 555);
  });

  testWidgets('插图流程：底单选相册 → noteimg 引用插入且文件入库', (tester) async {
    await tester.pumpWidget(host(pick: (source) async {
      final f = File('${tmpDir.path}/picked.png');
      await f.writeAsBytes([8, 8, 8]);
      return f.path;
    }));
    await tester.tap(find.byKey(const Key('btn_image')));
    await tester.pumpAndSettle(); // 底单
    await tester.runAsync(() async {
      await tester.tap(find.text('从相册选择'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final done = find
                .byKey(const Key('live_editing_block'))
                .evaluate()
                .isNotEmpty &&
            editingCtrl(tester).text.contains('noteimg://');
        if (done) break;
      }
    });
    await tester.pumpAndSettle();
    expect(editingCtrl(tester).text, contains('![](noteimg://'));
    final imgDir = Directory('${tmpDir.path}/upmark_note_images');
    final copied = await tester.runAsync(() async {
      final ok = await imgDir.exists();
      return ok ? await imgDir.list().length : 0;
    });
    expect(copied, 1);
  });

  testWidgets('全文档预览：眼睛切换，显示标题与渲染内容', (tester) async {
    await tester.pumpWidget(host(initial:
        Note(id: 'pv1', title: '预览篇', contentMd: '# 标题一\n\n正文**加粗**')));
    await tester.tap(find.byKey(const Key('btn_toggle_preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane_preview')), findsOneWidget);
    expect(find.textContaining('标题一'), findsOneWidget);
    // 切回编辑
    await tester.tap(find.byKey(const Key('btn_toggle_preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live_block_0')), findsOneWidget);
  });

  testWidgets('删除：确认后本地墓碑化', (tester) async {
    await tester.runAsync(() => db.saveNote(
        id: 'del1', title: '旧笔记', contentMd: 'c'));
    await tester.pumpWidget(host(initial:
        Note(id: 'del1', title: '旧笔记', contentMd: 'c')));
    await tester.tap(find.byKey(const Key('btn_delete')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final tombstones = await tester.runAsync(() => db.tombstonedNotes());
    expect(tombstones!.map((n) => n.id), contains('del1'));
  });

  testWidgets('返回时未保存修改自动静默落库', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) =>
        Scaffold(body: Center(child: FilledButton(
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(
                builder: (_) => NoteEditorScreen(
                    db: db, databasesDir: tmpDir.path))),
            child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('field_note_title')), '自动存');
    await tester.tap(find.byKey(const Key('live_block_0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('live_editing_block')), '内容');
    await tester.runAsync(() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
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
