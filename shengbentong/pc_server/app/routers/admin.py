# -*- coding: utf-8 -*-
"""管理接口：导入/日志/统计/模板 + 管理页"""
from __future__ import annotations

import json
import os
import shutil
import tempfile
import zipfile

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse, PlainTextResponse
from sqlalchemy.orm import Session

from ..bulk_importer import STATIC_IMAGES, import_bank, import_single_file
from ..models.database import Chapter, ImportLog, Question, Subject, get_db
from ..schemas.schemas import ImportRequest

router = APIRouter(prefix="/api/admin", tags=["admin"])

_WEB_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "..", "web")
_WEB_DIR = os.path.normpath(_WEB_DIR)

TEMPLATE_MD = """<!-- subject: 科目名 -->
# 第N章 章节名 练习题

## 一、单选题

1. 题干文字
   A. 选项一
   B. 选项二
   C. 选项三
   D. 选项四
**【答案】B**
**【讲解】** 一句话讲清为什么选B。

## 二、判断题

1. 陈述句内容。（）
**【答案】√**
**【讲解】** 判断依据。√和×必须用这两个符号。

## 三、填空题

1. 空位用恰好6个下划线______表示。
**【答案】** 答案内容
**【讲解】** 解析说明。
"""

TEMPLATE_PROMPT = """你是严格的题库格式化引擎。只输出纯Markdown，禁止代码围栏包裹与寒暄。
仅保留 单选题/多选题/判断题/填空题 四种客观题型，主观题一律丢弃。
结构: # 第N章 名称 练习题 → ## 一、单选题 (分区序号用一、二、三…)
每题: 编号. 题干 / A-D各占一行 / **【答案】X** / **【讲解】**解析
判断题答案只用√×；填空空位固定______(6个下划线)，多空答案用｜分隔。
不确定的题目直接丢弃，宁缺毋滥。完整规范见《AI收集题目提示词规范.md》。
"""


@router.post("/import")
def admin_import(req: ImportRequest, db: Session = Depends(get_db)):
    path = req.path.strip()
    if not os.path.exists(path):
        raise HTTPException(404, f"路径不存在: {path}")

    # ---- 单文件模式：致命错误直接返回HTTP 400 + 具体错误 ----
    if os.path.isfile(path):
        result = import_single_file(path)
        status = "success" if (result["ok"]
                               and not result["skippedQuestions"]) else "partial"
        if not result["ok"]:
            log = ImportLog(file_path=os.path.abspath(path), status="failed",
                            report_json=json.dumps(result, ensure_ascii=False))
            db.add(log)
            db.commit()
            raise HTTPException(400, detail={
                "message": "文件未通过格式校验，已拒绝入库",
                "errors": [result["fatal"]],
                "hint": "请修正后重新导入；完整规则见《MD格式规范v2.2》",
            })
        log = ImportLog(file_path=os.path.abspath(path), status=status,
                        report_json=json.dumps(result, ensure_ascii=False))
        db.add(log)
        db.commit()
        db.refresh(log)
        return {"log_id": log.id, "ok": True, "status": status,
                "report": result}

    # ---- 目录模式 ----
    try:
        summary = import_bank(path)
    except ValueError as e:
        raise HTTPException(400, str(e))

    if summary["files_failed"] and summary["questions"] == 0:
        status = "failed"
    elif summary["files_failed"] or summary["questions_skipped"] \
            or summary["sections_skipped"]:
        status = "partial"
    else:
        status = "success"

    log = ImportLog(
        subject_id=None,
        file_path=os.path.abspath(path),
        status=status,
        report_json=json.dumps(summary, ensure_ascii=False),
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    return {"log_id": log.id, "ok": log.status != "failed",
            "status": log.status, "report": summary}


@router.get("/import/{log_id}")
def admin_import_log(log_id: int, db: Session = Depends(get_db)):
    log = db.get(ImportLog, log_id)
    if log is None:
        raise HTTPException(404, "导入记录不存在")
    return {"log_id": log.id, "file_path": log.file_path,
            "status": log.status,
            "imported_at": log.imported_at.isoformat() if log.imported_at else None,
            "report": json.loads(log.report_json) if log.report_json else None}


@router.get("/stats")
def admin_stats(db: Session = Depends(get_db)):
    subjects = []
    for s in db.query(Subject).order_by(Subject.name).all():
        q_count = 0
        by_type: dict = {}
        for c in s.chapters:
            for q in c.questions:
                q_count += 1
                by_type[q.type] = by_type.get(q.type, 0) + 1
        subjects.append({"name": s.name, "chapters": len(s.chapters),
                         "questions": q_count, "by_type": by_type})
    return {"subjects": subjects}


@router.get("/template", response_class=PlainTextResponse)
def admin_template(kind: str = "md"):
    if kind == "prompt":
        return PlainTextResponse(TEMPLATE_PROMPT)
    if kind == "full":
        template_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "..", "shengbentong", "docs", "出题模板.md")
        if os.path.isfile(template_path):
            return PlainTextResponse(open(template_path, encoding="utf-8").read())
        return PlainTextResponse(TEMPLATE_PROMPT)
    return PlainTextResponse(TEMPLATE_MD)


_TPL_DIR = os.path.normpath(os.path.join(_WEB_DIR, "..", "..", "docs", "templates"))


@router.get("/subjects")
def list_subjects():
    """返回所有可用科目模板的文件名列表（不含扩展名）"""
    if not os.path.isdir(_TPL_DIR):
        return {"subjects": []}
    subjects = []
    for f in sorted(os.listdir(_TPL_DIR)):
        if f.endswith(".md") and not f.startswith("_"):
            subjects.append(f[:-3])  # 去 .md 后缀
    return {"subjects": subjects}


