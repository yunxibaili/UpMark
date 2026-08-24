/// SyncService — 全量下载 → 解析 → 事务写入 → 版本/时间戳落盘。
/// 阶段回调供UI展示"正在下载… / 正在写入…"，失败抛 ApiException。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_service.dart';
import 'db_service.dart';

class SyncResult {
  final int subjects;
  final int chapters;
  final int questions;
  final Duration elapsed;

  SyncResult({
    required this.subjects,
    required this.chapters,
    required this.questions,
    required this.elapsed,
  });
}

class SyncService {
  final ApiService api;
  final DbService db;

  SyncService({required this.api, required this.db});

  Future<SyncResult> run(void Function(String stage) onStage) async {
    final sw = Stopwatch()..start();

    onStage('正在连接PC并下载数据（gzip压缩传输）…');
    final raw = await api.fetchAll();

    onStage('正在解析同步载荷…');
    final payload = SyncPayload.fromJson(raw);

    if (payload.schemaVersion > 1) {
      throw ApiException('协议版本不兼容(${payload.schemaVersion})，请升级App');
    }

    onStage('正在写入本地数据库（${payload.subjects.length}个科目）…');
    await db.replaceAll(payload);

    final sp = await SharedPreferences.getInstance();
    await sp.setString(ApiConfig.dataVersionKey, payload.dataVersion);
    await sp.setString(
        ApiConfig.lastSyncKey, DateTime.now().toIso8601String());

    var chapterTotal = 0;
    var questionTotal = 0;
    for (final s in payload.subjects) {
      chapterTotal += s.chapters.length;
      for (final c in s.chapters) {
        questionTotal += c.questions.length;
      }
    }
    sw.stop();
    return SyncResult(
        subjects: payload.subjects.length,
        chapters: chapterTotal,
        questions: questionTotal,
        elapsed: sw.elapsed);
  }

  /// 对比服务器与本地 data_version；从未同步或版本不同 → true；离线返回 false（静默）
  Future<bool> hasUpdate() async {
    try {
      final all = await api.fetchAll();
      final remote = all['data_version']?.toString() ?? '';
      if (remote.isEmpty) return false;
      final sp = await SharedPreferences.getInstance();
      final local = sp.getString(ApiConfig.dataVersionKey);
      return local != remote;
    } on ApiException {
      return false;
    }
  }

  Future<String?> lastSyncTime() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(ApiConfig.lastSyncKey);
  }
}
