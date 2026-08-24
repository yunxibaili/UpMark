"""升本通 MD 解析器 — 数据模型
对应《MD格式规范v2.0》第十节 JSON Schema。
"""
from __future__ import annotations

from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Optional, List


class QType(str, Enum):
    SINGLE = "single_choice"
    MULTIPLE = "multiple_choice"
    JUDGE = "judgment"
    BLANK = "fill_blank"


# 分区白名单：清洗注记后的精确名/前缀名 → 题型；None 表示上下文推断区
SECTION_TYPE_MAP = {
    "单选题": QType.SINGLE,
    "选择题": QType.SINGLE,
    "单项选择题": QType.SINGLE,
    "多选题": QType.MULTIPLE,
    "多项选择题": QType.MULTIPLE,
    "判断题": QType.JUDGE,
    "判断正误题": QType.JUDGE,
    "判断正误": QType.JUDGE,
    "填空题": QType.BLANK,
    "填空": QType.BLANK,
    "补充练习题": None,          # 上下文区：逐题按自身特征推断题型
}


@dataclass
class Question:
    raw_number: Optional[int]           # 文件内原始题号（可能断档）
    global_seq: int                     # 重排后的连续序号(1-based)
    qtype: QType
    style: str                          # "A"/"B"/"C"
    difficulty: Optional[int]           # ★数量1~3，无则None
    material: Optional[str]             # 【材料】块原文，无则None
    stem: str
    options: List[str]                  # 纯内容数组，字母按下标隐含(A=0)
    answer: str                         # single:"B" multiple:"ABD" judge:"T"/"F" blank:原文本
    accepts: List[List[str]]            # blank专用：每空的可接受答案列表
    explanation: str                    # 允许空串(W312)
    source_line: int

    def to_dict(self) -> dict:
        d = asdict(self)
        d["qtype"] = self.qtype.value
        return d


@dataclass
class SkippedItem:                      # 被跳过的题目（W3xx）
    line: int
    code: str
    reason: str
    stem_preview: str = ""


@dataclass
class SkippedSection:                   # 被整区跳过的分区（W205）
    header: str
    start_line: int
    end_line: int
    code: str = "W205"


@dataclass
class WarningItem:
    line: int
    code: str
    msg: str


@dataclass
class ChapterInfo:
    number: Optional[int]               # 中文/阿拉伯章号 → int；试卷等无章号为None
    title: str


@dataclass
class ParseResult:
    ok: bool
    chapter: Optional[ChapterInfo]
    questions: List[Question] = field(default_factory=list)
    skipped_questions: List[SkippedItem] = field(default_factory=list)
    skipped_sections: List[SkippedSection] = field(default_factory=list)
    warnings: List[WarningItem] = field(default_factory=list)
    rejected: Optional[dict] = None     # ok=False时: {"code","line","msg"}

    @property
    def stats(self) -> dict:
        by_type: dict = {}
        for q in self.questions:
            by_type[q.qtype.value] = by_type.get(q.qtype.value, 0) + 1
        return {
            "imported": len(self.questions),
            "by_type": by_type,
            "questions_skipped": len(self.skipped_questions),
            "sections_skipped": len(self.skipped_sections),
            "warnings": len(self.warnings),
        }


class FileRejected(Exception):
    """文件级致命错误 E100/E122/E130"""

    def __init__(self, code: str, line: int, msg: str):
        super().__init__(f"[{code}] line {line}: {msg}")
        self.code = code
        self.line = line
        self.msg = msg

    def to_result(self) -> ParseResult:
        return ParseResult(ok=False, chapter=None,
                           rejected={"code": self.code, "line": self.line, "msg": self.msg})
