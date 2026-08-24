/// ApiService 网络层测试：绑定成功 / 服务端错误 / 连接拒绝 / 超时
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shengbentong/services/api_service.dart';

void main() {
  group('ApiService（本地HttpServer实测）', () {
  

    test('绑定成功：/api/bind 返回 bound', () async {
      final s = await HttpServer.bind('127.0.0.1', 0);
      s.listen((req) async {
        if (req.uri.path == '/api/bind') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(
              {'status': 'bound', 'app': 'shengbentong', 'schema_version': 1}));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      addTearDown(s.close);

      final api = ApiService(baseUrl: 'http://127.0.0.1:${s.port}');
      final r = await api.bind();
      expect(r['status'], 'bound');
    });

    test('服务端500 → 抛ApiException而非静默', () async {
      final s = await HttpServer.bind('127.0.0.1', 0);
      s.listen((req) async {
        req.response.statusCode = 500;
        await req.response.close();
      });
      addTearDown(s.close);

      final api = ApiService(baseUrl: 'http://127.0.0.1:${s.port}');
      expect(() => api.bind(), throwsA(isA<ApiException>()));
    });

    test('连接拒绝（端口未监听）→ 错误信息含"无法连接"', () async {
      // 绑定后立刻关闭，确保该端口无人监听
      final s = await HttpServer.bind('127.0.0.1', 0);
      final deadPort = s.port;
      await s.close();

      final api = ApiService(baseUrl: 'http://127.0.0.1:$deadPort');
      try {
        await api.bind();
        fail('应当抛出 ApiException');
      } on ApiException catch (e) {
        expect(e.message, contains('无法连接'));
      }
    });

    test('响应超时 → 错误信息含"响应超时"', () async {
      final s = await HttpServer.bind('127.0.0.1', 0);
      s.listen((req) async {
        await Future.delayed(const Duration(milliseconds: 800));
        req.response.statusCode = 200;
        req.response.write('{}');
        await req.response.close();
      });
      addTearDown(s.close);

      final api = ApiService(baseUrl: 'http://127.0.0.1:${s.port}',
          receiveTimeout: const Duration(milliseconds: 150));
      await expectLater(api.bind(), throwsA(isA<ApiException>()));
    });
  });
}
