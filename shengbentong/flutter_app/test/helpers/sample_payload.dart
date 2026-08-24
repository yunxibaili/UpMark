/// 共享样例载荷（多个测试文件引用，保持单一来源）
library;

const Map<String, dynamic> sampleSync = {
  'schema_version': 1,
  'data_version': 'SAMPLE-V1',
  'exported_at': '2026-08-24T00:00:00',
  'subjects': [
    {
      'id': 1,
      'name': '样例科目A',
      'chapters': [
        {
          'id': 11,
          'title': '第1章 样例',
          'order_num': 1,
          'knowledge_md': '# 样例知识点\n| 列 | 表 |\n```c\nint x;\n```',
          'questions': [
            {
              'id': 101,
              'type': 'single_choice',
              'number': 1,
              'global_seq': 1,
              'material': null,
              'stem': '单选样例',
              'options': ['甲', '乙', '丙', '丁'],
              'answer': 'B',
              'accepts': null,
              'explanation': '因为'
            },
            {
              'id': 102,
              'type': 'judgment',
              'number': 2,
              'global_seq': 2,
              'material': null,
              'stem': '判断样例。',
              'options': [],
              'answer': 'F',
              'accepts': null,
              'explanation': ''
            },
            {
              'id': 103,
              'type': 'fill_blank',
              'number': 3,
              'global_seq': 3,
              'material': null,
              'stem': '填空：______',
              'options': [],
              'answer': '答案;备选',
              'accepts': [['答案', '备选']],
              'explanation': ''
            },
          ],
        },
        {
          'id': 12,
          'title': '第2章 材料题',
          'order_num': 2,
          'knowledge_md': null,
          'questions': [
            {
              'id': 111,
              'type': 'multiple_choice',
              'number': 1,
              'global_seq': 1,
              'material': 'Passage...',
              'stem': '',
              'options': ['o1', 'o2', 'o3', 'o4'],
              'answer': 'ABD',
              'accepts': null,
              'explanation': '多选材料题（完形空题干形态）'
            },
          ],
        },
      ],
    },
  ],
};
