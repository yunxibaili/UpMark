"""升本通 MD 解析器 — 自研行扫描状态机
依据《MD格式规范v2.0》实现。白名单制：每一行要么成功解析，
要么命中预定义的 E(致命)/W(跳过或警告) 规则码 —— 绝不猜测，绝不静默丢弃。
"""
from __future__ import annotations

import os
import re
from typing import List, Optional, Tuple

from .models import (
    QType, Question, SkippedItem, SkippedSection, WarningItem,
    ChapterInfo, ParseResult, FileRejected, SECTION_TYPE_MAP,
)

# ---------------------------------------------------------------- 正则库
RE_H1 = re.compile(r"^#(?!#)\s*(.*)$")
RE_H2_SECTION = re.compile(r"^##(?!#)\s*(.*)$")
RE_H3_Q = re.compile(r"^###\s+(\d{1,3})[\.．]\s*(.*)$")            # 样式B
RE_Q_A = re.compile(r"^(\d{1,3})[\.．]\s*(.*)$")                    # 样式A（允许空题干→W303）
RE_HR = re.compile(r"^\s*(?:-{3,}|\*{3,})\s*$")                      # 水平分隔线，静默忽略
RE_Q_C = re.compile(
    r"^\*\*题目\s*(\d{1,3})\s*\*\*\s*(?:\[\s*难度\s*[:：]\s*([★☆]{1,3})\s*\])?\s*$"
)                                                                    # 样式C
RE_Q_D = re.compile(r"^\*\*(\d{1,3})[\.．]\s*(.+?)\*\*\s*$")          # 样式D：加粗题号
RE_INLINE_A = re.compile(r"(?:^|\s)A[\.．]\s*")                       # 行内选项起点（题干与A.同行）
RE_OPTION = re.compile(r"^\s{0,8}([A-D])[\.．]\s*(.+)$")
OPT_SPLIT = re.compile(r"[　\s]{2,}(?=[B-D][\.．])")                 # 单行多选项
RE_SEG_OPT = re.compile(r"^([B-D])[\.．]\s*(.*)$")
RE_ANS_B_VAL = re.compile(r"^\*\*【答案】\s*([^*]+?)\s*\*\*\s*$")     # **【答案】B**
RE_ANS_B_EMPTY = re.compile(r"^\*\*【答案】\*\*\s*(.*)$")             # **【答案】** 值/换行续
RE_ANS_PLAIN = re.compile(r"^【答案】\s*(.*)$")                        # 非加粗(样式C区)
RE_EXPL_B = re.compile(r"^\*\*【讲解】\*\*\s*(.*)$")
RE_EXPL_PLAIN = re.compile(r"^【讲解】\s*(.*)$")
RE_MATERIAL = re.compile(r"^\*{0,2}\s*【材料】\s*\*{0,2}\s*$")
RE_FENCE_OPEN = re.compile(r"^\s{0,3}(```+|~~~+)\s*(\w*)\s*$")
RE_FENCE_CLOSE = re.compile(r"^\s{0,3}(```+|~~~+)\s*$")
RE_BLANKS = re.compile(r"_{3,}")
RE_SEC_SEQ = re.compile(r"^([一二三四五六七八九十]{1,3})、\s*(.*)$")
RE_CHAPTER = re.compile(r"^第\s*([0-9]{1,3}|[一两二三四五六七八九十]{1,3})\s*章\s*(.*)$")
RE_SUFFIX = re.compile(r"\s*(练习题|知识点总结)\s*$")
RE_HTML_COMMENT = re.compile(r"^<!--.*?-->\s*$")
RE_SUBJECT = re.compile(r"^<!--\s*subject\s*[:：]\s*(.+?)\s*-->\s*$")

CN_NUM = {"一": 1, "两": 2, "二": 2, "三": 3, "四": 4, "五": 5,
          "六": 6, "七": 7, "八": 8, "九": 9, "十": 10}

JUDGE_MAP = {"√": "T", "×": "F"}


def _cn2int(s: str) -> Optional[int]:
    s = s.strip()
    if s.isdigit():
        return int(s)
    if "十" in s:
        a, _, b = s.partition("十")
        tens = CN_NUM.get(a, 1) if a else 1
        ones = CN_NUM.get(b, 0) if b else 0
        return tens * 10 + ones
    return CN_NUM.get(s)


