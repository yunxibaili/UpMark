/// SyncService 集成测试：本地HttpServer下发 → 全量落库 → 版本检测 → 图像原子下载
library;


import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
  String? qImage;                  // 非空时注入第1题的image字段

  Future<void> startServer() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path == '/api/sync/all') {
        final p = jsonDecode(jsonEncode(payloadV1)) as Map<String, dynamic>;
        p['data_version'] = version;
        if (qImage != null) {
          ((p['subjects'] as List)[0]['chapters'] as List)[0]['questions'][0]
              ['image'] = qImage;
        }
        req.response.write(jsonEncode(p));
      } else if (req.uri.path == '/api/health') {
        req.response.write(jsonEncode(
            {'status': 'ok', 'schema_version': 1, 'stats': {'subjects': 1}}));
      } else if (req.uri.path.startsWith('/static/images/')) {
        req.response.headers.contentType = ContentType.binary;
        req.response.add([1, 2, 3, 4]);
      } else {
        req.response.statusCode = 404;
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

  test('图像原子下载：落盘为正式名、无.tmp残留、DB改写本地路径', () async {
    qImage = '/static/images/a.png';
    final api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}');
    final db = await openTestDb('t_sync.db');

    final r = await SyncService(api: api, db: db).run((_) {});
    expect(r.questions, 2);

    final imgDir = p.join(await getDatabasesPath(), 'upmark_images');
    final finalFile = File(p.join(imgDir, 'a.png'));
    expect(await finalFile.exists(), isTrue, reason: '正式名文件应存在');
    expect(await finalFile.readAsBytes(), [1, 2, 3, 4]);
    expect(Directory(imgDir).listSync().whereType<File>().where(
        (f) => f.path.endsWith('.tmp')), isEmpty, reason: '不应残留.tmp');

    final rows = await db.rawQuestionsOf(100);
    expect(rows[0]['image'] as String, endsWith('a.png'));
    expect(rows[0]['image'] as String, isNot(contains('.tmp')));
  });

  test('图像下载前清理历史.tmp半成品', () async {
    qImage = '/static/images/a.png';
    final api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}');
    final db = await openTestDb('t_sync.db');
    final imgDir = p.join(await getDatabasesPath(), 'upmark_images');
    await Directory(imgDir).create(recursive: true);
    await File(p.join(imgDir, 'a.png.tmp')).writeAsBytes([9, 9]);

    await SyncService(api: api, db: db).run((_) {});

    expect(File(p.join(imgDir, 'a.png.tmp')).existsSync(), isFalse,
        reason: '历史半成品应被清理');
    expect(File(p.join(imgDir, 'a.png')).readAsBytesSync(), [1, 2, 3, 4]);
  });
}
