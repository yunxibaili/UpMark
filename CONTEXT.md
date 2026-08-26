# UpMark 升本通 · AI 交接上下文（压缩版）

> 本文档供新 AI 接手项目时一次性喂入。覆盖全部必要上下文，读完即可干活。
> 最后更新：2026-08-25 | 分支：main（发布）/ image-support（开发，已合入 main）

---

## 一、项目是什么

**升本通（UpMark）**：个人备考工具。PC(Windows) 自研解析 Markdown 当服务器，Flutter App 绑定后全量下载、离线刷题、回家同步进度。

- **PC 端**：Python 3 + FastAPI + SQLAlchemy + SQLite + uvicorn，端口 8000
- **App 端**：Flutter 3.47 + sqflite + dio + shared_preferences
- **网页端**：admin.html（管理台）+ quiz.html（刷题），零 CDN
- **仓库**：`D:\dev\upmark` → GitHub `yunxibaili/UpMark`
- **源码体积**：5.2 MB（构建产物已清，flutter build 会再生 ~3GB 属正常）
- **题库**：790 题 / 12 科目 / 48 章 / 21 题带图（DB 在 `%LOCALAPPDATA%/UpMark/shengbentong.db`）

---

## 二、文件结构（关键路径）

```
D:\dev\upmark\
├── api_contract_v2.json          ← 机器可读契约 v2.1
├── CHECKLIST.md                  ← 验收清单
├── RELEASE_NOTES.md              ← 版本说明
├── .gitignore                    ← test-bank/computer-bank/tests/scripts/归档/db 全排除
├── shengbentong/
│   ├── pc_server/
│   │   ├── app/
│   │   │   ├── main.py           ← 入口：FastAPI + /static 挂载 + GET / 302 重定向
│   │   │   ├── bulk_importer.py  ← 目录/ZIP 导入编排 + 零文件守卫(防误清空)
│   │   │   ├── routers/
│   │   │   │   ├── sync.py       ← /api/sync/* + data_version 动态推导
│   │   │   │   └── admin.py      ← /api/admin/* (导入/统计/模板/删除/上传/lan-ip)
│   │   │   ├── parser/
│   │   │   │   └── strict_parser.py  ← 自研状态机(855行)，禁用mistune/marked
│   │   │   └── models/database.py    ← SQLAlchemy模型 + APP_DATA_DIR + 级联配置
│   │   ├── static/
│   │   │   └── marked.min.js     ← 网页渲染库(本地内嵌,零CDN)
│   │   ├── web/
│   │   │   ├── admin.html        ← 管理台单页
│   │   │   └── quiz.html         ← 网页刷题单页
│   │   ├── tests/                ← 本地私有(gitignored), 46/46绿
│   │   ├── scripts/              ← 本地私有(gitignored), 工具脚本
│   │   ├── start.bat             ← 启动+备份+自动开浏览器
│   │   └── requirements.txt      ← fastapi/uvicorn/sqlalchemy 仅3个
│   ├── flutter_app/
│   │   ├── lib/
│   │   │   ├── main.dart         ← brandBlue=#4A90D9, okGreen, badRed
│   │   │   ├── models/models.dart
│   │   │   ├── screens/          ← bind/subject/chapter/quiz/exam/knowledge/stats/wrong_book/favorites
│   │   │   ├── services/         ← api_service/db_service/sync_service/quiz_logic/lan_scanner
│   │   │   └── widgets/rich_text.dart ← 零依赖富文本($公式蓝斜体/代码灰底/围栏容器)
│   │   ├── test/                 ← 49/49 绿
│   │   └── pubspec.yaml          ← dio/sqflite/markdown_widget/path/shared_preferences (零冗余)
│   ├── docs/
│   │   ├── API契约.md            ← 人读传输契约 v2.1
│   │   ├── MD格式规范v2.2.md     ← 解析层规范
│   │   ├── AI收集题目提示词规范.md ← v1.3 (R5a读图+R5b公式+R5c填空双轨+R5d代码)
│   │   ├── 代码生成与审批规范.md  ← v1.2 (红线+并行编辑规则)
│   │   ├── 数据集技术文档.md      ← v1.4
│   │   ├── 出题模板.md           ← v2.2
│   │   ├── 需求文档.md
│   │   ├── templates/            ← 7科目出题模板(_base+6科目)
│   │   ├── 测试报告_T-117.md
│   │   └── 归档/                 ← 旧版规范(本地保留,gitignored)
│   ├── flutter_app/设计文档.md
│   ├── pc_server/设计文档.md
│   └── README.md
├── db_snapshot/upmark_749.db     ← 恢复快照(当前实际790题,快照略旧)
├── computer-bank/                ← 计算机真题库(本地私有,gitignored)
├── archive/                      ← api_contract_v1.json(已归档)
└── RELEASE_NOTES.md              ← v1.0 版本说明
```