def _strip_notes(name: str) -> str:
    """去掉尾部注记括号：（每题2分…）（新增）等"""
    prev = None
    while prev != name:
        prev = name
        name = re.sub(r"[（(][^（）()]*[)）]\s*$", "", name).strip()
    return name


def _resolve_section_type(name: str) -> Tuple[Optional[QType], bool, Optional[str]]:
    """返回 (题型|None, 是否上下文区, 跳过原因)。跳过原因非None表示W205整区跳过。"""
    if name in SECTION_TYPE_MAP:
        t = SECTION_TYPE_MAP[name]
        return t, (t is None), None
    for k in sorted(SECTION_TYPE_MAP, key=len, reverse=True):
        if name.startswith(k):
            t = SECTION_TYPE_MAP[k]
            return t, (t is None), None
    return None, False, f"不支持的分区类型「{name}」"


def load_source(data: bytes) -> str:
    """G1: UTF-8 无 BOM。违规抛 E100。"""
    if data.startswith(b"\xef\xbb\xbf"):
        raise FileRejected("E100", 1, "检测到 UTF-8 BOM 头，请另存为无BOM的UTF-8")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as e:
        raise FileRejected("E100", 1, f"文件不是合法UTF-8编码: {e}") from e


class _Q:
    """正在组装的一道题"""

    def __init__(self, raw_number: int, style: str, difficulty: Optional[int],
                 material: Optional[str], line: int):
        self.raw_number = raw_number
        self.style = style
        self.difficulty = difficulty
        self.material = material
        self.line = line
        self.stem_parts: List[str] = [""]
        self.option_pairs: List[Tuple[str, str]] = []
        self.answer_raws: List[str] = []
        self.has_answer = False
        self.answer_pending = False       # **【答案】** 后换行续体
        self.expl_started = False
        self.expl_parts: List[str] = []

    @property
    def stem(self) -> str:
        return "\n".join(p for p in self.stem_parts).strip()


