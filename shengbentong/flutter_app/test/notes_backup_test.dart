/// T-125 笔记备份全链路测试：push(含墓碑+补图+清墓碑) / pull(整体替换+原子下载)
/// 用本地 HttpServer 实测，零 mock。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shengbentong/services/api_service.dart';
import 'package:shengbentong/services/db_service.dart';
import 'package:shengbentong/services/note_image_store.dart';
import 'package:shengbentong/services/notes_backup_service.dart';
import 'helpers/test_db.dart';

void main() {
  // 注意：不调 TestWidgetsFlutterBinding.ensureInitialized——
  // 一旦激活 binding，所有 HTTP 都会被 mock 成 400，无法实测本地服务。
  // sqflite 走 databaseFactoryFfi 全局注入即可。
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DbService db;
  late Directory tmpDir;

  setUp(() async {
    db = await openTestDb('t_notes_backup.db');
    tmpDir = await Directory.systemTemp.createTemp('notes_backup_test');
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

  test('pushBackup：推送含墓碑 → 按missing补传本地图片 → 清除本地墓碑',
      () async {
    final imgBytes = Uint8List.fromList(utf8.encode('local-png-bytes'));
    // 本地准备一张被引用的图片
    final dir =
        await ensureNoteImagesDir(tmpDir.path);
    final localImg = File('${dir.path}${Platform.pathSeparator}aa00112233445566.png');
    await localImg.writeAsBytes(imgBytes);

    await db.saveNote(
        id: 'live1', title: '存活', contentMd: '![](noteimg://aa00112233445566.png)');
    await db.saveNote(id: 'dead1', title: '', contentMd: '');
    await db.softDeleteNote('dead1');

    final uploaded = <String, Uint8List>{};
    final s = await HttpServer.bind('127.0.0.1', 0);
    s.listen((req) async {
      if (req.uri.path == '/api/notes/push') {
        final body = jsonDecode(await utf8.decoder.bind(req).join())
            as Map<String, dynamic>;
        final ids = (body['notes'] as List).map((n) => n['id']);
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'accepted': ids.length,
          'missing_images': ['aa00112233445566.png'],
        }));
      } else if (req.uri.path == '/api/notes/image') {
        final name = req.uri.queryParameters['name'];
        final buf = BytesBuilder();
        await for (final chunk in req) {
          buf.add(chunk);
        }
        uploaded[name!] = buf.takeBytes();
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'stored': name}));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    addTearDown(s.close);

    final api = ApiService(baseUrl: 'http://127.0.0.1:${s.port}');
    final r = await pushBackup(api: api, db: db, databasesDir: tmpDir.path);

    expect(r.pushed, 2); // 存活 + 墓碑
    expect(r.imagesUploaded, 1);
    expect(r.skippedImages, isEmpty);
    expect(uploaded['aa00112233445566.png'], imgBytes); // 字节与本地一致
    expect(await db.tombstonedNotes(), isEmpty); // 成功后墓碑清除
  });

  test('pullRestore：整体替换本地笔记 + 原子下载图片', () async {
    const pngName = 'bb00112233445566.png';
    final serverPng = Uint8List.fromList(utf8.encode('server-png'));
    final s = await HttpServer.bind('127.0.0.1', 0);
    s.listen((req) async {
      if (req.uri.path == '/api/notes/pull') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'exported_at': '2026-08-26T12:00:00',
          'notes': [
            {'id': 'p1', 'title': 'PC全局', 'content_md': '# hi',
             'question_id': null,
             'created_at': '2026-08-26T09:00:00',
             'updated_at': '2026-08-26T10:00:00'},
            {'id': 'p2', 'title': '', 'content_md':
                '![](noteimg://$pngName)',
             'question_id': 77, 'created_at': '2026-08-26T09:30:00',
             'updated_at': '2026-08-26T10:30:00'},
          ],
          'images': [pngName],
        }));
      } else if (req.uri.path == '/static/note_images/$pngName') {
        req.response.add(serverPng);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    addTearDown(s.close);

    // 预置一条本地旧笔记（应被整体替换掉）
    await db.saveNote(id: 'old-local', title: '旧', contentMd: '');

    final api = ApiService(baseUrl: 'http://127.0.0.1:${s.port}');
    final r = await pullRestore(api: api, db: db, databasesDir: tmpDir.path);

    expect(r.restored, 2);
    expect(r.imagesDownloaded, 1);
    expect(r.failedImages, isEmpty);

    final notes = await db.allNotes(includeDeleted: true);
    expect(notes.map((n) => n.id), containsAll(['p1', 'p2']));
    expect(notes.map((n) => n.id), isNot(contains('old-local')));

    final saved = File(
        '${noteImagesDirPath(tmpDir.path)}${Platform.pathSeparator}$pngName');
    expect(await saved.exists(), isTrue);
    expect(await saved.readAsBytes(), serverPng);
    expect(saved.path.endsWith('.tmp'), isFalse); // 无半成品残留
  });

  test('pushBackup：本地缺引用图时跳过并上报 skippedImages', () async {
    await db.saveNote(
        id: 'ghost', title: '', contentMd: '![](noteimg://cc00112233445566.png)');
    final s = await HttpServer.bind('127.0.0.1', 0);
    s.listen((req) async {
      if (req.uri.path == '/api/notes/push') {
        await utf8.decoder.bind(req).join();
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'accepted': 1,
          'missing_images': ['cc00112233445566.png'],
        }));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    addTearDown(s.close);

    final api = ApiService(baseUrl: 'http://127.0.0.1:${s.port}');
    final r = await pushBackup(api: api, db: db, databasesDir: tmpDir.path);
    expect(r.pushed, 1);
    expect(r.imagesUploaded, 0);
    expect(r.skippedImages, ['cc00112233445566.png']);
  });

  test('pushBackup 离线：ApiException 上抛不静默', () async {
    final dead = await HttpServer.bind('127.0.0.1', 0);
    final port = dead.port;
    await dead.close();
    final api = ApiService(baseUrl: 'http://127.0.0.1:$port');
    expect(
        () => pushBackup(api: api, db: db, databasesDir: tmpDir.path),
        throwsA(isA<ApiException>()));
  });
}
