# -*- coding: utf-8 -*-
"""SQLAlchemy 模型 — PC端主库（SQLite）
对应《升本通_最终技术方案》第五节表结构。
"""
from __future__ import annotations

import os
from datetime import datetime

from sqlalchemy import (
    Boolean, CheckConstraint, DateTime, ForeignKey, Integer, Text,
    UniqueConstraint, create_engine,
)
from sqlalchemy.orm import (DeclarativeBase, Mapped, mapped_column,
                            relationship, sessionmaker)

DB_PATH = os.environ.get("SBT_DB", "shengbentong.db")

engine = create_engine(f"sqlite:///{DB_PATH}", echo=False, future=True)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class Subject(Base):
    """科目：一个科目 = 一个MD文件夹"""
    __tablename__ = "subjects"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    folder_path: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.now)

    chapters: Mapped[list["Chapter"]] = relationship(
        back_populates="subject", cascade="all, delete-orphan",
        order_by="Chapter.order_num")


class Chapter(Base):
    """章节：来自一次成功的练习题/知识点文件解析"""
    __tablename__ = "chapters"
    __table_args__ = (UniqueConstraint("subject_id", "order_num"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    subject_id: Mapped[int] = mapped_column(
        ForeignKey("subjects.id", ondelete="CASCADE"), nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    order_num: Mapped[int] = mapped_column(Integer, nullable=False)
    knowledge_md: Mapped[str | None] = mapped_column(Text)   # 知识点原始Markdown

    subject: Mapped["Subject"] = relationship(back_populates="chapters")
    questions: Mapped[list["Question"]] = relationship(
        back_populates="chapter", cascade="all, delete-orphan",
        order_by="Question.global_seq")


class Question(Base):
    """题目：四种客观题型；options为纯内容JSON数组（字母按下标隐含）"""
    __tablename__ = "questions"
    __table_args__ = (
        CheckConstraint("type IN ('single_choice','multiple_choice',"
                        "'judgment','fill_blank')"),
        UniqueConstraint("chapter_id", "global_seq"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    chapter_id: Mapped[int] = mapped_column(
        ForeignKey("chapters.id", ondelete="CASCADE"), nullable=False)
    type: Mapped[str] = mapped_column(Text, nullable=False)
    number: Mapped[int] = mapped_column(Integer, nullable=False)      # 原始题号
    global_seq: Mapped[int] = mapped_column(Integer, nullable=False)  # W310重排序号
    material: Mapped[str | None] = mapped_column(Text)                # 【材料】块
    stem: Mapped[str] = mapped_column(Text, nullable=False)
    options: Mapped[str | None] = mapped_column(Text)                 # JSON数组
    answer: Mapped[str] = mapped_column(Text, nullable=False)
    accepts: Mapped[str | None] = mapped_column(Text)                 # blank:JSON二维数组
    explanation: Mapped[str] = mapped_column(Text, nullable=False, default="")
    source_line: Mapped[int | None] = mapped_column(Integer)
    image: Mapped[str | None] = mapped_column(Text)                   # v2.1:静态图URL(/static/images/…)

    chapter: Mapped["Chapter"] = relationship(back_populates="questions")
    records: Mapped[list["AnswerRecord"]] = relationship(
        back_populates="question", cascade="all, delete-orphan")


class AnswerRecord(Base):
    """答题记录（PC端汇总）"""
    __tablename__ = "answer_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    question_id: Mapped[int] = mapped_column(
        ForeignKey("questions.id", ondelete="CASCADE"), nullable=False)
    is_correct: Mapped[bool] = mapped_column(Boolean, nullable=False)
    answered_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.now)
    in_wrong_book: Mapped[bool] = mapped_column(Boolean, default=False)
    in_favorites: Mapped[bool] = mapped_column(Boolean, default=False)

    question: Mapped["Question"] = relationship(back_populates="records")


class ImportLog(Base):
    """导入日志：report_json 存完整导入报告（《规范v2.1》第十节格式）"""
    __tablename__ = "import_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    subject_id: Mapped[int | None] = mapped_column(ForeignKey("subjects.id"))
    file_path: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(
        Text, CheckConstraint("status IN ('success','partial','failed')"),
        nullable=False)
    report_json: Mapped[str | None] = mapped_column(Text)
    imported_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.now)


def init_db() -> None:
    """建表（幂等）+ 轻量迁移。App端sqflite表结构见 flutter_app/设计文档.md 第4节。"""
    Base.metadata.create_all(engine)
    _migrate()


def _migrate() -> None:
    """v2.1：questions 表补 image 列（create_all 不会 ALTER 已有表）。"""
    with engine.connect() as conn:
        cols = {row[1] for row in conn.exec_driver_sql(
            "PRAGMA table_info(questions)")}
        if "image" not in cols:
            conn.exec_driver_sql(
                "ALTER TABLE questions ADD COLUMN image TEXT")
            conn.commit()


def get_db():
    """FastAPI依赖：请求级会话"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


if __name__ == "__main__":
    init_db()
    print(f"数据库已初始化: {DB_PATH}")
