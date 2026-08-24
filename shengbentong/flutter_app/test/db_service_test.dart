/// DbService 字段完整性测试（T-103验收：查科目/章节字段齐全）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shengbentong/models/models.dart';
import 'package:shengbentong/services/db_service.dart';
import 'helpers/sample_payload.dart';
import 'helpers/test_db.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  late DbService db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDb('t_dbservice.db');
    await db.replaceAll(SyncPayload.fromJson(sampleSync));
  });

  tearDown(() => db.close());

  test('subjectsWithStats 返回名称/章节/题数字段完整', () async {
    final stats = await db.subjectsWithStats();
    expect(stats, isNotEmpty);
    for (final s in stats) {
      expect(s.subject.id, greaterThan(0));
      expect(s.subject.name, isNotEmpty);
      expect(s.chapters, greaterThanOrEqualTo(0));
      expect(s.questions, greaterThanOrEqualTo(0));
    }
  });

  test('chaptersOf 字段完整且按 order_num 升序', () async {
    // sample 中科目id=1 有两个章 order 1,2
    final chs = await db.chaptersOf(1);
    expect(chs.length, greaterThanOrEqualTo(2));
    expect(chs.map((c) => c.orderNum).toList(), everyElement(isA<int>()));
    for (var i = 1; i < chs.length; i++) {
      expect(chs[i].orderNum >= chs[i - 1].orderNum, isTrue);
    }
    for (final c in chs) {
      expect(c.title, isNotEmpty);
      // knowledge_md 允许为 null，但字段必须存在（fromRow 不抛即通过）
    }
  });

  test('knowledgeOf 命中与未命中', () async {
    // sample 第一个章 id=11 带 knowledge
    final hit = await db.knowledgeOf(11);
    expect(hit, isNotNull);
    final miss = await db.knowledgeOf(999999);
    expect(miss, isNull);
  });
}
