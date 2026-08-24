/// 数据模型 —— 与仓库根目录 api_contract_v1.json 严格对齐
library;

import 'dart:convert';

class Subject {
  final int id;
  final String name;

  Subject({required this.id, required this.name});

  factory Subject.fromRow(Map<String, Object?> row) =>
      Subject(id: row['id'] as int, name: row['name'] as String);

  Map<String, Object?> toRow() => {'id': id, 'name': name};
}

class Chapter {
  final int id;
  final int subjectId;
  final String title;
  final String? knowledgeMd;
  final int orderNum;

  Chapter({
    required this.id,
    required this.subjectId,
    required this.title,
    this.knowledgeMd,
    required this.orderNum,
  });

  factory Chapter.fromRow(Map<String, Object?> row) => Chapter(
        id: row['id'] as int,
        subjectId: row['subject_id'] as int,
        title: row['title'] as String,
        knowledgeMd: row['knowledge_md'] as String?,
        orderNum: row['order_num'] as int,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'subject_id': subjectId,
        'title': title,
        'knowledge_md': knowledgeMd,
        'order_num': orderNum,
      };
}

enum QuestionType { singleChoice, multipleChoice, judgment, fillBlank }

class Question {
  final int id;
  final int chapterId;
  final QuestionType type;
  final int number;
  final int globalSeq;
  final String? material;
  final String stem;
  final List<String> options;
  final String answer;
  final List<List<String>>? accepts;
  final String explanation;
  final int? sourceLine;

  Question({
    required this.id,
    required this.chapterId,
    required this.type,
    required this.number,
    required this.globalSeq,
    this.material,
    required this.stem,
    required this.options,
    required this.answer,
    this.accepts,
    required this.explanation,
    this.sourceLine,
  });

  factory Question.fromRow(Map<String, Object?> row) => Question(
        id: row['id'] as int,
        chapterId: row['chapter_id'] as int,
        type: typeFromApi(row['type'] as String),
        number: row['number'] as int,
        globalSeq: row['global_seq'] as int,
        material: row['material'] as String?,
        stem: (row['stem'] as String?) ?? '',
        options: _decodeList(row['options']),
        answer: (row['answer'] as String?) ?? '',
        accepts: _decodeAccepts(row['accepts']),
        explanation: (row['explanation'] as String?) ?? '',
        sourceLine: row['source_line'] as int?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'chapter_id': chapterId,
        'type': typeToApi(type),
        'number': number,
        'global_seq': globalSeq,
        'material': material,
        'stem': stem,
        'options': _encodeList(options),
        'answer': answer,
        'accepts': accepts == null ? null : _encodeAccepts(accepts!),
        'explanation': explanation,
        'source_line': sourceLine,
      };

  static String typeToApi(QuestionType t) => switch (t) {
        QuestionType.singleChoice => 'single_choice',
        QuestionType.multipleChoice => 'multiple_choice',
        QuestionType.judgment => 'judgment',
        QuestionType.fillBlank => 'fill_blank',
      };

  static QuestionType typeFromApi(String s) => switch (s) {
        'single_choice' => QuestionType.singleChoice,
        'multiple_choice' => QuestionType.multipleChoice,
        'judgment' => QuestionType.judgment,
        'fill_blank' => QuestionType.fillBlank,
        _ => throw FormatException('未知题型: $s'),
      };
}

String? _encodeList(List<String> list) =>
    list.isEmpty ? null : jsonEncode(list);

List<String> _decodeList(Object? raw) {
  if (raw == null) return const [];
  if (raw is List) return raw.map((e) => e.toString()).toList();
  return (jsonDecode(raw.toString()) as List)
      .map((e) => e.toString())
      .toList();
}

String? _encodeAccepts(List<List<String>> accepts) =>
    accepts.isEmpty ? null : jsonEncode(accepts);

List<List<String>>? _decodeAccepts(Object? raw) {
  if (raw == null) return null;
  final decoded = raw is List ? raw : (jsonDecode(raw.toString()) as List);
  return decoded
      .map((blank) =>
          (blank as List).map((a) => a.toString()).toList())
      .toList();
}

// ---------------------------------------------------------------- 同步载荷

class SyncQuestion {
  final int id;
  final String type;
  final int number;
  final int globalSeq;
  final String? material;
  final String stem;
  final List<String> options;
  final String answer;
  final List<List<String>>? accepts;
  final String explanation;

  SyncQuestion({
    required this.id,
    required this.type,
    required this.number,
    required this.globalSeq,
    this.material,
    required this.stem,
    required this.options,
    required this.answer,
    this.accepts,
    required this.explanation,
  });

  factory SyncQuestion.fromJson(Map<String, dynamic> j) => SyncQuestion(
        id: j['id'] as int,
        type: j['type'] as String,
        number: j['number'] as int? ?? 0,
        globalSeq: j['global_seq'] as int? ?? 0,
        material: j['material'] as String?,
        stem: j['stem'] as String? ?? '',
        options: (j['options'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        answer: j['answer'].toString(),
        accepts: (j['accepts'] as List?)
            ?.map((blank) =>
                (blank as List).map((a) => a.toString()).toList())
            .toList(),
        explanation: j['explanation'] as String? ?? '',
      );
}

class SyncChapter {
  final int id;
  final String title;
  final int orderNum;
  final String? knowledgeMd;
  final List<SyncQuestion> questions;

  SyncChapter({
    required this.id,
    required this.title,
    required this.orderNum,
    this.knowledgeMd,
    required this.questions,
  });

  factory SyncChapter.fromJson(Map<String, dynamic> j) => SyncChapter(
        id: j['id'] as int,
        title: j['title'] as String,
        orderNum: j['order_num'] as int? ?? 0,
        knowledgeMd: j['knowledge_md'] as String?,
        questions: (j['questions'] as List? ?? const [])
            .map((q) => SyncQuestion.fromJson(q as Map<String, dynamic>))
            .toList(),
      );
}

class SyncSubject {
  final int id;
  final String name;
  final List<SyncChapter> chapters;

  SyncSubject({required this.id, required this.name, required this.chapters});

  factory SyncSubject.fromJson(Map<String, dynamic> j) => SyncSubject(
        id: j['id'] as int,
        name: j['name'] as String,
        chapters: (j['chapters'] as List? ?? const [])
            .map((c) => SyncChapter.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class SyncPayload {
  final int schemaVersion;
  final String dataVersion;
  final String exportedAt;
  final List<SyncSubject> subjects;

  SyncPayload({
    required this.schemaVersion,
    required this.dataVersion,
    required this.exportedAt,
    required this.subjects,
  });

  factory SyncPayload.fromJson(Map<String, dynamic> j) => SyncPayload(
        schemaVersion: j['schema_version'] as int,
        dataVersion: j['data_version']?.toString() ?? '',
        exportedAt: j['exported_at'] as String? ?? '',
        subjects: (j['subjects'] as List? ?? const [])
            .map((s) => SyncSubject.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
