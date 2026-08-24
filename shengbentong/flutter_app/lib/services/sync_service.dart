/// SyncService — 全量下载 → 解析 → 事务写入 → 版本/时间戳落盘。
/// 阶段回调供UI展示"正在下载… / 正在写入…"，失败抛 ApiException。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_service.dart';
import 'db_service.dart';

/// 全量同步结果
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

/// 进度上报结果
class UploadResult {
  final int pushed;      // 服务端新收条数
  final int duplicates;  // 服务端去重条数
  final int remaining;   // 本地队列剩余

  const UploadResult(
      {required this.pushed, required this.duplicates, required this.remaining});
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

  /// T-105：把本地 sync_queue 批量上报到PC。
  /// 全部成功后清空队列；服务端按(question_id, answered_at)幂等去重，重复推无副作用。
  /// 离线/不可达时抛 ApiException，由调用方决定提示方式。
  Future<UploadResult> uploadPending() async {
    final rows = await db.pendingQueueRows();
    if (rows.isEmpty) {
      return const UploadResult(pushed: 0, duplicates: 0, remaining: 0);
    }
    final records = <Map<String, Object?>>[
      for (final r in rows)
        Map<String, Object?>.from(
            jsonDecode(r['payload'] as String) as Map),
    ];
    final res = await api.pushProgress(records);
    await db.clearQueueRows([for (final r in rows) r['id'] as int]);
    final remaining = (await db.pendingQueueRows()).length;
    return UploadResult(
        pushed: res['accepted'] as int? ?? 0,
        duplicates: res['duplicate_ignored'] as int? ?? 0,
        remaining: remaining);
  }

  /// 上次全量同步时间（仅读本地偏好，无需网络）
  static Future<String?> lastSyncTime() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(ApiConfig.lastSyncKey);
  }
}
