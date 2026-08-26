# -*- coding: utf-8 -*-
"""升本通 PC 服务端入口"""
from __future__ import annotations

import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from .models.database import init_db
from .routers import admin, sync

_STATIC_DIR = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "static"))


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()          # 启动即建表（幂等）+轻量迁移
    os.makedirs(os.path.join(_STATIC_DIR, "images"), exist_ok=True)
    yield


app = FastAPI(
    title="升本通服务端",
    description="局域网题库服务：MD导入 / REST同步 / 管理后台",
    version="2.0.0",
    lifespan=lifespan,
)

# App与PC浏览器均为局域网内不同源访问，放开CORS（仅限内网部署）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# v2.1/T-115: 题目图像在 %LOCALAPPDATA%/UpMark/static/images（bulk_importer拷入）
from .bulk_importer import STATIC_IMAGES as _IMAGES_DIR
os.makedirs(_IMAGES_DIR, exist_ok=True)   # StaticFiles要求目录在挂载前已存在
os.makedirs(_STATIC_DIR, exist_ok=True)
app.mount("/static/images", StaticFiles(directory=_IMAGES_DIR), name="images")  # 具体路径先注册
app.mount("/static", StaticFiles(directory=_STATIC_DIR), name="static")          # web资源(marked.min.js)

@app.get("/", include_in_schema=False)
def root():
    """T-119: 浏览器输 localhost:8000 直达管理台。"""
    return RedirectResponse(url="/api/admin/page", status_code=302)


app.include_router(sync.router)
app.include_router(admin.router)
