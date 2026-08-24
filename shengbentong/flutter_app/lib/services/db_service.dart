/// DbService — sqflite 本地库 CRUD。所有页面只读本地 DB（T-104 约定）。
library;

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

const dbName = 'upmark.db';

/// 进度/队列表建表语句（onCreate 与老库升级共用）
List<String> get progressTableSqls => [
      '''
  CREATE TABLE IF NOT EXISTS local_progress(
    question_id INTEGER PRIMARY KEY,
    is_correct INTEGER NOT NULL DEFAULT 0,
    answered_at TEXT,
    in_wrong_book INTEGER NOT NULL DEFAULT 0,
    in_favorites INTEGER NOT NULL DEFAULT 0,
    sync_status TEXT NOT NULL DEFAULT 'pending')
''',
      '''
  CREATE TABLE IF NOT EXISTS sync_queue(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id INTEGER NOT NULL,
    action TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at TEXT)
''',
    ];

class SubjectStat {
  final Subject subject;
  final int chapters;
  final int questions;
  SubjectStat({required this.subject, required this.chapters, required this.questions});
}

class DbService {
  final Database db;

  /// 测试隔离钩子：设置后 open() 使用该文件名
  static String? fileNameOverride;

  /// 最近一次打开的实例（测试断言用）
  static DbService? lastOpened;

  /// 测试专用：清空路径级缓存（配合 deleteDatabase 实现完全隔离）
  static void resetInstanceCache() {
    _cache.clear();
    lastOpened = null;
  }

  /// 路径级实例缓存：同一路径永远复用同一连接，
  /// 避免sqflite工厂"一处close全局关闭"的坑
  static final Map<String, DbService> _cache = {};

  DbService._(this.db);

  static Future<DbService> open([String? fileName]) async {
    final name = fileName ?? fileNameOverride ?? dbName;
    final cached = _cache[name];
    if (cached != null && cached.db.isOpen) {
      return cached;
    }
    _cache.remove(name);
    final dir = await getDefaultDatabasesDirectory();
    final db = await openDatabase(p.join(dir, name), version: 1,
        onCreate: (d, v) async {
      await d.execute('''
        CREATE TABLE subjects(
          id INTEGER PRIMARY KEY, name TEXT NOT NULL)
      ''');
      await d.execute('''
        CREATE TABLE chapters(
          id INTEGER PRIMARY KEY,
          subject_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          order_num INTEGER NOT NULL,
          knowledge_md TEXT)
      ''');
      await d.execute('''
        CREATE TABLE questions(
          id INTEGER PRIMARY KEY,
          chapter_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          number INTEGER NOT NULL DEFAULT 0,
          global_seq INTEGER NOT NULL DEFAULT 0,
          material TEXT,
          stem TEXT NOT NULL,
          options TEXT,
          answer TEXT NOT NULL,
          accepts TEXT,
          explanation TEXT NOT NULL DEFAULT '',
          source_line INTEGER)
      ''');
      await d.execute(
          'CREATE INDEX idx_questions_chapter ON questions(chapter_id)');
      for (final sql in progressTableSqls) {
        await d.execute(sql);
      }
    });
    final svc = DbService._(db);
    _cache[name] = svc;
    svc._mark();
    return svc;
  }

  void _mark() => DbService.lastOpened = this;

  /// 全量替换 subjects/chapters/questions 三表；进度表(local_progress)不动。
  Future<void> replaceAll(SyncPayload payload) async {
    final batch = db.batch();
    batch.delete('questions');
    batch.delete('chapters');
    batch.delete('subjects');

    for (final s in payload.subjects) {
      batch.insert('subjects', {'id': s.id, 'name': s.name});
      for (final c in s.chapters) {
        batch.insert('chapters', {
          'id': c.id,
          'subject_id': s.id,
          'title': c.title,
          'order_num': c.orderNum,
          'knowledge_md': c.knowledgeMd,
        });
        for (var i = 0; i < c.questions.length; i++) {
          final q = c.questions[i];
          batch.insert('questions', {
            'id': q.id,
            'chapter_id': c.id,
            'type': q.type,
            'number': q.number,
            'global_seq': q.globalSeq == 0 ? i + 1 : q.globalSeq,
            'material': q.material,
            'stem': q.stem,
            'options':
                q.options.isEmpty ? null : jsonEncode(q.options),
            'answer': q.answer,
            'accepts':
                q.accepts == null ? null : jsonEncode(q.accepts),
            'explanation': q.explanation,
            'source_line': null,
          });
        }
      }
    }
    await batch.commit(noResult: true);
  }

