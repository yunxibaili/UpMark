/// NotesBackupService — 笔记备份全链路（v2.2/T-125）。
///
/// 方向与题库相反：App 是唯一创作源，PC 仅作镜像仓库。
/// - [pushBackup]：全量推送笔记（含墓碑）→ 按 missing_images 补传本地图片 →
///   成功后清除本地墓碑。幂等由 PC 端 updated_at 新者胜保证，重复推无副作用。
/// - [pullRestore]：拉取 PC 全量笔记并整体替换本地（换机恢复）→ 原子下载全部
///   笔记图片到本地目录。单图失败不阻断恢复（缺图占位渲染）。
library;

import 'dart:io';

import '../models/models.dart';
import 'api_service.dart';
import 'db_service.dart';
import 'note_image_store.dart';

class NotesPushResult {
  final int pushed;
  final int imagesUploaded;
  final List<String> skippedImages;
  NotesPushResult(
      {required this.pushed,
      required this.imagesUploaded,
      required this.skippedImages});
}

class NotesPullResult {
  final int restored;
  final int imagesDownloaded;
  final List<String> failedImages;
  NotesPullResult(
      {required this.restored,
      required this.imagesDownloaded,
      required this.failedImages});
}

/// 全量备份：推送笔记 + 补传缺失图片 + 清墓碑
Future<NotesPushResult> pushBackup({
  required ApiService api,
  required DbService db,
  required String databasesDir,
}) async {
  final payload = await db.notesPushPayload();
  final r = await api.pushNotes(payload);
  final accepted = (r['accepted'] as num?)?.toInt() ?? 0;
  final missing =
      ((r['missing_images'] as List?) ?? const []).map((e) => e.toString());

  var uploaded = 0;
  final skipped = <String>[];
  for (final name in missing) {
    final f = File('${noteImagesDirPath(databasesDir)}${Platform.pathSeparator}${Uri.decodeComponent(name.split('/').last)}');
    if (!await f.exists()) {
      skipped.add(name);
      continue;
    }
    await api.uploadNoteImage(name, await f.readAsBytes());
    uploaded++;
  }
  await db.purgeTombstones();
  return NotesPushResult(
      pushed: accepted, imagesUploaded: uploaded, skippedImages: skipped);
}

/// 从PC恢复：整体替换本地笔记 + 原子下载图片（单图失败不阻断）
Future<NotesPullResult> pullRestore({
  required ApiService api,
  required DbService db,
  required String databasesDir,
}) async {
  final r = await api.pullNotes();
  final notes = ((r['notes'] as List?) ?? const [])
      .map((j) => Note.fromPullJson(j as Map<String, dynamic>))
      .toList();
  await db.replaceAllNotes(notes);

  await ensureNoteImagesDir(databasesDir);
  var downloaded = 0;
  final failed = <String>[];
  for (final name in ((r['images'] as List?) ?? const [])) {
    final imgName = name.toString().split('/').last;
    final savePath =
        '${noteImagesDirPath(databasesDir)}${Platform.pathSeparator}$imgName';
    try {
      await api.downloadTo('/static/note_images/$imgName', savePath);
      downloaded++;
    } on ApiException {
      failed.add(imgName);
    }
  }
  return NotesPullResult(
      restored: notes.length,
      imagesDownloaded: downloaded,
      failedImages: failed);
}