class StrictMDParser:
    """练习题文件解析器。用法:
        result = StrictMDParser().parse_exercises(text, source_name="xx.md")
    """

    def parse_exercises(self, text: str, source_name: str = "",
                        fallback_title: str = "",
                        fallback_subject: str | None = None) -> ParseResult:
        self.src = source_name
        self.subject_declared: Optional[str] = None
        self.warnings: List[WarningItem] = []
        self.skipped_qs: List[SkippedItem] = []
        self.skipped_secs: List[SkippedSection] = []
        self.imported: List[Question] = []
        self.chapter: Optional[ChapterInfo] = None
        try:
            self._run(text, fallback_title)
        except FileRejected as e:
            return e.to_result()
        return ParseResult(
            ok=True, chapter=self.chapter,
            subject=self.subject_declared or fallback_subject or None,
            questions=self.imported,
            skipped_questions=self.skipped_qs, skipped_sections=self.skipped_secs,
            warnings=self.warnings)

    # ------------------------------------------------------------ 主循环
    def _run(self, text: str, fallback_title: str) -> None:
        lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")

        state = "PREAMBLE"                # PREAMBLE/CHAPTER/SECTION/QUESTION/SKIP_SECTION
        h1_count = 0
        in_code = False
        code_buf: List[str] = []
        code_route: str = "stem"          # stem/option_last/expl/material/discarded

        sec_seq_last: Optional[int] = None
        cur_sec_line = 0
        cur_qtype: Optional[QType] = None
        cur_is_context = False
        cur_styles: set = set()
        cur_plain_warned = False
        expected_next = 1
        open_skip_sec: Optional[SkippedSection] = None

        cur_q: Optional[_Q] = None
        expected_opt = "B"                # 多行拆分时的下一个选项字母
        material_buf: Optional[List[str]] = None
        material_current: Optional[str] = None
        prev_blank = True

        def warn(line: int, code: str, msg: str) -> None:
            self.warnings.append(WarningItem(line, code, msg))

        def skip_q(q: _Q, code: str, reason: str) -> None:
            preview = q.stem.replace("\n", " ")[:40]
            self.skipped_qs.append(SkippedItem(q.line, code, reason, preview))

        def close_skip_section(end_line: int) -> None:
            nonlocal open_skip_sec
            if open_skip_sec is not None:
                open_skip_sec.end_line = max(end_line, open_skip_sec.start_line)
                self.skipped_secs.append(open_skip_sec)
                open_skip_sec = None

        def flush_material() -> None:
            nonlocal material_buf, material_current
            if material_buf is not None:
                material_current = "\n".join(material_buf).strip() or None
                material_buf = None

        def finalize_question() -> None:
            nonlocal cur_q, expected_next
            if cur_q is None:
                return
            q = cur_q
            cur_q = None
            self._finalize_one(q, cur_qtype if not cur_is_context else None,
                               cur_is_context, warn, skip_q)
            cur_styles.add(q.style)

        for lineno, raw in enumerate(lines, 1):
            line = raw.rstrip()

            # ---------- 围栏（全局最高优先级, G7） ----------
            if in_code:
                if RE_FENCE_CLOSE.match(line):
                    in_code = False
                    block = "\n".join([fence_head] + code_buf + ["```"])
                    if code_route == "material" and material_buf is not None:
                        material_buf.append(block)
                    elif cur_q is not None:
                        if code_route == "expl":
                            cur_q.expl_parts.append(block)
                        elif code_route == "option_last" and cur_q.option_pairs:
                            l, c = cur_q.option_pairs[-1]
                            cur_q.option_pairs[-1] = (l, c + "\n" + block)
                        else:
                            cur_q.stem_parts.append(block)
                    # discarded: 跳过分区内不落地
                else:
                    code_buf.append(raw.rstrip("\n"))
                prev_blank = not line.strip()
                continue
            m_open = RE_FENCE_OPEN.match(line)
            if m_open:
                in_code = True
                code_buf = []
                ticks, lang = m_open.group(1), m_open.group(2) or ""
                fence_head = ticks + lang          # 保留原始语言标记
                if material_buf is not None:
                    code_route = "material"
                elif cur_q is None:
                    code_route = "discarded"
                elif cur_q.expl_started:
                    code_route = "expl"
                elif cur_q.has_answer:
                    code_route = "expl"
                elif cur_q.option_pairs:
                    code_route = "option_last"
                else:
                    code_route = "stem"
                prev_blank = not line.strip()
                continue

            stripped = line.strip()

            # ---------- 水平分隔线（规范6.6：静默忽略，不算游离文本） ----------
            if RE_HR.match(line):
                prev_blank = True
                continue

            # ---------- PREAMBLE ----------
            if state == "PREAMBLE":
                if not stripped:
                    prev_blank = True
                    continue
                if RE_HTML_COMMENT.match(stripped):
                    ms = RE_SUBJECT.match(stripped)
                    if ms:
                        self.subject_declared = ms.group(1).strip()
                    continue
                m_h1 = RE_H1.match(line)
                if m_h1 and m_h1.group(1).strip():
                    h1_count += 1
                    self._set_chapter(m_h1.group(1).strip(), fallback_title)
                    state = "CHAPTER"
                    prev_blank = True
                    continue
                warn(lineno, "W314", f"已忽略标题前的游离文本：「{stripped[:30]}」")
                continue

            # ---------- 跳过分区 ----------
            if state == "SKIP_SECTION":
                if RE_H2_SECTION.match(line):
                    pass   # 落到下方通用分区头处理（负责关闭跳过区）
                else:
                    prev_blank = not stripped
                    continue

            # ---------- 分区头（通用入口） ----------
            m_h2 = RE_H2_SECTION.match(line)
            if m_h2:
                finalize_question()
                flush_material()
                close_skip_section(lineno - 1)
                material_current = None           # 新分区重置材料
                header_txt = m_h2.group(1).strip()
                m_seq = RE_SEC_SEQ.match(header_txt)
                seq_val: Optional[int] = None
                if m_seq:
                    seq_val = _cn2int(m_seq.group(1))
                    type_src = m_seq.group(2)
                else:
                    warn(lineno, "W316", f"分区头缺少中文序号：「## {header_txt[:20]}」")
                    type_src = header_txt
                if seq_val is not None and (
                        (sec_seq_last is None and seq_val != 1)
                        or (sec_seq_last is not None and seq_val <= sec_seq_last)):
                    warn(lineno, "W316",
                         f"分区序号异常（当前{seq_val}，期望递增），按出现顺序继续处理")
                if seq_val is not None:
                    sec_seq_last = seq_val
                clean_name = _strip_notes(type_src)
                qtype, is_ctx, skip_reason = _resolve_section_type(clean_name)
                cur_sec_line = lineno
                cur_qtype = qtype
                cur_is_context = is_ctx
                cur_styles = set()
                cur_plain_warned = False
                expected_next = 1
                if skip_reason is not None:
                    open_skip_sec = SkippedSection(header_txt, lineno, lineno)
                    state = "SKIP_SECTION"
                else:
                    state = "SECTION"
                prev_blank = True
                continue

            if state == "SKIP_SECTION":      # 吞行
                prev_blank = not stripped
                continue

            # ---------- 材料块标记 ----------
            if RE_MATERIAL.match(stripped):
                finalize_question()
                flush_material()
                material_buf = []
                prev_blank = True
                continue
            if material_buf is not None:      # 收集材料，遇 分区/新材料/题目起始 即终止
                terminate = bool(RE_H2_SECTION.match(line)) \
                    or bool(RE_MATERIAL.match(stripped))
                if not terminate and cur_q is None:
                    probe = self._match_question_start(
                        line, stripped, None, cur_qtype, cur_is_context,
                        expected_next, None, prev_blank)
                    terminate = probe is not None
                if terminate:
                    flush_material()          # 落穿到下方对应处理器
                else:
                    material_buf.append(line)
                    prev_blank = not stripped
                    continue

            # ---------- 额外 H1 ----------
            m_h1 = RE_H1.match(line)
            if m_h1:
                txt = m_h1.group(1).strip()
                if txt and h1_count < 2 and state == "CHAPTER" and cur_q is None:
                    h1_count += 1              # 试卷封面第二行
                    self._set_chapter(txt, fallback_title, append=True)
                elif txt:
                    warn(lineno, "W314", f"已忽略多余H1：「{txt[:30]}」")
                prev_blank = True
                continue

            # ---------- 题干起始判定（唯一决策点） ----------
            qs = self._match_question_start(line, stripped, cur_q, cur_qtype,
                                             cur_is_context, expected_next,
                                             material_current, prev_blank)
            if qs is not None and cur_q is not None and qs[1] == "A":
                # 样式A歧义闸（统一规则）：编号必须大于当前题号；
                # 是否真是新题由【前瞻验证】裁决——下一实质行呈结构性证据
                # （选项/答案/讲解/材料/分区/分隔线/其他题干）⇒ 新题；纯散文 ⇒ 讲解列表项。
                if qs[0] <= cur_q.raw_number or \
                        not self._lookahead_says_question(lines, lineno):
                    qs = None
            if qs is not None:
                n, style, diff, stem0 = qs
                finalize_question()
                if cur_styles and style not in cur_styles:
                    warn(lineno, "W311", f"分区内混用题目样式（现出现样式{style}），均已兼容解析")
                if n != expected_next:
                    warn(lineno, "W310",
                         f"题号 {n} 与期望 {expected_next} 不符（跳号/重复/乱序），已自动重排")
                expected_next = n + 1
                cur_q = _Q(n, style, diff, material_current, lineno)
                if stem0:
                    cur_q.stem_parts = [stem0]
                    self._try_split_inline(cur_q)   # 题干与选项同行（真题卷式）
                state = "QUESTION"
                prev_blank = not stripped
                continue

            # ---------- QUESTION 内部各行 ----------
            if cur_q is not None:
                q = cur_q

                ans_m = (RE_ANS_B_VAL.match(stripped) or RE_ANS_B_EMPTY.match(stripped)
                         or ((not stripped.startswith("**")) and RE_ANS_PLAIN.match(stripped)))
                if ans_m:
                    val = ans_m.group(1).strip()
                    if isinstance(ans_m.string, str) and ans_m.re is RE_ANS_PLAIN \
                            and not cur_plain_warned and cur_q.style != "C":
                        warn(lineno, "W318", "非加粗【答案】行出现在加粗样式区，已接受")
                        cur_plain_warned = True
                    if val:
                        q.answer_raws.append(val)
                        q.has_answer = True
                        q.answer_pending = False
                    else:
                        q.has_answer = True
                        q.answer_pending = True     # 值在后续行
                    prev_blank = not stripped
                    continue

                expl_m = RE_EXPL_B.match(stripped) or \
                         ((not stripped.startswith("**")) and RE_EXPL_PLAIN.match(stripped))
                if expl_m:
                    val = expl_m.group(1).strip()
                    q.expl_started = True
                    if val:
                        q.expl_parts.append(val)
                    if expl_m.re is RE_EXPL_PLAIN and not cur_plain_warned \
                            and cur_q.style != "C":
                        warn(lineno, "W318", "非加粗【讲解】行出现在加粗样式区，已接受")
                        cur_plain_warned = True
                    prev_blank = not stripped
                    continue

                opt_m = RE_OPTION.match(line)
                if opt_m and not q.expl_started and not q.has_answer:
                    letter, content = opt_m.group(1), opt_m.group(2).strip()
                    segs = OPT_SPLIT.split(content)
                    if len(segs) > 1:
                        cur_letter = letter
                        pairs = [(cur_letter, segs[0].strip())]
                        ok_chain = True
                        for seg in segs[1:]:
                            sm = RE_SEG_OPT.match(seg.strip())
                            exp_letter = chr(ord(pairs[-1][0]) + 1)
                            if sm and sm.group(1) == exp_letter:
                                pairs.append((sm.group(1), sm.group(2).strip()))
                            else:
                                ok_chain = False
                                break
                        if ok_chain:
                            q.option_pairs.extend(pairs)
                            expected_opt = chr(ord(pairs[-1][0]) + 1)
                            prev_blank = not stripped
                            continue
                    q.option_pairs.append((letter, content))
                    expected_opt = chr(ord(letter) + 1)
                    prev_blank = not stripped
                    continue

                # 续行路由（answer_pending 最优先：跨行答案体）
                if not stripped:
                    prev_blank = True
                    continue
                if q.answer_pending:
                    q.answer_raws.append(stripped)
                elif q.expl_started or q.has_answer:
                    q.expl_parts.append(line)
                elif line[:1] in (" ", "\t") and q.option_pairs:
                    l, c = q.option_pairs[-1]
                    q.option_pairs[-1] = (l, (c + " " + stripped).strip())
                else:
                    q.stem_parts.append(stripped)
                prev_blank = False
                continue

            # 游离文本（章节头之后、任何题目之前）
            if stripped:
                warn(lineno, "W314", f"已忽略游离文本：「{stripped[:30]}」")
            prev_blank = not stripped

        # ---------- EOF ----------
        if in_code:
            raise FileRejected("E122", len(lines),
                               "代码块围栏未闭合（文件结束仍有打开的```）")
        finalize_question()
        flush_material()
        close_skip_section(len(lines))

        if not self.imported:
            raise FileRejected("E130", len(lines),
                               "解析完成但没有任何可入库的客观题（可能全为主观题或格式全部无效）")

    # ------------------------------------------------------------ 辅助
    def _set_chapter(self, raw_title: str, fallback: str, append: bool = False) -> None:
        if append and self.chapter is not None:
            self.chapter.title = f"{self.chapter.title} {raw_title}".strip()
            return
        t = raw_title.strip()
        num: Optional[int] = None
        m = RE_CHAPTER.match(t)
        if m:
            num = _cn2int(m.group(1))
            t = m.group(2).strip()
        t = RE_SUFFIX.sub("", t).strip()
        if not t:
            t = (fallback or "未命名章节").strip()
        self.chapter = ChapterInfo(num, t)

    def _match_question_start(self, line: str, stripped: str,
                              cur_q: Optional[_Q], qtype: Optional[QType],
                              is_ctx: bool, expected_next: int,
                              material_current: Optional[str], prev_blank: bool):
        """唯一的新题判定入口。返回 (编号, 样式, 难度, 初始题干) 或 None。

        防歧义闸（仅样式A且已有题在身时生效，用于区分"讲解里的编号列表"）：
            已见答案 且 编号>当前题号 且（编号恰为当前+1 或 前一行为空行）
        样式B/C/D格式本身无歧义，直接判定为新题。
        """
        if not stripped:
            return None
        m = RE_H3_Q.match(line)
        if m:
            return int(m.group(1)), "B", None, m.group(2).strip()
        m = RE_Q_C.match(stripped)
        if m:
            stars = m.group(2)
            diff = min(len(stars), 3) if stars else None
            return int(m.group(1)), "C", diff, ""
        m = RE_Q_D.match(stripped)
        if m:
            return int(m.group(1)), "D", None, m.group(2).strip()
        m = RE_Q_A.match(line)
        if m:
            n = int(m.group(1))
            if cur_q is None:
                return n, "A", None, m.group(2).strip()
            if n > cur_q.raw_number:
                return n, "A", None, m.group(2).strip()   # 由外层前瞻闸最终裁决
            return None
        return None

    def _try_split_inline(self, q: _Q) -> None:
        """确定性拆分"题干 A. x　　B. y..."同行写法（真题卷常见）。
        仅当字母链A→B→C→D完整时才拆分；否则保持原样交给下游规则处理。"""
        if q.option_pairs or not q.stem_parts:
            return
        text = q.stem_parts[0]
        m = RE_INLINE_A.search(text)
        if not m:
            return
        head = text[:m.start()].strip()
        rest = text[m.end():].strip()
        if not rest:
            return
        pairs = [("A", rest)]
        expected = "B"
        pos = 0
        while True:
            sm = re.compile(r"(?:^|[　\s]{2,})([B-D])[\.．]\s*").search(rest, pos)
            if not sm or sm.group(1) != expected:
                break
            start = sm.end()
            nxt = re.compile(r"[　\s]{2,}(?=[C-D][\.．])").search(rest, start)
            seg_end = nxt.start() if nxt else len(rest)
            pairs.append((sm.group(1), rest[start:seg_end].strip()))
            expected = chr(ord(expected) + 1)
            pos = seg_end
            if expected > "D":
                break
        if [p[0] for p in pairs] == ["A", "B", "C", "D"]:
            q.stem_parts = [head] if head else [""]
            q.option_pairs = pairs

    def _lookahead_says_question(self, lines: List[str], idx_one_based: int) -> bool:
        """从候选行向后找结构性证据（选项/答案/讲解/材料/分区/分隔线/围栏/其他题干）。
        遇到代码块时跳过其内部内容继续扫描（代码块本身即新题的强证据）。"""
        in_code = False
        for j in range(idx_one_based, len(lines)):      # lines[j] 为第 j+1 行
            if j == idx_one_based - 1:
                continue                                 # 跳过候选行自身
            raw_j = lines[j]
            t = raw_j.strip()
            if not t:
                continue
            if in_code:
                if RE_FENCE_CLOSE.match(raw_j):
                    in_code = False
                    return True                          # 围栏正常闭合=结构证据
                continue
            if RE_FENCE_OPEN.match(raw_j):
                in_code = True
                continue
            return bool(
                RE_OPTION.match(raw_j) or RE_ANS_B_VAL.match(t)
                or RE_ANS_B_EMPTY.match(t) or RE_ANS_PLAIN.match(t)
                or RE_EXPL_B.match(t) or RE_EXPL_PLAIN.match(t)
                or RE_MATERIAL.match(t) or RE_H2_SECTION.match(raw_j)
                or RE_HR.match(raw_j)
                or RE_H3_Q.match(raw_j) or RE_Q_C.match(t)
                or RE_Q_D.match(t)
                or (self._qa_plain_match(t) is not None))
        return True                                       # 到文件尾视为新题

    @staticmethod
    def _qa_plain_match(t: str):
        m = RE_Q_A.match(t)
        return m

    def _finalize_one(self, q: _Q, fixed_type: Optional[QType],
                      is_ctx: bool, warn, skip_q) -> None:
        raw = q.answer_raws[0].strip() if q.answer_raws else ""

        # ---- 上下文区推断题型 ----
        if fixed_type is None:
            if raw in JUDGE_MAP:
                fixed_type = QType.JUDGE
            elif RE_BLANKS.search(q.stem):
                fixed_type = QType.BLANK
            elif len(q.option_pairs) >= 2:
                letters = "".join(l for l, _ in q.option_pairs)
                fixed_type = QType.MULTIPLE if len(raw) >= 2 and raw != "" and all(
                    c in "ABCD" for c in raw.upper()) else QType.SINGLE
                _ = letters
            else:
                skip_q(q, "W321", "无法识别为客观题型（疑似主观题：无选项且无√×答案且无填空位）")
                return

        # ---- 公共：缺答案 ----
        if not q.has_answer or not raw:
            skip_q(q, "W302", "缺少【答案】行")
            return
        if len(set(q.answer_raws)) > 1:
            skip_q(q, "W307", f"存在多个互相矛盾的答案行: {q.answer_raws}")
            return

        # ---- 空题干 ----
        stem = q.stem
        # 完形填空形态例外：存在【材料】时允许空题干（App按"第N空"呈现）
        if not stem and q.material is None:
            skip_q(q, "W303", "题干为空")
            return

        letters = [l for l, _ in q.option_pairs]
        contents = [c for _, c in q.option_pairs]

        # ---- 分类型校验 ----
        answer: str
        accepts: List[List[str]] = []

        if not q.expl_started:
            warn(q.line, "W312", "缺少【讲解】行，已保留该题并将讲解置空")

        if fixed_type == QType.JUDGE:
            if contents:
                skip_q(q, "W306", "判断题出现了选项行")
                return
            v = JUDGE_MAP.get(raw)
            if v is None:
                skip_q(q, "W302", f"判断题答案必须是√或×，实际:「{raw[:10]}」")
                return
            answer = v

        elif fixed_type == QType.BLANK:
            if contents:
                skip_q(q, "W306", "填空题出现了选项行")
                return
            blanks = RE_BLANKS.findall(stem)
            for b in set(blanks):
                if len(b) != 6:
                    warn(q.line, "W313",
                         f"空位使用{len(b)}个下划线（标准为6个______），已按空位识别")
                    break
            if not blanks:
                skip_q(q, "W304", "填空题题干中没有______空位标记")
                return
            segs = [s.strip() for s in raw.split("｜")]
            if len(segs) != len(blanks) and len(blanks) >= 2:
                # 兼容规则(确定性)：旧版语料多空答案用 顿号/中文逗号/半角逗号/全角分号 分隔，
                # 仅当拆分后段数恰好等于空位数时采用并告警；绝不猜测。
                # 注意：分号仅在多空(≥2)时作为分隔符参与，避免与单空的";备选"语义冲突。
                for sep in ("、", "，", ",", "；"):
                    alt = [s.strip() for s in raw.split(sep)]
                    if len(alt) == len(blanks) and all(alt):
                        segs = alt
                        warn(q.line, "W319",
                             f"多空答案使用非标准分隔符「{sep}」，已自动识别为{len(blanks)}空")
                        break
            if len(segs) != len(blanks):
                skip_q(q, "W320",
                       f"空位数({len(blanks)})与答案段数({len(segs)})不一致")
                return
            accepts = [[a.strip() for a in re.split("[;；]", seg) if a.strip()]
                       for seg in segs]
            if any(not alt for alt in accepts):
                skip_q(q, "W302", "存在空的答案段")
                return
            answer = raw.strip()

        else:  # SINGLE / MULTIPLE
            if len(letters) < 2:
                probe = raw.upper().replace(" ", "")
                if not probe or not all(c in "ABCD" for c in probe):
                    skip_q(q, "W321",
                           "疑似主观题混入客观分区（无选项且答案非选项字母）")
                else:
                    skip_q(q, "W301",
                           f"选择题可识别选项不足2个（实际{len(letters)}个）")
                return
            if len(set(letters)) != len(letters) or \
                    letters != [chr(65 + i) for i in range(len(letters))]:
                skip_q(q, "W305", f"选项字母不连续或重复: {''.join(letters)}")
                return
            if len(letters) != 4:
                skip_q(q, "W305", f"选择题选项数应为4，实际{len(letters)}个")
                return
            cand = raw.upper().replace(" ", "")
            if fixed_type == QType.SINGLE:
                if not re.fullmatch(r"[ABCD]", cand):
                    skip_q(q, "W302", f"单选题答案必须是单个A-D字母，实际:「{raw[:10]}」")
                    return
                answer = cand
            else:
                cs = sorted(set(cand))
                if not (2 <= len(cs) <= 4) or not all(c in "ABCD" for c in cs):
                    skip_q(q, "W302", f"多选题答案须为2~4个不同字母，实际:「{raw[:10]}」")
                    return
                answer = "".join(cs)

        self.imported.append(Question(
            raw_number=q.raw_number,
            global_seq=len(self.imported) + 1,
            qtype=fixed_type,
            style=q.style,
            difficulty=q.difficulty,
            material=q.material,
            stem=stem,
            options=contents,
            answer=answer,
            accepts=accepts,
            explanation="\n".join(q.expl_parts).strip(),
            source_line=q.line,
        ))

    # ------------------------------------------------------------ 知识点文件
    def parse_knowledge(self, text: str, source_name: str = "",
                        fallback_title: str = "",
                        fallback_subject: str | None = None) -> ParseResult:
        """K规则：不做结构强校验，仅提取H1章节信息，原文整体保留。"""
        self.src = source_name
        self.warnings = []
        subject_declared = None
        for line in text.split("\n")[:5]:                 # 仅扫描文件头部声明
            ms = RE_SUBJECT.match(line.strip())
            if ms:
                subject_declared = ms.group(1).strip()
                break
        lines = text.replace("\r\n", "\n").split("\n")
        in_code = False
        h1_count = 0
        chapter: Optional[ChapterInfo] = None
        for lineno, raw in enumerate(lines, 1):
            line = raw.rstrip()
            if RE_FENCE_OPEN.match(line) and not in_code:
                in_code = True
                continue
            if in_code:
                if RE_FENCE_CLOSE.match(line):
                    in_code = False
                continue
            m = RE_H1.match(line)
            if m and m.group(1).strip():
                h1_count += 1
                if chapter is None:
                    self._set_chapter(m.group(1).strip(), fallback_title)
                    chapter = self.chapter
                elif h1_count == 2 and chapter.title and "试题" not in chapter.title:
                    self._set_chapter(m.group(1).strip(), fallback_title, append=True)
                    chapter = self.chapter
        if chapter is None:
            title = (fallback or source_name or "未命名章节").strip()
            self.warnings.append(WarningItem(1, "W315", f"缺少H1标题，使用兜底名「{title}」"))
            chapter = ChapterInfo(None, title)
        return ParseResult(ok=True, chapter=chapter,
                           subject=subject_declared or fallback_subject or None,
                           warnings=self.warnings)