  Future<List<SubjectStat>> subjectsWithStats() async {
    final rows = await db.rawQuery('''
      SELECT s.id AS sid, s.name AS name,
             COUNT(DISTINCT c.id) AS ch_cnt,
             COUNT(q.id) AS q_cnt
      FROM subjects s
      LEFT JOIN chapters c ON c.subject_id = s.id
      LEFT JOIN questions q ON q.chapter_id = c.id
      GROUP BY s.id, s.name
      ORDER BY s.name
    ''');
    return [
      for (final r in rows)
        SubjectStat(
          subject: Subject(id: r['sid'] as int, name: r['name'] as String),
          chapters: (r['ch_cnt'] as int?) ?? 0,
          questions: (r['q_cnt'] as int?) ?? 0,
        ),
    ];
  }

  Future<List<Chapter>> chaptersOf(int subjectId) async {
    final rows = await db.query('chapters',
        where: 'subject_id = ?', whereArgs: [subjectId], orderBy: 'order_num ASC');
    return rows.map(Chapter.fromRow).toList();
  }

  Future<int> questionCountOf(int chapterId) async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM questions WHERE chapter_id = ?',
        [chapterId]);
    return (r.first['n'] as int?) ?? 0;
  }

  /// T-104 将按此签名读取题目（约定勿改）
  Future<List<Map<String, Object?>>> rawQuestionsOf(int chapterId) =>
      db.query('questions',
          where: 'chapter_id = ?',
          whereArgs: [chapterId],
          orderBy: 'global_seq ASC');

  Future<String?> knowledgeOf(int chapterId) async {
    final rows = await db.query('chapters',
        columns: ['knowledge_md'],
        where: 'id = ?',
        whereArgs: [chapterId],
        limit: 1);
    return rows.isEmpty ? null : rows.first['knowledge_md'] as String?;
  }

  /// T-104：答题后写入进度与上传队列（幂等：同题保留最新）
  Future<void> saveProgress({
    required int questionId,
    required bool isCorrect,
    bool inWrongBook = false,
    bool inFavorites = false,
  }) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('local_progress', {
      'question_id': questionId,
      'is_correct': isCorrect ? 1 : 0,
      'answered_at': now,
      'in_wrong_book': (inWrongBook || !isCorrect) ? 1 : 0,
      'in_favorites': inFavorites ? 1 : 0,
      'sync_status': 'pending',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('sync_queue', {
      'question_id': questionId,
      'action': 'answer',
      'payload': jsonEncode({
        'question_id': questionId,
        'is_correct': isCorrect,
        'answered_at': now,
        'in_wrong_book': inWrongBook || !isCorrect,
        'in_favorites': inFavorites,
      }),
      'created_at': now,
    });
  }

  /// 某章已作答进度：qid -> 行（刷题页恢复状态用）
  Future<Map<int, Map<String, Object?>>> progressMapOf(
      List<int> questionIds) async {
    if (questionIds.isEmpty) return {};
    final ph = List.filled(questionIds.length, '?').join(',');
    final rows = await db.query('local_progress',
        where: 'question_id IN ($ph)', whereArgs: questionIds);
    return {for (final r in rows) r['question_id'] as int: r};
  }

  /// 测试/调试用：原始SQL透传
  Future<List<Map<String, Object?>>> rawQuery(String sql,
          [List<Object?>? args]) =>
      db.rawQuery(sql, args);

  Future<void> close() async {
    await db.close();
  }
}

/// sqflite 默认工厂在纯 Dart 测试中不可用，测试侧用 sqflite_common_ffi 注入。
Future<String> getDefaultDatabasesDirectory() async =>
    (await getDatabasesPath());
