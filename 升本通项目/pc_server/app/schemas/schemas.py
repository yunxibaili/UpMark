# -*- coding: utf-8 -*-
"""Pydantic 请求/响应模型 —— 与《docs/API契约.md》v1 对齐"""
from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class ProgressItem(BaseModel):
    question_id: int
    is_correct: bool
    answered_at: Optional[datetime] = None
    in_wrong_book: bool = False
    in_favorites: bool = False


class ProgressBatch(BaseModel):
    records: List[ProgressItem] = Field(default_factory=list)


class ImportRequest(BaseModel):
    path: str = Field(..., description="题库根目录或单科目目录(服务器本地路径)")