# ---------------------------------------------------------------- CLI 独立运行
if __name__ == "__main__":  # pragma: no cover
    import json
    import sys as _sys

    if len(_sys.argv) < 2:
        print("用法: python -m app.parser.strict_parser <文件.md> [--json]")
        _sys.exit(2)
    path = _sys.argv[1]
    as_json = "--json" in _sys.argv[2:]

    try:
        text = load_source(open(path, "rb").read())
    except FileRejected as e:
        payload = {"ok": False, "file": path, "rejected": e.__dict__}
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        _sys.exit(1)

    result = StrictMDParser().parse_exercises(text, os.path.basename(path))
    payload = {
        "ok": result.ok,
        "file": path,
        "subject": result.subject,
        "chapter": result.chapter.__dict__ if result.chapter else None,
        "stats": result.stats,
        "questions": [q.to_dict() for q in result.questions],
        "skipped_questions": [vars(s) for s in result.skipped_questions],
        "skipped_sections": [vars(s) for s in result.skipped_sections],
        "warnings": [vars(w) for w in result.warnings],
        "rejected": result.rejected,
    }
    if as_json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        ch = payload["chapter"]
        st = payload["stats"]
        print(f"章节: 第{ch['number']}章 {ch['title']}" if ch and ch["number"]
              else f"标题: {ch['title'] if ch else '-'}")
        print(f"入库: {st['imported']}  按题型: {st['by_type']}")
        print(f"跳题: {st['questions_skipped']}  跳分区: {st['sections_skipped']}"
              f"  警告: {st['warnings']}")
        for s in result.skipped_questions:
            print(f"  [{s.code}] L{s.line}: {s.reason} | {s.stem_preview}")
        for s in result.skipped_sections:
            print(f"  [{s.code}] L{s.start_line}-{s.end_line}: {s.header}")
        for w in result.warnings:
            print(f"  [{w.code}] L{w.line}: {w.msg}")
    _sys.exit(0 if result.ok else 1)