**运行时数据**（不在仓库中）：
```
%LOCALAPPDATA%/UpMark/
├── shengbentong.db               ← SQLite主库
├── static/images/                ← 题目图片(sha1命名)
└── backup/                       ← 启动自动备份(保留10份)
```

---

## 三、分支策略

| 分支 | 用途 | 当前状态 |
|------|------|----------|
| `main` | 发布基线 | ✅ 已合入全部功能，与 image-support 同步 |
| `image-support` | 开发分支 | ✅ 已合入 main，保留作为开发线 |

**规则**：新功能在 image-support 开发，经用户批准后合入 main。归档文档（docs/归档/）和题库数据（test-bank/computer-bank）永远不上传 GitHub。

---

## 四、核心流程

### 4.1 出题 → 导入 → 刷题 全链路

```
用户找真题/教材 → 对话AI转录(OCR两步法) → 科目模板提示词喂AI → AI输出MD
→ 存 练习题.md + 图片放 images/ → start.bat 启动PC → 管理台拖拽/路径导入
→ 解析器(E/W码校验) → 拷图入static(sha1命名) → SQLite落库
→ App重同步(全量下载+原子下载图片) → 离线刷题 → 进度上报
```

### 4.2 图像题处理

```
MD写【图】images/fig1.png → 解析器识别(归属其后题目/分区重置/可加粗/可与材料共存)
→ 导入时 resolve_image(): 相对路径定位→sha1命名→拷入static/images
→ sync/all下发 image字段(/static/images/<sha1名>) → App原子下载(.tmp→rename)
→ DB改写为本地绝对路径 → Image.file离线渲染
```

- W322 = 空图路径忽略；W323 = 缺图置null不阻断
- 【图】必须写在分区内（分区头重置归属）
- $$ 独立公式块仅限【讲解】中（题干后紧跟会吞题——T-115已修lookahead但提示词仍保守限制）

### 4.3 LaTeX/代码文本化（D方案阶段一）

- 行内公式 `$...$` → App蓝斜体等宽 + 网页`<code class=math>`
- 代码围栏 ```c → App灰底等宽容器 + 网页marked渲染
- 填空含公式必须附纯文本备选（英文分号;分隔）
- **阶段二（永不做除非用户投诉）**：flutter_math_fork / KaTeX 精美排版

### 4.4 同步与离线

- App 全量下载 sync/all（gzip）→ 预下载全部题图到本地 → DB改写为本地绝对路径
- 原子下载：.tmp → rename（杀进程/断网不留半张图）
- 答题进 sync_queue → 联网批量 POST /api/sync/progress → 幂等去重
- data_version 动态推导（科目-章-题数-最大ID）→ App MaterialBanner 弱提示更新

---

## 五、文档版本线（零漂移）

| 文档 | 版本 | 位置 |
|------|------|------|
| MD格式规范 | v2.2 | docs/MD格式规范v2.2.md（v2.1及更早已归档） |
| API契约 | v2.1 | docs/API契约.md（人读）+ api_contract_v2.json（机器） |
| 提示词规范 | v1.3 | docs/AI收集题目提示词规范.md |
| 代码审批规范 | v1.2 | docs/代码生成与审批规范.md |
| 数据集技术文档 | v1.4 | docs/数据集技术文档.md |
| 出题模板 | v2.2 | docs/出题模板.md + docs/templates/ 7文件 |
| 测试报告 | T-117 | docs/测试报告_T-117.md |

---

## 六、硬性红线（违反即拒）

| # | 红线 |
|---|------|
| 1 | MD解析禁用 mistune/marked 等通用库，必须自研行扫描状态机 |
| 2 | 两端必须 SQLite，禁 MySQL/PostgreSQL/MongoDB |
| 3 | 禁止任何公网调用（CDN、第三方API、云存储） |
| 4 | 文件读写强制 UTF-8 无 BOM |
| 5 | 禁止 try-except 静默吞错，必须带上下文异常 |
| 6 | 新增依赖需用户审批 |
| 7 | 禁止上传 test-bank/ computer-bank/ tests/ scripts/ db_snapshot/ docs/归档/ archive/ |
| 8 | 图像版本与无图像版本分支隔离（main=无图像基线，开发在image-support） |
| 9 | 归档旧文档不上传 |
| 10 | 禁止修改 SQLite 表结构（onUpgrade 补列除外） |
| 11 | 禁止重写解析器状态机 |
| 12 | 禁止把简单逻辑抽象成 Manager/Provider/Handler |
| 13 | 禁止写超过 3 层的继承 |
| 14 | 错误处理：文件操作/网络/DB 写入必须有 try-catch + 上下文 |
| 15 | 判分归一化逻辑（多候选匹配）不动 |
| 16 | 离线同步 sync_queue 持久化逻辑不动 |
| 17 | 并行编辑：开工前 git status 干净 + pull；同文件禁双端同改；完成即推送 |

---

## 七、E/W 校验码速查

| 码 | 含义 | 级别 |
|----|------|------|
| E100 | UTF-8 BOM 或编码错误 | 拒文件 |
| E122 | 代码围栏不配对 | 拒文件 |
| E130 | 解析完成 0 题可用 | 拒文件 |
| W205 | 非白名单题型分区 | 跳整区 |
| W301/W305 | 选项<2 / 选项数≠4 | 跳题 |
| W302 | 缺答案行或值非法 | 跳题 |
| W303/W304 | 题干空 / 填空无空位 | 跳题 |
| W307 | 多答案矛盾 | 跳题 |
| W310 | 题号断档/重复 | 自动重排 |
| W318 | 非加粗答案行在A/B样式区 | 接受 |
| W319 | 多空答案非标准分隔符 | 自动识别 |
| W322 | 【图】行空路径 | 忽略 |
| W323 | 图像文件不存在 | image=null 不阻断 |
| W313 | 非标准下划线长度 | 告警 |
| W316 | 分区序号异常 | 告警 |

---

## 八、当前项目状态（T-100~T-119 全完结）

| 任务 | 状态 |
|------|------|
| T-100~T-107 基础（解析器/题库/FastAPI/App壳/刷题/进阶/网页刷题） | ✅ |
| T-108 图像题全链路 | ✅ |
| T-109 考研真题图像实战 | ✅ |
| T-110 分支隔离 + 归档退出 | ✅ |
| T-111 LaTeX/代码文本化 D方案阶段一 | ✅（阶段二永不做除非投诉） |
| T-112 五项加固（原子下载/data_version/备份/字体/CHECKLIST） | ✅ |
| T-113 提示词v1.3 + 引用大扫除 | ✅ |
| T-114 提示词三轮收敛 + 全科目验证 | ✅ |
| T-115 Ponytail精简（2.26GB→5MB） | ✅ |
| T-116 data_version动态化 | ✅ |
| T-117 全量测试（清零→双通道→毒化10点→报告） | ✅ |
| T-118 单科目删除双端 | ✅ |
| T-119 连接扫描 + PC直达网页 | ✅ |

**队列**：空。**可选项**：release打包签名、对错动画、T-111阶段二精美公式、笔记版本。

---

## 九、环境速查

| 项 | 值 |
|----|-----|
| Flutter | 3.47.1 stable |
| Android SDK | 36.0.0 @ D:\android-sdk |
| JDK | 17 @ D:\jdk17\jdk-17.0.20+8 |
| MuMu模拟器 | adb connect 127.0.0.1:16384 |
| PC局域网IP | 192.168.1.124 |
| 服务端启动 | 双击 pc_server/start.bat（备份+自动开浏览器+uvicorn） |
| 管理台 | http://localhost:8000/api/admin/page |
| 刷题页 | http://localhost:8000/api/admin/quiz/page |
| App绑定 | 输入PC局域网IP:8000 或 扫描局域网自动发现 |
| 运行时数据 | %LOCALAPPDATA%/UpMark/ |
| Python | 系统 Python 3.12（无venv，依赖全局安装） |

---

## 十、常见操作速查

```bash
# 启动服务端
cd shengbentong/pc_server && start.bat

