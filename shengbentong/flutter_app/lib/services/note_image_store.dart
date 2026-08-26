/// NoteImageStore — 笔记图片本地存储（v2.2/T-122）。
///
/// 图片不入库：32 位十六进制名 + 扩展名，存 `<databases>/upmark_note_images/`；
/// MD 内以私有协议 `noteimg://<name>` 引用（Joplin 资源模式同思路），
/// 渲染层把协议映射到本目录文件离线显示。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';

const noteImgExtAllowed = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];

/// noteimg:// 引用正则（与 PC 端孤儿回收扫描同一语法）
final noteimgRefRe = RegExp(r'noteimg://([^)\s]+)');

/// 从 Markdown 正文提取全部笔记图片引用名
Set<String> extractNoteImgRefs(String md) =>
    noteimgRefRe.allMatches(md).map((m) => m.group(1)!).toSet();

String noteImagesDirPath(String databasesDir) =>
    p.join(databasesDir, 'upmark_note_images');

Future<Directory> ensureNoteImagesDir(String databasesDir) async {
  final d = Directory(noteImagesDirPath(databasesDir));
  if (!await d.exists()) {
    await d.create(recursive: true);
  }
  return d;
}

/// 把选中的图片拷入笔记图库，返回 noteimg:// 引用名（32位hex加扩展名）。
/// 格式不在白名单时抛 ArgumentError（调用方提示用户）。
Future<String> importNoteImage(String databasesDir, String sourcePath) async {
  final ext = p.extension(sourcePath).toLowerCase();
  if (!noteImgExtAllowed.contains(ext)) {
    throw ArgumentError('仅支持 png/jpg/jpeg/gif/webp 图片: $sourcePath');
  }
  final name = '${newNoteHexId()}$ext';
  final dir = await ensureNoteImagesDir(databasesDir);
  await File(sourcePath).copy(p.join(dir.path, name));
  return name;
}

/// noteimg:// 引用名 → 本地绝对路径；缺失返回空串（渲染层降级为占位）
Future<String> resolveNoteImagePath(String databasesDir, String name) async {
  if (name.isEmpty) return '';
  final safe = p.basename(name); // 防路径穿越
  final f = File(p.join(noteImagesDirPath(databasesDir), safe));
  return await f.exists() ? f.path : '';
}

/// 批量解析一篇笔记的全部引用 → {引用名: 本地绝对路径}（缺失项不含）
Future<Map<String, String>> resolveNoteImageMap(
    String databasesDir, String contentMd) async {
  final map = <String, String>{};
  for (final ref in extractNoteImgRefs(contentMd)) {
    final path = await resolveNoteImagePath(databasesDir, ref);
    if (path.isNotEmpty) map[ref] = path;
  }
  return map;
}

/// 删除不再被任何存活笔记引用的本地图片（删笔记/改图后调用；失败忽略不阻断）
Future<void> cleanupOrphanNoteImages(
    String databasesDir, Set<String> liveRefs) async {
  final dir = noteImagesDirPath(databasesDir);
  if (!await Directory(dir).exists()) return;
  await for (final f in Directory(dir).list()) {
    if (f is File && !liveRefs.contains(p.basename(f.path))) {
      try {
        await f.delete();
      } catch (_) {/* 文件占用等场景忽略 */}
    }
  }
}
