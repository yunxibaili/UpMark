# -*- coding: utf-8 -*-
"""bulk_importer — 题库批量入库编排器

扫描任意题库根目录（如 测试题库/ 或 广东专升本计算机考试题/）：
  顶层文件夹 → 科目(Subject)，内嵌subject声明优先覆盖
  NN-章节目录 → 章节(Chapter)，练习题.md解析入库，知识点总结.md整文存储
重复导入按 (科目, 章节序号) 幂等覆盖。

独立运行: python -m app.bulk_importer <题库根目录>
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
import urllib.parse
from datetime import datetime
from typing import Optional

from sqlalchemy.orm import Session

from .models.database import (
    APP_DATA_DIR, Chapter, ImportLog, Question, Subject, engine, init_db,
    SessionLocal,
)
from .parser.models import FileRejected
from .parser.strict_parser import StrictMDParser, load_source

STATIC_IMAGES = os.path.normpath(os.path.join(APP_DATA_DIR, "static", "images"))  # T-115: 复用APP_DATA_DIR


def resolve_image(rel: Optional[str], md_path: str,
                  extra_warnings: list) -> Optional[str]:
    """v2.1:【图】相对路径 → 拷入 static/images 并返回 /static/images/… URL。
    图像文件缺失→W323警告+置None（不阻断导入）。同名覆盖以支持图像内容更新。"""
    if not rel:
        return None
    src = os.path.normpath(os.path.join(os.path.dirname(md_path), rel))
    if not os.path.isfile(src):
        extra_warnings.append({"line": 0, "code": "W323",
                               "msg": f"图像文件不存在: {rel}"})
        return None
    os.makedirs(STATIC_IMAGES, exist_ok=True)
    digest = hashlib.sha1(os.path.abspath(src).encode("utf-8")).hexdigest()[:12]
    ext = os.path.splitext(src)[1].lower() or ".png"
    name = f"{digest}_{hashlib.sha1(rel.encode('utf-8')).hexdigest()[:8]}{ext}"
    shutil.copyfile(src, os.path.join(STATIC_IMAGES, name))
    return f"/static/images/{urllib.parse.quote(name)}"


def _detect_subject(first_lines: list[str]) -> Optional[str]:
    for line in first_lines:
        ms = RE_SUBJECT_LINE.match(line.strip())
        if ms:
            return ms.group(1).strip()
    return None


RE_SUBJECT_LINE = __import__("re").compile(r"^<!--\s*subject\s*[:：]\s*(.+?)\s*-->\s*$")


def import_bank(bank_root: str) -> dict:
    """导入整个题库根目录，返回汇总统计。幂等：可重复执行。"""
    init_db()
    parser = StrictMDParser()
    summary = {
        "bank_root": os.path.abspath(bank_root),
        "subjects": set(), "chapters": 0, "questions": 0,
        "files_total": 0, "files_failed": 0,
        "questions_skipped": 0, "sections_skipped": 0,
        "rejected": [],
    }
    logs: list[ImportLog] = []

    with SessionLocal() as db:                                  # type: Session
        for top in sorted(os.listdir(bank_root)):
            subject_dir = os.path.join(bank_root, top)
            if not os.path.isdir(subject_dir):
                continue
            if top.startswith(("_", ".", "~")):                 # 台账/隐藏目录跳过
                continue

            subject = db.query(Subject).filter_by(name=top).one_or_none()
            if subject is None:
                subject = Subject(name=top,
                                  folder_path=os.path.abspath(subject_dir))
                db.add(subject)
                db.flush()
            summary["subjects"].add(top)

            chapter_seq = 0
            for chap_name in sorted(os.listdir(subject_dir)):
                chap_path = os.path.join(subject_dir, chap_name)
                ex_file = os.path.join(chap_path, "练习题.md")
                kn_file = os.path.join(chap_path, "知识点总结.md")
                if not os.path.isfile(ex_file):
                    continue
                summary["files_total"] += 1
                chapter_seq += 1

                # ---- 解析练习题 ----
                try:
                    text = load_source(open(ex_file, "rb").read())
                except FileRejected as e:
                    summary["files_failed"] += 1
                    summary["rejected"].append(
                        {"file": rel(bank_root, ex_file), **e.__dict__})
                    logs.append(_log(db, subject.id, ex_file, "failed",
                                     {"fatal": e.__dict__}))
                    continue

                result = parser.parse_exercises(
                    text, ex_file,
                    fallback_title=chap_name,
                    fallback_subject=top)

                if not result.ok:
                    summary["files_failed"] += 1
                    summary["rejected"].append(
                        {"file": rel(bank_root, ex_file), **result.rejected})
                    logs.append(_log(db, subject.id, ex_file, "failed",
                                     {"fatal": result.rejected}))
                    continue

                # ---- 章节 upsert ----
                order_num = result.chapter.number or chapter_seq
                chapter = db.query(Chapter).filter_by(
                    subject_id=subject.id, order_num=order_num).one_or_none()
                if chapter is None:
                    chapter = Chapter(subject_id=subject.id,
                                      title=result.chapter.title,
                                      order_num=order_num)
                    db.add(chapter)
                    db.flush()
                else:
                    chapter.title = result.chapter.title
                summary["chapters"] += 1

                # ---- 知识点原文 ----
                if os.path.isfile(kn_file):
                    try:
                        kn_result = parser.parse_knowledge(
                            load_source(open(kn_file, "rb").read()), kn_file)
                        chapter.knowledge_md = kn_result and text_kn(kn_file)
                    except FileRejected as e:
                        logs.append(_log(db, subject.id, kn_file, "failed",
                                         {"fatal": e.__dict__}))

                # ---- 题目重建（幂等） ----
                db.query(Question).filter_by(chapter_id=chapter.id).delete()
                extra_warnings: list = []
                for q in result.questions:
                    db.add(Question(
                        chapter_id=chapter.id,
                        type=q.qtype.value,
                        number=q.raw_number or q.global_seq,
                        global_seq=q.global_seq,
                        material=q.material,
                        stem=q.stem,
                        options=json.dumps(q.options, ensure_ascii=False),
                        answer=q.answer,
                        accepts=(json.dumps(q.accepts, ensure_ascii=False)
                                 if q.accepts else None),
                        explanation=q.explanation,
                        source_line=q.source_line,
                        image=resolve_image(q.image, ex_file, extra_warnings),
                    ))

                summary["questions"] += len(result.questions)
                summary["questions_skipped"] += len(result.skipped_questions)
                summary["sections_skipped"] += len(result.skipped_sections)

                status = ("success" if not (result.skipped_questions
                                            or result.skipped_sections)
                          else "partial")
                report = {
                    "imported": len(result.questions),
                    "skippedQuestions": [vars(s) for s in result.skipped_questions],
                    "skippedSections": [vars(s) for s in result.skipped_sections],
                    "warnings": [vars(w) for w in result.warnings] + extra_warnings,
                }
                logs.append(_log(db, subject.id, ex_file, status, report))

        for lg in logs:
            db.add(lg)
        # 清理空科目：目录存在但没有任何成功入库章节的（如"考试信息"类资源目录）
        for empty_subject in db.query(Subject).filter(
                ~Subject.chapters.any()).all():
            db.delete(empty_subject)
        db.commit()

    summary["subjects"] = sorted(summary["subjects"])
    summary["generated_at"] = datetime.now().isoformat(timespec="seconds")
    return summary


def text_kn(path: str) -> str:
    from .parser.strict_parser import load_source as _ls
    return _ls(open(path, "rb").read())


def rel(root: str, path: str) -> str:
    return os.path.relpath(path, root)


def _log(db: Session, subject_id: Optional[int], file_path: str,
         status: str, report: dict) -> ImportLog:
    return ImportLog(subject_id=subject_id,
                     file_path=file_path,
                     status=status,
                     report_json=json.dumps(report, ensure_ascii=False))


def import_single_file(path: str) -> dict:
    """导入单个练习题.md：供管理接口使用。
    解析致命失败时返回 ok=False + fatal详情（路由层转HTTP 400）。"""
    init_db()
    parser = StrictMDParser()
    try:
        text = load_source(open(path, "rb").read())
    except FileRejected as e:
        return {"ok": False, "fatal": e.__dict__}

    result = parser.parse_exercises(text, path)
    if not result.ok:
        return {"ok": False, "fatal": result.rejected}

    subject_name = result.subject or "未分类"
    with SessionLocal() as db:
        subject = db.query(Subject).filter_by(name=subject_name).one_or_none()
        if subject is None:
            subject = Subject(name=subject_name,
                              folder_path=os.path.abspath(path))
            db.add(subject)
            db.flush()

        order_num = result.chapter.number or 1
        chapter = db.query(Chapter).filter_by(
            subject_id=subject.id, order_num=order_num).one_or_none()
        if chapter is None:
            chapter = Chapter(subject_id=subject.id,
                              title=result.chapter.title,
                              order_num=order_num)
            db.add(chapter)
            db.flush()
        else:
            chapter.title = result.chapter.title

        db.query(Question).filter_by(chapter_id=chapter.id).delete()
        extra_warnings: list = []
        for q in result.questions:
            db.add(Question(
                chapter_id=chapter.id,
                type=q.qtype.value,
                number=q.raw_number or q.global_seq,
                global_seq=q.global_seq,
                material=q.material,
                stem=q.stem,
                options=json.dumps(q.options, ensure_ascii=False),
                answer=q.answer,
                accepts=(json.dumps(q.accepts, ensure_ascii=False)
                         if q.accepts else None),
                explanation=q.explanation,
                source_line=q.source_line,
                image=resolve_image(q.image, path, extra_warnings),
            ))
        db.commit()
        return {"ok": True, "subject": subject_name,
                "chapter": chapter.title, "chapter_id": chapter.id,
                "imported": len(result.questions),
                "skippedQuestions": [vars(s) for s in result.skipped_questions],
                "warnings": [vars(w) for w in result.warnings] + extra_warnings}


if __name__ == "__main__":  # pragma: no cover
    root = sys.argv[1] if len(sys.argv) > 1 else "../test-bank"
    out = import_bank(root)
    print(json.dumps(out, ensure_ascii=False, indent=2))
