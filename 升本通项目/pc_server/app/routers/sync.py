# -*- coding: utf-8 -*-
"""同步接口：App/PC网页 共用的数据下行与进度上行"""
from __future__ import annotations

import json
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..models.database import (
    AnswerRecord, Chapter, Question, Subject, get_db,
)
from ..schemas.schemas import ProgressBatch, ProgressItem

router = APIRouter(prefix="/api", tags=["sync"])
SCHEMA_VERSION = 1


def _question_dict(q: Question) -> dict:
    return {
        "id": q.id,
        "type": q.type,
        "number": q.number,
        "global_seq": q.global_seq,
        "material": q.material,
        "stem": q.stem,
        "options": json.loads(q.options) if q.options else [],
        "answer": q.answer,
        "accepts": json.loads(q.accepts) if q.accepts else None,
        "explanation": q.explanation,
    }


def _chapter_dict(c: Chapter, with_questions: bool = False) -> dict:
    d = {
        "id": c.id,
        "title": c.title,
        "order_num": c.order_num,
        "knowledge_md": c.knowledge_md,
    }
    if with_questions:
        d["questions"] = [_question_dict(q) for q in c.questions]
    return d


def _subject_dict(s: Subject, deep: bool = False) -> dict:
    return {
        "id": s.id,
        "name": s.name,
        "chapters": [_chapter_dict(c, deep) for c in s.chapters],
    }


def _counts(db: Session) -> dict:
    return {
        "subjects": db.query(Subject).count(),
        "chapters": db.query(Chapter).count(),
        "questions": db.query(Question).count(),
    }


@router.get("/health")
def health(db: Session = Depends(get_db)):
    return {"status": "ok", "app": "shengbentong",
            "schema_version": SCHEMA_VERSION, "stats": _counts(db)}


@router.get("/sync/all")
def sync_all(db: Session = Depends(get_db)):
    subjects = db.query(Subject).order_by(Subject.name).all()
    return {
        "schema_version": SCHEMA_VERSION,
        "exported_at": datetime.now().isoformat(timespec="seconds"),
        "subjects": [_subject_dict(s, deep=True) for s in subjects],
    }


@router.get("/sync/chapters/{subject_id}")
def sync_chapters(subject_id: int, db: Session = Depends(get_db)):
    s = db.get(Subject, subject_id)
    if s is None:
        raise HTTPException(404, "科目不存在")
    return {"id": s.id, "name": s.name,
            "chapters": [_chapter_dict(c, True) for c in s.chapters]}


@router.get("/sync/questions/{chapter_id}")
def sync_questions(chapter_id: int, db: Session = Depends(get_db)):
    c = db.get(Chapter, chapter_id)
    if c is None:
        raise HTTPException(404, "章节不存在")
    return {"chapter_id": c.id, "title": c.title,
            "questions": [_question_dict(q) for q in c.questions]}


@router.post("/sync/progress")
def sync_progress(batch: ProgressBatch, db: Session = Depends(get_db)):
    accepted = duplicate = 0
    for item in batch.records:
        dt = item.answered_at or datetime.now()
        exists = db.query(AnswerRecord).filter_by(
            question_id=item.question_id, answered_at=dt).first()
        if exists is not None:
            duplicate += 1
            continue
        db.add(AnswerRecord(
            question_id=item.question_id,
            is_correct=item.is_correct,
            answered_at=dt,
            in_wrong_book=item.in_wrong_book,
            in_favorites=item.in_favorites,
        ))
        accepted += 1
    db.commit()
    return {"accepted": accepted, "duplicate_ignored": duplicate}
