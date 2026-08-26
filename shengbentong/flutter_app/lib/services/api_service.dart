/// ApiService — Dio 封装。baseUrl 从 SharedPreferences 读取。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const portKey = 'server_port';
  static const ipKey = 'server_ip';
  static const dataVersionKey = 'data_version';
  static const lastSyncKey = 'last_sync_at';

  final String baseUrl;

  ApiConfig({required this.baseUrl});

  static Future<ApiConfig> load() async {
    final sp = await SharedPreferences.getInstance();
    final ip = sp.getString(ipKey);
    final port = sp.getInt(portKey) ?? 8000;
    if (ip == null || ip.isEmpty) {
      throw StateError('未绑定服务器');
    }
    return ApiConfig(baseUrl: 'http://$ip:$port');
  }

  static Future<void> save(String ip, int port) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(ipKey, ip);
    await sp.setInt(portKey, port);
  }

  static Future<bool> hasBinding() async {
    final sp = await SharedPreferences.getInstance();
    final ip = sp.getString(ipKey);
    return ip != null && ip.isNotEmpty;
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

String mapDioError(Object e) {
  if (e is DioException) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout => '连接超时：请确认PC服务端已启动',
      DioExceptionType.receiveTimeout => '响应超时：数据量过大或网络不稳定',
      DioExceptionType.connectionError => '无法连接：IP/端口错误或PC服务端未运行',
      _ => e.message ?? '网络异常',
    };
  }
  return e.toString();
}

class ApiService {
  final Dio _dio;

  ApiService({required String baseUrl,
      Duration? connectTimeout,
      Duration? receiveTimeout})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: connectTimeout ?? const Duration(seconds: 5),
          receiveTimeout: receiveTimeout ?? const Duration(seconds: 120),
          headers: {'Accept-Encoding': 'gzip'},
        ));

  /// 绑定探测：可达返回统计，不可达抛 ApiException(带具体原因)
  Future<Map<String, dynamic>> bind() async {
    try {
      final r = await _dio.post('/api/bind');
      return Map<String, dynamic>.from(r.data as Map);
    } catch (e) {
      throw ApiException(mapDioError(e));
    }
  }

  Future<Map<String, dynamic>> fetchAll() async {
    try {
      final r = await _dio.get('/api/sync/all');
      return Map<String, dynamic>.from(r.data as Map);
    } catch (e) {
      throw ApiException(mapDioError(e));
    }
  }

  Future<Map<String, dynamic>> health() async {
    try {
      final r = await _dio.get('/api/health');
      return Map<String, dynamic>.from(r.data as Map);
    } catch (e) {
      throw ApiException(mapDioError(e));
    }
  }

  Future<Map<String, dynamic>> pushProgress(
      List<Map<String, Object?>> records) async {
    try {
      final r = await _dio.post('/api/sync/progress',
          data: {'records': records});
      return Map<String, dynamic>.from(r.data as Map);
    } catch (e) {
      throw ApiException(mapDioError(e));
    }
  }

  /// v2.1: 下载题目图像到本地缓存（同步阶段调用，保证离线可渲染）。
  /// T-112: 原子写入——先下 .tmp 再改名，杀进程/断网不会留下半张图。
  Future<void> downloadTo(String urlPath, String savePath) async {
    final tmp = '$savePath.tmp';
    await _dio.download(urlPath, tmp);
    final tmpFile = File(tmp);
    if (!await tmpFile.exists()) {
      throw StateError('下载未产生文件: $urlPath');
    }
    final target = File(savePath);
    if (await target.exists()) await target.delete();
    await tmpFile.rename(savePath);
  }

  /// T-118: 删除PC端指定科目（级联删章/题/答题记录+孤儿图）。失败抛 ApiException。
  Future<void> deleteSubject(int subjectId) async {
    try {
      await _dio.delete('/api/admin/subject/$subjectId');
    } catch (e) {
      throw ApiException(mapDioError(e));
    }
  }

  // ------------------------------------------------- 笔记备份（v2.2/T-122）

  /// 全量推送笔记（含墓碑）。返回 {accepted, missing_images}；失败抛 ApiException。
  Future<Map<String, dynamic>> pushNotes(
      List<Map<String, Object?>> notes) async {
    try {
      final r = await _dio.post('/api/notes/push', data: {'notes': notes});
      return Map<String, dynamic>.from(r.data as Map);
    } catch (e) {
      throw ApiException(mapDioError(e));
    }
  }

  /// 全量拉取笔记（换机恢复）。返回 {exported_at, notes, images}。
  Future<Map<String, dynamic>> pullNotes() async {
    try {
      final r = await _dio.get('/api/notes/pull');
      return Map<String, dynamic>.from(r.data as Map);
    } catch (e) {
      throw ApiException(mapDioError(e));
    }
  }

  /// 上传单张笔记图：原始字节流 octet-stream（零 multipart 依赖）。
  Future<Map<String, dynamic>> uploadNoteImage(
      String name, Uint8List bytes) async {
    try {
      final r = await _dio.post('/api/notes/image',
          data: bytes,
          queryParameters: {'name': name},
          options: Options(headers: {
            Headers.contentLengthHeader: bytes.length,
            Headers.contentTypeHeader: 'application/octet-stream',
          }));
      return Map<String, dynamic>.from(r.data as Map);
    } catch (e) {
      throw ApiException(mapDioError(e));
    }
  }
}

Future<ApiService> createApiFromPrefs() async {
  final cfg = await ApiConfig.load();
  return ApiService(baseUrl: cfg.baseUrl);
}

/// 是否已保存过绑定信息（决定首屏路由）
Future<bool> hasBindingSaved() async => ApiConfig.hasBinding();

SharedPreferences? _spInstance;
Future<SharedPreferences> prefs() async =>
    _spInstance ??= await SharedPreferences.getInstance();

Future<String?> readDataVersion() async =>
    (await prefs()).getString(ApiConfig.dataVersionKey);

Future<void> writeDataVersion(String v) async =>
    (await prefs()).setString(ApiConfig.dataVersionKey, v);
