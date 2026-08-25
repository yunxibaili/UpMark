# 升本通 — 项目总览与导航

> 一句话：PC(Windows)自研解析MD当服务器，Flutter App绑定后全量下载、离线刷题、回家同步。
> 本文档 = 项目入口导航。设计细节分看 `pc_server/设计文档.md` 与 `flutter_app/设计文档.md`。

---

## 1. 五项最终决策

| # | 决策 |
|---|------|
| D1 | 不碰 EXAM-MASTER，代码全部自建（只借鉴其表结构与API思路） |
| D2 | MD解析器100%自研（行扫描+状态机），禁用 mistune/marked；不匹配的行走规范预定义E/W码，绝不猜测、绝不静默丢弃 |
| D3 | Flutter App + 本地SQLite离线缓存；不做微信小程序 |
| D4 | 技术栈精简：FastAPI+SQLAlchemy+SQLite / Flutter+sqflite+dio+Riverpod |
| D5 | Week1-10 严格串行开发 |

## 2. 总体架构

```
┌──────────────────────────────────────────────┐
│            PC 服务端 (Windows)                 │
│  MD导入 → StrictParser(自研状态机)             │
│        → SQLite主库 ←→ FastAPI REST           │
│  管理网页：导入/报告/官方模板下载                │
└──────────────────┬───────────────────────────┘
                   │ HTTP 局域网 (Dio)
┌──────────────────┴───────────────────────────┐
│         Flutter App (Android)                 │
│ 首次绑定(IP:8000) → 全量同步 → 本地sqflite     │
│ 离线刷题(零延迟) → 回家自动批量上报 sync_queue  │
└──────────────────────────────────────────────┘
```

## 3. 前后端职责边界（铁律）

| | PC 服务端 | Flutter App |
|--|-----------|-------------|
| **做** | MD导入/解析/校验、主库存储、REST API、导入报告、官方模板下载 | 绑定PC、全量下载、本地库缓存、知识点渲染、刷题交互判分、进度上报 |
| **不做** | 不碰任何UI细节 | **绝不做MD解析**——App只消费API返回的结构化JSON |

## 4. 目录导航

```
D:\dev\upmark\
├── README.md                        ← 本文件（总览导航）
├── api_contract_v2.json             ← 前后端接口契约（机器可读；v1存档于git历史）
├── db_snapshot/                     ← 本地DB快照（联调恢复用，不入库）
├── shengbentong/                    ← 项目主体
│   ├── 任务清单.md → docs/          ★全项目唯一任务清单在 docs/ 内
│   ├── docs/ …
│   ├── pc_server/  flutter_app/
│   └── test-bank/                   ← 多科目测试集（本地私有）
└── computer-bank/                   ← 计算机真题库（本地私有）
```

> 约定：`computer-bank/` 文件夹是纯题库资产，项目文件一律不放里面。

## 5. 当前状态（2026-08-25）

| 任务 | 状态 |
|------|------|
| T-100 解析器 | ✅ 512题/0跳/0失败 |
| T-101 测试题库 | ✅ 9科目/148题 全绿基线集（v1.3） |
| T-102 FastAPI | ✅ Gate 2/3通过 |
| T-103 App壳 | ✅ MuMu绑定+同步+离线验证通过 |
| T-104 刷题闭环 | ✅ 29/29测试绿，MuMu刷题/材料/多选全验证 |
| T-105 进阶 | ✅ 错题本/收藏/统计/两端同步验证通过 |
| T-107 PC网页刷题 | ✅ 四题型+材料块+进度直写，拖拽导入 |
| T-108 图像题 | ✅ 【图】全链路+规范v2.1+契约v2，MuMu在线/离线验收通过 |
| T-106 发布 | 🎯 进行中 |

## 6. 开发路线

| 周 | 模块 | 验收标准 |
|----|------|----------|
| 1-2 | pc_server：MD解析器+黄金样例集 | 1052题全量回归：客观题全入库或按W码跳过上报，0静默丢失 |
| 3 | pc_server：FastAPI 导入+同步API | curl拉取完整JSON，报告含跳过明细 |
| 4-5 | flutter_app：壳（绑定→下载→列表） | 实机断网可浏览全部科目章节 |
| 6-7 | flutter_app：刷题页四种题型+判分+讲解 | 刷完一章无卡顿；填空`;`多答案判分 |
| 8-9 | flutter_app：错题本/收藏/离线/上报 | 断网刷题回家自动同步一致 |
| 10 | UI统一百词斩风格+模拟考试+打包 | 非技术用户独立跑通全流程 |

## 7. 文档冲突优先级

```
需求文档 ＞ MD格式规范v2.1 ＞ 两份设计文档 ＞ 本README
```
实现与规范冲突 → 视为实现bug。改需求/规范须升版本号。

## 8. T-103 联调速查（复制即用）

> 契约唯一依据：仓库根目录 `api_contract_v2.json`。服务启动：双击 `pc_server/start.bat`

```bash
# 健康检查（应返回 status:ok 与 stats）
curl http://localhost:8000/api/health

# 绑定探测
curl -X POST http://localhost:8000/api/bind

# 全量同步（科目→章节→题目）
curl http://localhost:8000/api/sync/all

# 单章题目
curl http://localhost:8000/api/sync/questions/1

# 进度上报（幂等，重复提交按 question_id+answered_at 去重）
curl -X POST http://localhost:8000/api/sync/progress ^
  -H "Content-Type: application/json" ^
  -d "{\"records\":[{\"question_id\":1,\"is_correct\":true,\"in_wrong_book\":true}]}"

# 导入题库目录 / 单个md（单文件致命错误返回400+错误明细）
curl -X POST http://localhost:8000/api/admin/import ^
  -H "Content-Type: application/json" ^
  -d "{\"path\":\"D:/dev/upmark/test-bank\"}"

# 管理页(导入/报告/统计/模板) 与 Swagger
http://localhost:8000/api/admin/page
http://localhost:8000/docs
```

**DB快照恢复**：联调数据弄乱后，用 `db_snapshot/` 内备份覆盖 `pc_server/shengbentong.db` 即可回到661题初始态。

```powershell
Copy-Item db_snapshot\upmark_661.db shengbentong\pc_server\shengbentong.db -Force
```
