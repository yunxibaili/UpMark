/// lan_scanner 单元测试：probe 注入，不真实发网络请求
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:shengbentong/services/lan_scanner.dart';

void main() {
  test('subnetOf: IPv4 推断 /24 基址', () {
    expect(subnetOf('192.168.1.124'), '192.168.1.');
    expect(subnetOf('10.0.0.7'), '10.0.0.');
  });

  test('scanLanForServer: 仅命中 probe 为真的主机', () async {
    final hits = await scanLanForServer(
        subnets: ['10.0.0.'],
        port: '8000',
        probe: (h, p) async => h == '10.0.0.7');
    expect(hits, ['10.0.0.7']);
  });

  test('scanLanForServer: 多命中保持网段顺序', () async {
    final hits = await scanLanForServer(
        subnets: ['192.168.1.'],
        probe: (h, p) async => h.endsWith('.5') || h.endsWith('.2'));
    expect(hits, ['192.168.1.2', '192.168.1.5']);
  });

  test('scanLanForServer: 全部未命中返回空', () async {
    final hits = await scanLanForServer(
        subnets: ['10.9.9.'], probe: (h, p) async => false);
    expect(hits, isEmpty);
  });

  test('scanLanForServer: onProgress 汇报到 254', () async {
    var lastDone = 0, lastTotal = 0;
    await scanLanForServer(
        subnets: ['10.1.1.'],
        probe: (h, p) async => false,
        onProgress: (d, t) {
          lastDone = d;
          lastTotal = t;
        });
    expect(lastDone, 254);
    expect(lastTotal, 254);
  });
}
