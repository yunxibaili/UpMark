/// DbService — sqflite 本地库 CRUD。所有页面只读本地 DB（T-104 约定）。
library;

import 'dart:convert';

import 'dart:io';

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

/// v2.2/T-122: 笔记表（App 为唯一创作源，PC 仅作备份镜像）。
/// 一题一篇由部分唯一索引兜底；墓碑行 question_id 置空不占位。
List<String> get notesTableSqls => [
      '''
  CREATE TABLE IF NOT EXISTS notes(
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL DEFAULT '',
    content_md TEXT NOT NULL DEFAULT '',
    question_id INTEGER,
    deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT,
    updated_at TEXT)
''',
      '''
  CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_question
    ON notes(question_id) WHERE question_id IS NOT NULL AND deleted = 0
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
    final db = await openDatabase(p.join(dir, name), version: 3,
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
          image TEXT,
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
      for (final sql in notesTableSqls) {
        await d.execute(sql);
      }
    }, onUpgrade: (d, oldV, newV) async {
      if (oldV < 2) {
        // v2.1: questions 补 image 列
        await d.execute('ALTER TABLE questions ADD COLUMN image TEXT');
      }
      if (oldV < 3) {
        // v2.2/T-122: notes 表（仅新增，不动旧表）
        for (final sql in notesTableSqls) {
          await d.execute(sql);
        }
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
            'image': q.image,
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

  /// 按ID列表取完整题目（保持传入顺序；错题/收藏重练用）
  Future<List<Question>> questionsByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final ph = List.filled(ids.length, '?').join(',');
    final rows =
        await db.query('questions', where: 'id IN ($ph)', whereArgs: ids);
    final map = {for (final r in rows) r['id'] as int: Question.fromRow(r)};
    return [for (final id in ids) if (map[id] != null) map[id]!];
  }

  Future<String?> knowledgeOf(int chapterId) async {
    final rows = await db.query('chapters',
        columns: ['knowledge_md'],
        where: 'id = ?',
        whereArgs: [chapterId],
        limit: 1);
    return rows.isEmpty ? null : rows.first['knowledge_md'] as String?;
  }

  /// T-105：答题后写入进度与上传队列（幂等：同题保留最新）。
  /// [inFavorites] 传 null 表示"保持原收藏状态不变"。
  Future<void> saveProgress({
    required int questionId,
    required bool isCorrect,
    bool inWrongBook = false,
    bool? inFavorites,
  }) async {
    final now = DateTime.now().toIso8601String();
    var fav = inFavorites;
    if (fav == null) {
      final prev = await db.query('local_progress',
          columns: ['in_favorites'],
          where: 'question_id = ?',
          whereArgs: [questionId],
          limit: 1);
      fav = prev.isEmpty
          ? false
          : (prev.first['in_favorites'] as int? ?? 0) == 1;
    }
    await db.insert('local_progress', {
      'question_id': questionId,
      'is_correct': isCorrect ? 1 : 0,
      'answered_at': now,
      'in_wrong_book': (inWrongBook || !isCorrect) ? 1 : 0,
      'in_favorites': fav ? 1 : 0,
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
        'in_favorites': fav,
      }),
      'created_at': now,
    });
  }

  /// 收藏/取消收藏（保留已有答题状态；取消也入队，两端一致）
  Future<void> setFavorite(int questionId, bool fav) async {
    final now = DateTime.now().toIso8601String();
    final prev = await db.query('local_progress',
        where: 'question_id = ?', whereArgs: [questionId], limit: 1);
    if (prev.isEmpty) {
      await db.insert('local_progress', {
        'question_id': questionId,
        'is_correct': 0,
        'answered_at': now,
        'in_wrong_book': 0,
        'in_favorites': fav ? 1 : 0,
        'sync_status': 'pending',
      });
    } else {
      await db.update('local_progress', {'in_favorites': fav ? 1 : 0},
          where: 'question_id = ?', whereArgs: [questionId]);
    }
    await db.insert('sync_queue', {
      'question_id': questionId,
      'action': fav ? 'favorite_add' : 'favorite_remove',
      'payload': jsonEncode({
        'question_id': questionId,
        'is_correct': prev.isEmpty ? false : (prev.first['is_correct'] as int? ?? 0) == 1,
        'answered_at': now,
        'in_wrong_book':
            prev.isEmpty ? false : (prev.first['in_wrong_book'] as int? ?? 0) == 1,
        'in_favorites': fav,
      }),
      'created_at': now,
    });
  }

  /// 错题本移除（答对重练时由 saveProgress 自动移除；此处手动移除）
  Future<void> removeFromWrongBook(int questionId) =>
      _setFlag(questionId, 'in_wrong_book', false);

  Future<void> _setFlag(int questionId, String col, bool v) async {
    final r = await db.query('local_progress',
        where: 'question_id = ?', whereArgs: [questionId], limit: 1);
    if (r.isEmpty) return;
    await db.update('local_progress', {col: v ? 1 : 0},
        where: 'question_id = ?', whereArgs: [questionId]);
  }

  /// 错题列表：JOIN 题目+科目，按最近作答倒序
  Future<List<Map<String, Object?>>> wrongBookEntries() => db.rawQuery('''
    SELECT q.id AS qid, q.stem, q.type, p.answered_at, s.name AS subject
    FROM local_progress p
    JOIN questions q ON q.id = p.question_id
    JOIN chapters c ON c.id = q.chapter_id
    JOIN subjects s ON s.id = c.subject_id
    WHERE p.in_wrong_book = 1
    ORDER BY p.answered_at DESC
  ''');

  Future<List<int>> wrongQuestionIds() async {
    final rows = await db.query('local_progress',
        columns: ['question_id'],
        where: 'in_wrong_book = 1',
        orderBy: 'answered_at DESC');
    return [for (final r in rows) r['question_id'] as int];
  }

  /// 收藏列表：同上结构
  Future<List<Map<String, Object?>>> favoriteEntries() => db.rawQuery('''
    SELECT q.id AS qid, q.stem, q.type, s.name AS subject
    FROM local_progress p
    JOIN questions q ON q.id = p.question_id
    JOIN chapters c ON c.id = q.chapter_id
    JOIN subjects s ON s.id = c.subject_id
    WHERE p.in_favorites = 1
    ORDER BY p.answered_at DESC
  ''');

  Future<List<int>> favoriteQuestionIds() async {
    final rows = await db.query('local_progress',
        columns: ['question_id'],
        where: 'in_favorites = 1',
        orderBy: 'answered_at DESC');
    return [for (final r in rows) r['question_id'] as int];
  }

  /// 统计汇总（数字版）
  Future<Map<String, Object?>> statsSummary() async {
    final total = await db.rawQuery(
        'SELECT COUNT(*) AS n, SUM(is_correct) AS ok FROM local_progress');
    final answered = (total.first['n'] as int?) ?? 0;
    final correct = (total.first['ok'] as int?) ?? 0;
    final wrong = (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM local_progress WHERE in_wrong_book = 1'))
        .first['n'] as int? ?? 0;
    final favs = (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM local_progress WHERE in_favorites = 1'))
        .first['n'] as int? ?? 0;
    final pending = (await db.rawQuery('SELECT COUNT(*) AS n FROM sync_queue'))
        .first['n'] as int? ?? 0;
    return {
      'answered': answered,
      'correct': correct,
      'accuracy': answered == 0 ? null : correct / answered,
      'wrong_book': wrong,
      'favorites': favs,
      'pending_upload': pending,
    };
  }

  /// 分科目正确率
  Future<List<Map<String, Object?>>> accuracyBySubject() => db.rawQuery('''
    SELECT s.name AS subject,
           COUNT(*) AS answered,
           SUM(p.is_correct) AS correct
    FROM local_progress p
    JOIN questions q ON q.id = p.question_id
    JOIN chapters c ON c.id = q.chapter_id
    JOIN subjects s ON s.id = c.subject_id
    GROUP BY s.id, s.name
    ORDER BY answered DESC
  ''');

  /// 待上传队列行（含自增id与payload）
  Future<List<Map<String, Object?>>> pendingQueueRows() =>
      db.query('sync_queue', orderBy: 'id ASC');

  /// 上传成功后清除已推送的队列行（服务端按(qid,answered_at)幂等去重，重复推无副作用）
  Future<void> clearQueueRows(List<int> ids) async {
    if (ids.isEmpty) return;
    final ph = List.filled(ids.length, '?').join(',');
    await db.delete('sync_queue', where: 'id IN ($ph)', whereArgs: ids);
  }

  /// v2.1: 图像下载成功后，把 questions.image 从远端相对路径改写为本地绝对路径
  Future<void> rewriteQuestionImages(Map<String, String> remoteToLocal) async {
    if (remoteToLocal.isEmpty) return;
    final batch = db.batch();
    for (final e in remoteToLocal.entries) {
      batch.update('questions', {'image': e.value},
          where: 'image = ?', whereArgs: [e.key]);
    }
    await batch.commit(noResult: true);
  }

  /// v2.1: 下载失败的图像置空（题目仍可用，仅无图）
  Future<void> nullifyQuestionImages(Set<String> remotes) async {
    for (final r in remotes) {
      await db.update('questions', {'image': null},
          where: 'image = ?', whereArgs: [r]);
    }
  }

  // ---------------------------------------------------------- 笔记（v2.2/T-122）

  /// 全部笔记（updated_at 倒序；默认不含墓碑）
  Future<List<Note>> allNotes({bool includeDeleted = false}) async {
    final rows = await db.query('notes',
        where: includeDeleted ? null : 'deleted = 0',
        orderBy: 'updated_at DESC');
    return rows.map(Note.fromRow).toList();
  }

  /// 存活笔记数（主页入口角标）
  Future<int> liveNoteCount() async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM notes WHERE deleted = 0');
    return (r.first['n'] as int?) ?? 0;
  }

  Future<Note?> noteById(String id) async {
    final rows = await db.query('notes',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Note.fromRow(rows.first);
  }

  /// 题目笔记（一题一篇；无则 null）
  Future<Note?> noteOfQuestion(int questionId) async {
    final rows = await db.query('notes',
        where: 'question_id = ? AND deleted = 0',
        whereArgs: [questionId],
        limit: 1);
    return rows.isEmpty ? null : Note.fromRow(rows.first);
  }

  /// 新建或更新笔记（id 已存在即更新；created_at 保留首次值）。
  /// 违反一题一篇唯一索引时抛异常（UI 层捕获提示，不静默）。
  Future<String> saveNote({
    required String id,
    required String title,
    required String contentMd,
    int? questionId,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final prev = await db.query('notes',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (prev.isEmpty) {
      await db.insert('notes', {
        'id': id,
        'title': title,
        'content_md': contentMd,
        'question_id': questionId,
        'deleted': 0,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
    } else {
      await db.update('notes', {
        'title': title,
        'content_md': contentMd,
        'question_id': questionId,
        'deleted': 0,
        'updated_at': nowIso,
      }, where: 'id = ?', whereArgs: [id]);
    }
    return id;
  }

  /// 软删除为墓碑（清空 question_id 释放占位；推送成功后 purgeTombstones）
  Future<void> softDeleteNote(String id) async {
    await db.update('notes', {
      'deleted': 1,
      'question_id': null,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// 待推送墓碑
  Future<List<Note>> tombstonedNotes() async {
    final rows =
        await db.query('notes', where: 'deleted = 1', orderBy: 'updated_at DESC');
    return rows.map(Note.fromRow).toList();
  }

  /// 推送确认成功后物理清除全部墓碑
  Future<void> purgeTombstones() async {
    await db.delete('notes', where: 'deleted = 1');
  }

  /// pull 恢复：以 PC 为准整体替换 notes 表（仅收非墓碑行）。
  /// UI 必须先明确警示"本地笔记将被覆盖"再调用。
  Future<void> replaceAllNotes(List<Note> notes) async {
    final batch = db.batch();
    batch.delete('notes');
    for (final n in notes.where((n) => !n.deleted)) {
      batch.insert('notes', {
        'id': n.id,
        'title': n.title,
        'content_md': n.contentMd,
        'question_id': n.questionId,
        'deleted': 0,
        'created_at': n.createdAt.toIso8601String(),
        'updated_at': n.updatedAt.toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
  }

  /// 推送载荷：全量存活笔记 + 墓碑（个人规模全表推送，幂等由 PC 端保证）
  Future<List<Map<String, Object?>>> notesPushPayload() async {
    final live = (await allNotes(includeDeleted: true));
    return [for (final n in live) n.toPushJson()];
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
  /// T-118: 删除指定科目的全部本地数据（题/章/科目/进度/待传队列项）+ 孤儿图片文件。
  /// 返回删除的题目数。须在 PC 端删除成功后调用（服务器为唯一事实源）。
  Future<int> deleteSubjectData(int subjectId) async {
    final chapterRows =
        await db.query('chapters', where: 'subject_id = ?', whereArgs: [subjectId]);
    final cids = chapterRows.map((c) => c['id'] as int).toList();
    var qcount = 0;
    final remainingImages = <String>{};
    for (final cid in cids) {
      final rows = await db.query('questions',
          where: 'chapter_id = ?', whereArgs: [cid]);
      for (final r in rows) {
        qcount++;
        final qid = r['id'] as int;
        await db.delete('sync_queue', where: 'question_id = ?', whereArgs: [qid]);
        await db.delete('local_progress', where: 'question_id = ?', whereArgs: [qid]);
        final img = r['image'] as String?;
        if (img != null && img.isNotEmpty) {
          final still = await db.rawQuery(
              'SELECT COUNT(*) AS n FROM questions WHERE image = ? AND id != ?',
              [img, qid]);
          if (((still.first['n'] as int?) ?? 0) > 0) {
            remainingImages.add(img.split('/').last);
          }
        }
      }
      await db.delete('questions', where: 'chapter_id = ?', whereArgs: [cid]);
    }
    await db.delete('chapters', where: 'subject_id = ?', whereArgs: [subjectId]);
    await db.delete('subjects', where: 'id = ?', whereArgs: [subjectId]);
    final dir = p.join(await getDefaultDatabasesDirectory(), 'upmark_images');
    if (await Directory(dir).exists()) {
      await for (final f in Directory(dir).list()) {
        if (f is File && !remainingImages.contains(f.path.split('/').last)) {
          try {
            await f.delete();
          } catch (_) {/* 占用等忽略 */}
        }
      }
    }
    return qcount;
  }

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
