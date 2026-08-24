/// SyncService 集成测试：本地HttpServer下发 → 全量落库 → 版本检测
library;


import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'helpers/test_db.dart';

import 'package:shengbentong/services/api_service.dart';

import 'package:shengbentong/services/sync_service.dart';

const payloadV1 = {
  'schema_version': 1,
  'data_version': 'VTEST-1',
  'exported_at': '2026-08-24T00:00:00',
  'subjects': [
    {
      'id': 1,
      'name': '测试科目',
      'chapters': [
        {
          'id': 100,
          'title': '第1章',
          'order_num': 1,
          'knowledge_md': '# K\n内容',
          'questions': [
            {
              'id': 501,
              'type': 'single_choice',
              'number': 1,
              'global_seq': 1,
              'material': null,
              'stem': 'q1',
              'options': ['a', 'b'],
              'answer': 'A',
              'accepts': null,
              'explanation': 'e'
            },
            {
              'id': 502,
              'type': 'fill_blank',
              'number': 2,
              'global_seq': 2,
              'material': null,
              'stem': '______',
              'options': [],
              'answer': '答',
              'accepts': [['答']],
              'explanation': ''
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

  late HttpServer server;
  String version = 'VTEST-1';

  Future<void> startServer() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path == '/api/sync/all') {
        final p = Map<String, dynamic>.from(payloadV1);
        p['data_version'] = version;
        req.response.write(jsonEncode(p));
      } else if (req.uri.path == '/api/health') {
        req.response.write(jsonEncode(
            {'status': 'ok', 'schema_version': 1, 'stats': {'subjects': 1}}));
      }
      await req.response.close();
    });
  }

  setUp(() async {
    version = 'VTEST-1';
    SharedPreferences.setMockInitialValues({});
    await startServer();
  });

  tearDown(() => server.close(force: true));

  test('全量同步后：DB数量=预期，data_version已保存，hasUpdate=false', () async {
    final api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}');
    final db = await openTestDb('t_sync.db');
    final svc = SyncService(api: api, db: db);

    final r = await svc.run((_) {});
    expect(r.subjects, 1);
    expect(r.chapters, 1);
    expect(r.questions, 2);

    final rows = await db.rawQuestionsOf(100);
    expect(rows.length, 2);
    expect(rows[0]['stem'], 'q1');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('data_version'), 'VTEST-1');
    expect(await svc.hasUpdate(), isFalse);
  });

  test('服务端版本变化 → hasUpdate=true（题库更新提示依据）', () async {
    final api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}');
    final db = await openTestDb('t_sync.db');
    final svc = SyncService(api: api, db: db);

    await svc.run((_) {});           // 同步 VTEST-1
    version = 'VTEST-2';             // 服务端升版
    expect(await svc.hasUpdate(), isTrue);
  });

  test('阶段回调依次触发且非空', () async {
    final api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}');
    final db = await openTestDb('t_sync.db');
    final stages = <String>[];
    await SyncService(api: api, db: db).run(stages.add);
    expect(stages.length, greaterThanOrEqualTo(3));
    expect(stages.first, contains('下载'));
  });
}