# 导入题库（管理台拖拽 或 API）
curl -X POST http://localhost:8000/api/admin/import -H "Content-Type: application/json" -d '{"path":"D:/dev/upmark/shengbentong/test-bank"}'

# 检查健康
curl http://localhost:8000/api/health

# Flutter 构建
cd shengbentong/flutter_app && flutter build apk --debug   # 或 --release

# 部署 MuMu
D:\android-sdk\platform-tools\adb.exe -s 127.0.0.1:16384 install -r build\app\outputs\flutter-apk\app-debug.apk

# 跑测试
python -m pytest -q                    # PC 46/46
flutter analyze && flutter test        # Flutter 49/49
python scripts/validate_prompts.py     # 解析矩阵全量

# 提示词验证（全量测试库）
python scripts/validate_prompts.py "D:\dev\upmark\shengbentong\test-bank\全量测试"
```

---

## 十一、注意事项

1. **并行编辑**：开工前 git status 必须干净 + pull；同文件禁双端同改
2. **目录导入**：必须传题库根目录，传科目文件夹会把章节误当科目（files_total=0）
3. **【图】写在分区内**：分区头之前的【图】会被静默重置丢弃
4. **$$ 块**：仅允许在讲解中（题干后紧跟曾致吞题，T-115 已修 lookahead 但提示词仍保守）
5. **填空多候选**：用英文分号 `;` 分隔，全角 `｜` 是多空分隔符不能混用
6. **续分区编号**：`（续）` 分区也必须从 1 开始编号
7. **test-bank 是本地私有**：gitignored，所有生成的题目/转化/验证内容都在这里，不上 GitHub
8. **删除科目**：双端同删（App调PC接口+清本地），答题记录一并删除不可恢复
9. **归档文档**：docs/归档/ 本地保留但不上传
10. **data_version**：动态推导，每次导入后必变（App会弹更新提示），不导入则稳定
