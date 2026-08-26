/// LAN 扫描 —— /24 网段并发探测升本通服务端（T-119）。
/// 零依赖：dart:io 原生 NetworkInterface + HttpClient。
/// probe 可注入，便于单元测试（不真实发网络请求）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 探测单台主机是否为升本通服务端
typedef HealthProbe = Future<bool> Function(String host, String port);

/// 默认探测：GET /api/health 响应包含 shengbentong 即命中
Future<bool> defaultProbe(String host, String port) async {
  HttpClient? client;
  try {
    client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 400);
    final req = await client
        .openUrl('GET', Uri.parse('http://$host:$port/api/health'))
        .timeout(const Duration(milliseconds: 900));
    final resp = await req.close().timeout(const Duration(milliseconds: 900));
    final body = await resp.transform(utf8.decoder).join();
    return body.contains('shengbentong');
  } catch (_) {
    return false;
  } finally {
    client?.close(force: true);
  }
}

/// 本机 IPv4 列表（排除回环 127.* 与链路本地 169.254.*）
Future<List<String>> localIPv4s() async {
  final interfaces = await NetworkInterface.list();
  final out = <String>[];
  for (final itf in interfaces) {
    for (final addr in itf.addresses) {
      if (addr.type == InternetAddressType.IPv4 &&
          !addr.address.startsWith('127.') &&
          !addr.address.startsWith('169.254.')) {
        out.add(addr.address);
      }
    }
  }
  return out;
}

/// 由本机 IPv4 推断 /24 网段基址（如 192.168.1.124 → 192.168.1.）
String subnetOf(String ip) {
  final parts = ip.split('.');
  return '${parts[0]}.${parts[1]}.${parts[2]}.';
}

/// 扫描网段基址列表（如 ['192.168.1.']）的 1~254 主机，返回命中的服务端 IP。
/// [subnets] 为空时自动取本机网段；[probe] 可注入；[onProgress] 汇报进度。
Future<List<String>> scanLanForServer({
  List<String> subnets = const [],
  String port = '8000',
  HealthProbe probe = defaultProbe,
  int concurrency = 40,
  void Function(int done, int total)? onProgress,
}) async {
  final bases =
      subnets.isNotEmpty ? subnets : (await localIPv4s()).map(subnetOf).toList();
  final hosts = <String>[
    for (final b in bases) for (var i = 1; i <= 254; i++) '$b$i'
  ];
  final hits = <String>[];
  for (var i = 0; i < hosts.length; i += concurrency) {
    final batch = hosts.skip(i).take(concurrency).toList();
    final results = await Future.wait(
        [for (final h in batch) probe(h, port)]);
    for (var j = 0; j < batch.length; j++) {
      if (results[j]) hits.add(batch[j]);
    }
    onProgress?.call((i + batch.length).clamp(0, hosts.length), hosts.length);
  }
  return hits;
}
