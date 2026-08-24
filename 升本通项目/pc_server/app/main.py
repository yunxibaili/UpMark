# -*- coding: utf-8 -*-
"""升本通 PC 服务端入口"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .models.database import init_db
from .routers import admin, sync


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()          # 启动即建表（幂等）
    yield


app = FastAPI(
    title="升本通服务端",
    description="局域网题库服务：MD导入 / REST同步 / 管理后台",
    version="1.0.0",
    lifespan=lifespan,
)

# App与PC浏览器均为局域网内不同源访问，放开CORS（仅限内网部署）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(sync.router)
app.include_router(admin.router)
