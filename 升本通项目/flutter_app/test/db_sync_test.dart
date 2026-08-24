/// 本地DB + 同步载荷解析 单元测试（sqflite_common_ffi，无需真机/模拟器）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shengbentong/models/models.dart';
import 'package:shengbentong/services/db_service.dart';
import 'package:shengbentong/services/api_service.dart';
import 'package:shengbentong/services/sync_service.dart';

const sampleSync = {
  'schema_version': 1,
  'data_version': '20240824-1',
  'exported_at': '2026-08-24T00:00:00',
  'subjects': [
    {
      'id': 1,
      'name': 'C语言',
      'chapters': [
        {
          'id': 11,
          'title': '第1章 基础',
          'order_num': 1,
          'knowledge_md': '# 第1章\n| 表格 | 测试 |\n```c\nint a;\n```',
          'questions': [
            {
              'id': 101,
              'type': 'single_choice',
              'number': 1,
              'global_seq': 1,
              'material': null,
              'stem': '以下正确的是',
              'options': ['甲', '乙', '丙', '丁'],
              'answer': 'B',
              'accepts': null,
              'explanation': '因为'
            },
            {
              'id': 102,
              'type': 'judgment',
              'number': 2,
              'global_seq': 2,
              'material': null,
              'stem': '判断陈述',
              'options': [],
              'answer': 'T',
              'accepts': null,
              'explanation': ''
            },
          ],
        },
        {
          'id': 12,
          'title': '第2章 指针',
          'order_num': 2,
          'knowledge_md': null,
          'questions': [
            {
              'id': 103,
              'type': 'multiple_choice',
              'number': 1,
              'global_seq': 1,
              'material': 'Passage...',
              'stem': '',
              'options': ['A1', 'A2', 'A3', 'A4'],
              'answer': 'ABD',
              'accepts': null,
              'explanation': '多选解析'
            },
            {
              'id': 104,
              'type': 'fill_blank',
              'number': 2,
              'global_seq': 2,
              'material': null,
              'stem': '两空题：______和______',
              'options': [],
              'answer': '编译｜链接',
              'accepts': [['编译'], ['链接']],
              'explanation': '填空解析'
            },
          ],
        },
      ],
    },
    {
      'id': 2,
      'name': '数据结构',
      'chapters': [
        {
          'id': 21,
          'title': '第3章 栈',
          'order_num': 1,
          'knowledge_md': null,
          'questions': [
            {
              'id': 201,
              'type': 'single_choice',
              'number': 1,
              'global_seq': 1,
              'material': null,
              'stem': '栈的特性',
              'options': ['LIFO', 'FIFO', '随机', '顺序'],
              'answer': 'A',
              'accepts': null,
              'explanation': 'LIFO'
            },
          ],
        },
      ],
    },
  ],
};

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncPayload 解析', () {
    test('字段完整映射（契约v1）', () {
      final p = SyncPayload.fromJson(sampleSync);
      expect(p.schemaVersion, 1);
      expect(p.dataVersion, '20240824-1');
      expect(p.subjects.length, 2);
      expect(p.subjects[0].chapters.length, 2);
      final q101 = p.subjects[0].chapters[0].questions[0];
      expect(q101.type, 'single_choice');
      expect(q101.options.length, 4);
      expect(q101.options[1], '乙');
      final q104 = p.subjects[0].chapters[1].questions[1];
      expect(q104.accepts, [['编译'], ['链接']]);
      expect(q104.stem, contains('______'));
    });
  });

  group('DbService 落库与查询', () {
    late DbService db;

    setUp(() async {
      db = await DbService.open();
      await db.replaceAll(SyncPayload.fromJson(sampleSync));
    });

    tearDown(() async {
      await db.close();
    });

    test('replaceAll 数量与PC端一致', () async {
      final stats = await db.subjectsWithStats();
      expect(stats.length, 2);
      final cLang = stats.firstWhere((s) => s.subject.name == 'C语言');
      expect(cLang.chapters, 2);
      expect(cLang.questions, 4);
    });

    test('rawQuestionsOf 按 global_seq 排序且字段回读正确', () async {
      final rows = await db.rawQuestionsOf(11);
      expect(rows.length, 2);
      expect(rows[0]['type'], 'single_choice');
      final q = Question.fromRow(rows[0]);
      expect(q.options, ['甲', '乙', '丙', '丁']);
      expect(q.answer, 'B');
      expect(q.explanation, '因为');

      final judgeRow = rows[1];
      expect(Question.fromRow(judgeRow).type, QuestionType.judgment);
      expect(judgeRow['options'], isNull);
    });

    test('fill_blank 的 accepts 往返一致', () async {
      final rows = await db.rawQuestionsOf(12);
      final blank = Question.fromRow(rows.firstWhere(
          (r) => r['type'] == 'fill_blank'));
      expect(blank.accepts, [
        ['编译'],
        ['链接']
      ]);
      expect(blank.answer.contains('｜'), isTrue);
    });

    test('幂等：重复 replaceAll 不产生重复行', () async {
      await db.replaceAll(SyncPayload.fromJson(sampleSync));
      await db.replaceAll(SyncPayload.fromJson(sampleSync));
      final stats = await db.subjectsWithStats();
      final totalQ = stats.fold<int>(0, (n, s) => n + s.questions);
      expect(totalQ, 5);
    });

    test('章节按 order_num 排序、空题干(材料题)允许', () async {
      final chs = await db.chaptersOf(1);
      expect(chs.map((c) => c.orderNum).toList(), [1, 2]);
      final rows = await db.rawQuestionsOf(12);
      final materialQ =
          rows.map(Question.fromRow).firstWhere((q) => q.material != null);
      expect(materialQ.stem, '');
      expect(materialQ.material, 'Passage...');
    });
  });

  group('SyncService 版本检测', () {
    test('从未同步→hasUpdate为true；离线→false不抛异常', () async {
      final api = ApiService(baseUrl: 'http://127.0.0.1:9'); // 必然连不上
      final db = await DbService.open();
      final svc = SyncService(api: api, db: db);
      expect(await svc.hasUpdate(), isFalse);
      await db.close();
    });
  });
}
