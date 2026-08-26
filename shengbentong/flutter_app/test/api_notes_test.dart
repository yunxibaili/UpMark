/// T-122 笔记备份网络层测试：本地 HttpServer 实测 push/pull/image 三端点
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:shengbentong/services/api_service.dart';

void main() {
  group('ApiService 笔记端点（本地HttpServer实测）', () {
    test('pushNotes 发送 {notes:[...]] 并解析 accepted/missing_images', () async {
      Map<String, dynamic>? captured;
      final s = await HttpServer.bind('127.0.0.1', 0);
      s.listen((req) async {
        if (req.uri.path == '/api/notes/push' && req.method == 'POST') {
          final body = await utf8.decoder.bind(req).join();
          captured = jsonDecode(body) as Map<String, dynamic>;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(
              {'accepted': 2, 'missing_images': ['abc00112233445566.png']}));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      addTearDown(s.close);

      final api = ApiService(baseUrl: 'http://127.0.0.1:${s.port}');
      final r = await api.pushNotes([
        {'id': 'n1', 'title': 't', 'content_md': '', 'question_id': null,
         'deleted': false, 'created_at': '2026-08-26T10:00:00',
         'updated_at': '2026-08-26T10:00:00'},
      ]);
      expect(r['accepted'], 2);
      expect((r['missing_images'] as List).single, 'abc00112233445566.png');
      final notes = captured!['notes'] as List;
      expect(notes.single['id'], 'n1');
    });

    test('pullNotes GET 并解析 notes/images/exported_at', () async {
      final s = await HttpServer.bind('127.0.0.1', 0);
      s.listen((req) async {
        if (req.uri.path == '/api/notes/pull' && req.method == 'GET') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'exported_at': '2026-08-26T11:00:00',
            'notes': [
              {'id': 'p1', 'title': '恢复', 'content_md': '# md',
               'question_id': 5, 'created_at': '2026-08-26T09:00:00',
               'updated_at': '2026-08-26T10:00:00'},
            ],
            'images': ['abc00112233445566.png'],
          }));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      addTearDown(s.close);

      final api = ApiService(baseUrl: 'http://127.0.0.1:${s.port}');
      final r = await api.pullNotes();
      expect(r['exported_at'], '2026-08-26T11:00:00');
      expect((r['notes'] as List).single['title'], '恢复');
      expect((r['images'] as List).length, 1);
    });

    test('uploadNoteImage 以 octet-stream 原始字节流发送到 /api/notes/image',
        () async {
      Uint8List? received;
      String? queryName;
      String? contentType;
      final s = await HttpServer.bind('127.0.0.1', 0);
      s.listen((req) async {
        if (req.uri.path == '/api/notes/image' && req.method == 'POST') {
          queryName = req.uri.queryParameters['name'];
          contentType = req.headers.contentType?.toString();
          final buf = BytesBuilder();
          await for (final chunk in req) {
            buf.add(chunk);
          }
          received = buf.takeBytes();
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'stored': queryName}));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      addTearDown(s.close);

      final api = ApiService(baseUrl: 'http://127.0.0.1:${s.port}');
      final bytes = Uint8List.fromList(utf8.encode('fake-png-bytes'));
      final r = await api.uploadNoteImage(
          'abc00112233445566.png', bytes);
      expect(r['stored'], 'abc00112233445566.png');
      expect(queryName, 'abc00112233445566.png');
      expect(contentType, contains('application/octet-stream'));
      expect(received, bytes);
    });

    test('pushNotes 服务端500 → 抛 ApiException', () async {
      final s = await HttpServer.bind('127.0.0.1', 0);
      s.listen((req) async {
        req.response.statusCode = 500;
        await req.response.close();
      });
      addTearDown(s.close);

      final api = ApiService(baseUrl: 'http://127.0.0.1:${s.port}');
      expect(() => api.pushNotes(const []),
          throwsA(isA<ApiException>()));
    });
  });
}
