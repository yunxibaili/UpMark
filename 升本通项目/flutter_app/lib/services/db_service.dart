/// DbService — sqflite 本地库 CRUD。所有页面只读本地 DB（T-104 约定）。
library;

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

const dbName = 'upmark.db';

class SubjectStat {
  final Subject subject;
  final int chapters;
  final int questions;
  SubjectStat({required this.subject, required this.chapters, required this.questions});
}

class DbService {
  final Database db;

  DbService._(this.db);

  static Future<DbService> open() async {
    final dir = await getDefaultDatabasesDirectory();
    final db = await openDatabase(p.join(dir, dbName), version: 1,
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
    });
    return DbService._(db);
  }

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

  Future<void> close() => db.close();
}

/// sqflite 默认工厂在纯 Dart 测试中不可用，测试侧用 sqflite_common_ffi 注入。
Future<String> getDefaultDatabasesDirectory() async =>
    (await getDatabasesPath());
