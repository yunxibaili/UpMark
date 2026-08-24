/// T-105 进阶功能服务层测试：错题本/收藏/统计/上传队列（sqflite_common_ffi）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shengbentong/models/models.dart';
import 'package:shengbentong/services/db_service.dart';
import 'helpers/test_db.dart';

/// 与 db_sync_test 同构的最小题库（2科目3章4题，含JOIN所需外键链）
const bank = {
  'schema_version': 1,
  'data_version': 'v-t105',
  'exported_at': '2026-08-24T00:00:00',
  'subjects': [
    {
      'id': 1,
      'name': '考研政治',
      'chapters': [
        {
          'id': 11,
          'title': '马原',
          'order_num': 1,
          'knowledge_md': null,
          'questions': [
            {
              'id': 101,
              'type': 'single_choice',
              'number': 1,
              'global_seq': 1,
              'material': null,
              'stem': '物质的唯一特性',
              'options': ['运动', '客观实在性', '可知', '广延'],
              'answer': 'B',
              'accepts': null,
              'explanation': '列宁物质定义'
            },
            {
              'id': 102,
              'type': 'judgment',
              'number': 2,
              'global_seq': 2,
              'material': null,
              'stem': '实践是检验真理的唯一标准。',
              'options': [],
              'answer': 'T',
              'accepts': null,
              'explanation': ''
            },
          ],
        },
      ],
    },
    {
      'id': 2,
      'name': '高等数学',
      'chapters': [
        {
          'id': 21,
          'title': '极限',
          'order_num': 1,
          'knowledge_md': null,
          'questions': [
            {
              'id': 201,
              'type': 'fill_blank',
              'number': 1,
              'global_seq': 1,
              'material': null,
              'stem': 'lim sinx/x = ______',
              'options': [],
              'answer': '1',
              'accepts': [['1']],
              'explanation': '重要极限'
            },
          ],
        },
      ],
    },
  ],
};

void main() {
  setUpAll(() {
    initFfi();
    SharedPreferences.setMockInitialValues({});
  });

  late DbService db;
  setUp(() async {
    db = await openTestDb('t_t105.db');
    await db.replaceAll(SyncPayload.fromJson(bank));
  });
  tearDown(() async => db.close());

  group('错题本流转', () {
    test('答错自动入本→重练答对自动移出', () async {
      await db.saveProgress(questionId: 101, isCorrect: false);
      expect(await db.wrongQuestionIds(), [101]);

      // 重练答对（未显式传收藏 → 保持原状）
      await db.saveProgress(questionId: 101, isCorrect: true);
      expect(await db.wrongQuestionIds(), isEmpty);
    });

    test('答错不影响已有收藏位；手动移除生效', () async {
      await db.setFavorite(102, true);
      await db.saveProgress(questionId: 102, isCorrect: false);
      var rows = await db.rawQuery(
          'SELECT in_favorites, in_wrong_book FROM local_progress '
          'WHERE question_id = 102');
      expect(rows.single['in_favorites'], 1); // 收藏被保留
      expect(rows.single['in_wrong_book'], 1);

      await db.removeFromWrongBook(102);
      rows = await db.rawQuery(
          'SELECT in_wrong_book, in_favorites FROM local_progress '
          'WHERE question_id = 102');
      expect(rows.single['in_wrong_book'], 0);
      expect(rows.single['in_favorites'], 1);
    });

    test('wrongBookEntries 带科目名JOIN', () async {
      await db.saveProgress(questionId: 101, isCorrect: false);
      final entries = await db.wrongBookEntries();
      expect(entries.length, 1);
      expect(entries.single['qid'], 101);
      expect(entries.single['subject'], '考研政治');
    });
  });

  group('收藏夹', () {
    test('未答过的题也可直接收藏（建行不误标错题）', () async {
      await db.setFavorite(201, true);
      final row = (await db.rawQuery(
              'SELECT * FROM local_progress WHERE question_id = 201'))
          .single;
      expect(row['in_favorites'], 1);
      expect(row['in_wrong_book'], 0);

      expect((await db.favoriteQuestionIds()), [201]);
      expect((await db.favoriteEntries()).single['subject'], '高等数学');

      await db.setFavorite(201, false);
      expect(await db.favoriteQuestionIds(), isEmpty);
    });
  });

  group('统计汇总', () {
    test('statsSummary 与 accuracyBySubject 数字正确', () async {
      await db.saveProgress(questionId: 101, isCorrect: true);
      await db.saveProgress(questionId: 102, isCorrect: false);
      await db.saveProgress(questionId: 201, isCorrect: true);
      await db.setFavorite(101, true);

      final s = await db.statsSummary();
      expect(s['answered'], 3);
      expect(s['correct'], 2);
      expect(s['accuracy'] as double, closeTo(2 / 3, 1e-9));
      expect(s['wrong_book'], 1);
      expect(s['favorites'], 1);
      expect(s['pending_upload'],
          4); // 3次答题+1次收藏各入队一条

      final bySubject = await db.accuracyBySubject();
      final zz = bySubject.firstWhere((r) => r['subject'] == '考研政治');
      expect(zz['answered'], 2);
      expect(zz['correct'], 1);
    });

    test('零作答时accuracy为null而非除零异常', () async {
      final s = await db.statsSummary();
      expect(s['answered'], 0);
      expect(s['accuracy'], isNull);
    });
  });

  group('上传队列', () {
    test('pendingQueueRows/clearQueueRows 往返', () async {
      await db.saveProgress(questionId: 101, isCorrect: true);
      await db.saveProgress(questionId: 201, isCorrect: false);

      var rows = await db.pendingQueueRows();
      expect(rows.length, 2);
      final payload = rows.first['payload'] as String;
      expect(payload, contains('"question_id":101'));
      expect(payload, contains('in_wrong_book'));

      await db.clearQueueRows([rows.first['id'] as int]);
      rows = await db.pendingQueueRows();
      expect(rows.length, 1);
      expect(rows.single['question_id'], 201);
    });
  });

  group('questionsByIds', () {
    test('按传入顺序返回且字段完整', () async {
      final qs = await db.questionsByIds([201, 101]);
      expect(qs.map((q) => q.id).toList(), [201, 101]);
      expect(qs[1].type, QuestionType.singleChoice);
      expect(qs[1].options.length, 4);
      expect(() async => await db.questionsByIds([]), returnsNormally);
    });
  });
}
