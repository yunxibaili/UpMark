/// T-122 笔记数据层测试：v3建表 / CRUD / 一题一篇唯一索引 / 墓碑流转 / pull恢复
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shengbentong/models/models.dart';
import 'package:shengbentong/services/db_service.dart';
import 'helpers/test_db.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DbService db;

  setUp(() async {
    db = await openTestDb('t_notes.db');
  });

  tearDown(() => db.close());

  Note note(String id,
          {String title = 't',
          String md = 'm',
          int? qid,
          bool deleted = false,
          DateTime? updated}) =>
      Note(
        id: id,
        title: title,
        contentMd: md,
        questionId: qid,
        deleted: deleted,
        createdAt: DateTime(2026, 8, 26, 10),
        updatedAt: updated ?? DateTime(2026, 8, 26, 10),
      );

  test('saveNote 新建后更新，created_at 保留首次值', () async {
    final id = await db.saveNote(id: 'n1', title: '第一版', contentMd: 'a');
    expect(id, 'n1');
    final createdFirst = (await db.noteById('n1'))!.createdAt;
    await Future.delayed(const Duration(milliseconds: 20));
    await db.saveNote(id: 'n1', title: '第二版', contentMd: 'b');
    final n = await db.noteById('n1');
    expect(n, isNotNull);
    expect(n!.title, '第二版');
    expect(n.createdAt, createdFirst); // 更新不改首次创建时间
    expect(n.updatedAt.isAfter(createdFirst), isTrue);
  });

  test('一题一篇：部分唯一索引拦截同题第二篇', () async {
    await db.saveNote(id: 'qa1', title: '', contentMd: '', questionId: 9001);
    await expectLater(
      db.saveNote(id: 'qa2', title: '', contentMd: '', questionId: 9001),
      throwsA(isA<Exception>()),
    );
    // 不同题不受影响
    await db.saveNote(id: 'qb1', title: '', contentMd: '', questionId: 9002);
    expect((await db.noteOfQuestion(9002))!.id, 'qb1');
  });

  test('noteOfQuestion 命中与未命中', () async {
    expect(await db.noteOfQuestion(7777), isNull);
    await db.saveNote(id: 'nq', title: '', contentMd: '', questionId: 7777);
    expect((await db.noteOfQuestion(7777))!.id, 'nq');
  });

  test('软删除清空 question_id 并入墓碑；purge 物理清除', () async {
    await db.saveNote(id: 'nd', title: '', contentMd: '', questionId: 8001);
    await db.softDeleteNote('nd');
    // 墓碑释放占位：同题可再建
    await db.saveNote(id: 'nd2', title: '', contentMd: '', questionId: 8001);
    expect((await db.tombstonedNotes()).map((n) => n.id), contains('nd'));
    // 默认列表不含墓碑
    expect((await db.allNotes()).map((n) => n.id), isNot(contains('nd')));
    await db.purgeTombstones();
    expect(await db.noteById('nd'), isNull);
    expect((await db.allNotes()).map((n) => n.id), contains('nd2'));
  });

  test('allNotes 按 updated_at 倒序', () async {
    await db.saveNote(id: 'o1', title: '', contentMd: '');
    await db.saveNote(id: 'o2', title: '', contentMd: '');
    final ids = (await db.allNotes()).map((n) => n.id).toList();
    expect(ids.indexOf('o2'), lessThan(ids.indexOf('o1')));
  });

  test('replaceAllNotes 以 PC 为准整体替换（丢弃墓碑行）', () async {
    await db.saveNote(id: 'local-keep-out', title: '本地旧', contentMd: '');
    await db.replaceAllNotes([
      note('pc1', title: '全局笔记', md: '# hi'),
      note('pc2', qid: 42, md: '![](noteimg://abc.png)'),
      note('tomb', deleted: true),
    ]);
    final all = await db.allNotes(includeDeleted: true);
    expect(all.length, 2);
    expect(all.map((n) => n.id), containsAll(['pc1', 'pc2']));
    expect((await db.liveNoteCount()), 2);
  });

  test('notesPushPayload 同时包含存活笔记与墓碑', () async {
    await db.saveNote(id: 'live1', title: 'L', contentMd: 'c');
    await db.saveNote(id: 'dead1', title: '', contentMd: '', questionId: 9);
    await db.softDeleteNote('dead1');
    final payload = await db.notesPushPayload();
    expect(payload.length, 2);
    final dead = payload.firstWhere((m) => m['id'] == 'dead1');
    expect(dead['deleted'], isTrue); // 契约布尔
    expect(dead['question_id'], isNull); // 软删除时已清空占位
  });

  test('newNoteHexId 为32位hex且不重复', () {
    final ids = {for (var i = 0; i < 200; i++) newNoteHexId()};
    expect(ids.length, 200);
    for (final id in ids) {
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
    }
  });
}