@router.get("/template/subject/{name}", response_class=PlainTextResponse)
def get_subject_template(name: str):
    """返回指定科目的提示词模板"""
    safe = os.path.basename(name)  # 防路径穿越
    path = os.path.join(_TPL_DIR, safe + ".md")
    if not os.path.isfile(path):
        raise HTTPException(404, f"模板不存在: {name}")
    return PlainTextResponse(open(path, encoding="utf-8").read())


@router.get("/page", include_in_schema=False)
def admin_page():
    index = os.path.join(_WEB_DIR, "admin.html")
    if not os.path.isfile(index):
        raise HTTPException(404, "管理页文件缺失 web/admin.html")
    return FileResponse(index, media_type="text/html")


@router.get("/quiz/page", include_in_schema=False)
def quiz_page():
    """T-107: PC网页刷题入口（复用REST API，进度直写SQLite）"""
    page = os.path.join(_WEB_DIR, "quiz.html")
    if not os.path.isfile(page):
        raise HTTPException(404, "刷题页文件缺失 web/quiz.html")
    return FileResponse(page, media_type="text/html")


@router.post("/upload")
async def admin_upload(request: Request, name: str = Query(...),
                       db: Session = Depends(get_db)):
    """T-107+: 拖拽上传导入。原始字节流传输（零新依赖，不用python-multipart）。
    - .md   → 单文件导入（致命错误HTTP 400 + errors）
    - .zip  → 解压后按目录递归导入（summary与目录模式一致）
    响应统一归一化为目录报告形状，前端renderReport直接渲染。"""
    safe = os.path.basename(name or "").strip()
    if not (safe.lower().endswith(".md") or safe.lower().endswith(".zip")):
        raise HTTPException(400, "仅支持 .md 或 .zip 文件")
    data = await request.body()
    if not data:
        raise HTTPException(400, "上传内容为空")

    tmp_root = tempfile.mkdtemp(prefix="upmark_upload_")
    try:
        target = os.path.join(tmp_root, safe)
        with open(target, "wb") as f:
            f.write(data)

        if safe.lower().endswith(".zip"):
            extract_dir = os.path.join(tmp_root, "extracted")
            with zipfile.ZipFile(target) as z:
                for member in z.namelist():
                    dest = os.path.normpath(os.path.join(extract_dir, member))
                    if not dest.startswith(os.path.normpath(extract_dir)):
                        raise HTTPException(400, f"zip内含非法路径: {member}")
                z.extractall(extract_dir)
            try:
                summary = import_bank(extract_dir)
            except ValueError as e:
                raise HTTPException(400, str(e))
            if summary["files_failed"] and summary["questions"] == 0:
                status = "failed"
            elif (summary["files_failed"] or summary["questions_skipped"]
                    or summary["sections_skipped"]):
                status = "partial"
            else:
                status = "success"
            log = ImportLog(file_path=f"<upload>{safe}", status=status,
                            report_json=json.dumps(summary, ensure_ascii=False))
            db.add(log)
            db.commit()
            db.refresh(log)
            return {"log_id": log.id, "ok": status != "failed",
                    "status": status, "report": summary}

        # ---- 单 .md 文件 ----
        result = import_single_file(target)
        if not result.get("ok"):
            log = ImportLog(file_path=f"<upload>{safe}", status="failed",
                            report_json=json.dumps(result, ensure_ascii=False))
            db.add(log)
            db.commit()
            raise HTTPException(400, detail={
                "message": "文件未通过格式校验，已拒绝入库",
                "errors": [result["fatal"]],
                "hint": "请修正后重新拖入；完整规则见《MD格式规范v2.2》",
            })
        summary = {
            "files_total": 1,
            "questions": result.get("imported", 0),
            "questions_skipped": len(result.get("skippedQuestions", [])),
            "sections_skipped": 0,
            "warnings": result.get("warnings", []),
            "skipped_questions": result.get("skippedQuestions", []),
            "skipped_sections": [],
            "subject": result.get("subject"),
            "chapter": result.get("chapter"),
        }
        status = "success" if summary["questions_skipped"] == 0 else "partial"
        log = ImportLog(file_path=f"<upload>{safe}", status=status,
                        report_json=json.dumps(summary, ensure_ascii=False))
        db.add(log)
        db.commit()
        db.refresh(log)
        return {"log_id": log.id, "ok": True, "status": status,
                "report": summary}
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)


@router.delete("/subject/{subject_id}")
def delete_subject(subject_id: int, db: Session = Depends(get_db)):
    """T-118: 删除指定科目——级联删除其章节/题目/答题记录（ORM all,delete-orphan），
    并清理删除后不再被任何题目引用的图片文件。不可恢复。"""
    subject = db.get(Subject, subject_id)
    if subject is None:
        raise HTTPException(404, "科目不存在")
    chapters = db.query(Chapter).filter_by(subject_id=subject_id).all()
    chapter_ids = [c.id for c in chapters]
    q_rows = (db.query(Question)
              .filter(Question.chapter_id.in_(chapter_ids)).all()
              if chapter_ids else [])
    img_files = {os.path.basename(q.image) for q in q_rows if q.image}
    n_ch, n_q = len(chapters), len(q_rows)
    db.delete(subject)          # 级联: chapters/questions/answer_records
    db.commit()
    # 全库复查剩余引用，删除不再被引用的图片（共用图自动保护）
    remaining = {os.path.basename(r[0]) for r in
                 db.query(Question.image).filter(Question.image.isnot(None)).all()}
    removed = 0
    for name in sorted(img_files):
        if name in remaining:
            continue
        p = os.path.join(STATIC_IMAGES, name)
        if os.path.isfile(p):
            os.remove(p)
            removed += 1
    return {"deleted": {"chapters": n_ch, "questions": n_q, "images": removed}}
