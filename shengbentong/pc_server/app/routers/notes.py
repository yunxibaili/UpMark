# -*- coding: utf-8 -*-
"""笔记备份接口（v2.2/T-120）：App 是唯一创作源，PC 仅作镜像仓库。

- POST /api/notes/push   幂等 upsert（updated_at 新者胜）+ 墓碑物理删除；
                         返回 PC 侧缺失的图片清单
- GET  /api/notes/pull   全量拉取（换机恢复）；先孤儿回收再列图，保证清单干净
- POST /api/notes/image  单张笔记图上传：原始字节流（零新依赖，对齐 admin/upload 风格）

图片以 sha1 十六进制文件名存 %LOCALAPPDATA%/UpMark/static/note_images/，
经 /static/note_images 静态服务下发（main.py 挂载）；
MD 内以私有协议 noteimg://<sha1名> 引用（Joplin 资源模式同思路）。
"""
from __future__ import annotations

import os
import re
import urllib.parse
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from ..models.database import APP_DATA_DIR, Note, get_db
from ..schemas.schemas import NotesPushRequest

router = APIRouter(prefix="/api/notes", tags=["notes"])

NOTE_IMAGES = os.path.normpath(
    os.path.join(APP_DATA_DIR, "static", "note_images"))
ALLOWED_NOTE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}

_RE_NOTEIMG = re.compile(r"noteimg://([^)\s]+)")
_RE_SHA1_NAME = re.compile(r"[0-9a-fA-F]{8,40}")


def extract_note_image_refs(content_md: str) -> set[str]:
    """从 Markdown 正文提取全部笔记图片引用名（noteimg://<sha1名>）。"""
    return {urllib.parse.unquote(m)
            for m in _RE_NOTEIMG.findall(content_md or "")}


def _all_live_image_refs(db: Session) -> set[str]:
    """全库现存笔记引用的图片名集合（PC 不存墓碑，全部行即活笔记）。"""
    refs: set[str] = set()
    for (md,) in db.query(Note.content_md).all():
        refs |= extract_note_image_refs(md)
    return refs


def apply_note_push(db: Session, items) -> dict:
    """幂等应用一批笔记推送：
    - deleted=true → 物理删除该行（墓碑不留库）
    - 同 id 已存在且 PC 侧 updated_at 较新 → 保留 PC 版（新者胜）
    - question_id 一题一篇不变式：新绑定会挤掉绑同一题的旧笔记
    返回 {"accepted": n, "missing_images": [...]}（全库视角缺失图片）。"""
    accepted = 0
    for item in items:
        existing = db.get(Note, item.id)
        if item.deleted:
            if existing is not None:
                db.delete(existing)
            accepted += 1
            continue
        incoming_updated = item.updated_at or datetime.now()
        if existing is not None and existing.updated_at > incoming_updated:
            accepted += 1          # PC 侧较新：保留 PC 版
            continue
        if item.question_id is not None:
            db.query(Note).filter(
                Note.question_id == item.question_id,
                Note.id != item.id).delete(synchronize_session=False)
        if existing is None:
            existing = Note(id=item.id,
                            created_at=item.created_at or incoming_updated)
            db.add(existing)
        existing.title = item.title
        existing.content_md = item.content_md
        existing.question_id = item.question_id
        existing.updated_at = incoming_updated
        accepted += 1
    db.commit()
    refs = _all_live_image_refs(db)
    missing = sorted(name for name in refs
                     if not os.path.isfile(os.path.join(NOTE_IMAGES, name)))
    return {"accepted": accepted, "missing_images": missing}


def save_note_image(name: str, data: bytes) -> str:
    """校验并落盘单张笔记图（sha1 十六进制名 + 扩展名白名单）。
    非法输入抛 ValueError（路由层转 HTTP 400），绝不静默吞错。"""
    safe = os.path.basename((name or "").strip())
    stem, ext = os.path.splitext(safe)
    if ext.lower() not in ALLOWED_NOTE_EXTS:
        raise ValueError(f"仅支持图片格式 {sorted(ALLOWED_NOTE_EXTS)}: {name}")
    if not _RE_SHA1_NAME.fullmatch(stem):
        raise ValueError(f"文件名须为sha1十六进制摘要: {name}")
    if not data:
        raise ValueError("上传内容为空")
    os.makedirs(NOTE_IMAGES, exist_ok=True)
    with open(os.path.join(NOTE_IMAGES, safe), "wb") as f:
        f.write(data)
    return safe


def cleanup_orphan_note_images(db: Session) -> int:
    """物理删除不再被任何笔记引用的图片文件（共用图自动保护）。
    返回删除数。目录不存在时视为空集返回 0。"""
    if not os.path.isdir(NOTE_IMAGES):
        return 0
    refs = _all_live_image_refs(db)
    removed = 0
    for fname in sorted(os.listdir(NOTE_IMAGES)):
        if fname in refs:
            continue
        path = os.path.join(NOTE_IMAGES, fname)
        if os.path.isfile(path):
            os.remove(path)
            removed += 1
    return removed


def _note_dict(n: Note) -> dict:
    return {
        "id": n.id,
        "title": n.title,
        "content_md": n.content_md,
        "question_id": n.question_id,
        "created_at": (n.created_at.isoformat(timespec="seconds")
                       if n.created_at else None),
        "updated_at": (n.updated_at.isoformat(timespec="seconds")
                       if n.updated_at else None),
    }


@router.post("/push")
def notes_push(payload: NotesPushRequest, db: Session = Depends(get_db)):
    result = apply_note_push(db, payload.notes)
    cleanup_orphan_note_images(db)
    return result


@router.get("/pull")
def notes_pull(db: Session = Depends(get_db)):
    cleanup_orphan_note_images(db)
    rows = db.query(Note).order_by(Note.updated_at.desc()).all()
    images: list[str] = []
    if os.path.isdir(NOTE_IMAGES):
        images = sorted(f for f in os.listdir(NOTE_IMAGES)
                        if os.path.splitext(f)[1].lower() in ALLOWED_NOTE_EXTS)
    return {
        "exported_at": datetime.now().isoformat(timespec="seconds"),
        "notes": [_note_dict(n) for n in rows],
        "images": images,
    }


@router.post("/image")
async def notes_image(request: Request, name: str = Query(...)):
    """原始字节流上传单张笔记图（App 端 dio 直发 Uint8List，零 multipart 依赖）。"""
    data = await request.body()
    try:
        stored = save_note_image(name, data)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return {"stored": stored}
