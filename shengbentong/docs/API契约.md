# 升本通 API 契约 v2.1（PC服务端 / Flutter App 共同遵守）

> 数据结构权威定义：《MD格式规范v2.2》第十一节 JSON Schema；机器可读契约：仓库根 `api_contract_v2.json`（v2.1）。本文为人读传输契约，与机器契约同步。
> 所有响应均为 UTF-8 JSON；错误统一走 HTTP 状态码 + `{"detail": "描述"}`。

## 0. 通用约定

```
BaseURL: http://<PC局域网IP>:8000
协议版本: schema_version = 2   （GET /api/health 与 /api/sync/all 均返回）
数据版本: data_version = "<科目>-<章>-<题数>-<最大题ID>"（从DB状态动态推导，T-116）
          导入增删后必变；App本地值不一致 → MaterialBanner 弱提示"题库有更新"（稍后可继续用旧题）
不兼容升级: schema_version 大于App支持值 → App提示升级（本地DB onUpgrade无损迁移）
浏览器直达: GET / → 302 重定向到管理台 /api/admin/page（T-119）
```

### 错误信封
```json
{"detail": "人类可读错误描述"}
```

## 1. 探测与绑定

### GET /api/health
```json
{"status": "ok", "app": "shengbentong", "schema_version": 2,
 "data_version": "12-47-790-4566",
 "stats": {"subjects": 13, "chapters": 49, "questions": 790}}
```

### POST /api/bind
```json
{"status": "bound", "app": "shengbentong", "schema_version": 2}
```

### GET /api/admin/lan-ip          （T-119新增）
返回服务端局域网 IPv4（非回环），供管理台生成"手机扫码打开管理台"二维码。
```json
{"ip": "192.168.1.124"}
```

## 2. 同步（App ← PC）

### GET /api/sync/all          （gzip可选：Accept-Encoding）
```jsonc
{
  "schema_version": 2,
  "data_version": "12-47-790-4566",   // 动态推导，见第0节
  "exported_at": "2026-08-25T10:00:00",
  "subjects": [
    {"id": 1, "name": "C语言", "chapters": [
      {"id": 11, "title": "第一章 程序设计与C语言基础", "order_num": 1,
       "knowledge_md": "# 第一章 …原始Markdown…",
       "questions": [
         {"id": 90001, "type": "single_choice",     // single|multiple_choice|judgment|fill_blank
          "number": 1, "global_seq": 1,
          "material": null,                          // 【材料】块原文或null
          "image": "/static/images/<sha1名>.png",    // v2.1:【图】静态URL或null（App同步时原子下载到本地改写为绝对路径）
          "stem": "题干…",
          "options": ["内容A","内容B","内容C","内容D"],  // judge/blank为[]
          "answer": "B",                              // multiple:"ABD" judgment:"T"/"F"
          "accepts": null,                            // fill_blank: [["编译","链接"]]
          "explanation": "…"}
       ]}]}
  ]
}
```
App端处理：整体覆盖写入本地sqflite；题目图像经原子下载（.tmp→rename）到本地，离线可渲染。

### GET /api/sync/chapters/{subject_id} / questions/{chapter_id}
分章懒加载变体，字段同上（去掉外层包装）。

## 3. 进度上报（App → PC）

### POST /api/sync/progress
```json
{"records": [
  {"question_id": 90001, "is_correct": true,
   "answered_at": "2026-08-25T21:03:11",
   "in_wrong_book": false, "in_favorites": true}
]}
```
响应：
```json
{"accepted": 128, "duplicate_ignored": 3}
```
语义：幂等；同一 (question_id, answered_at) 重复上报忽略。

## 4. 管理（PC本地网页用）

```
GET  /                             → 302 重定向到 /api/admin/page（T-119）
GET  /api/admin/page               → 管理台单页（导入/统计/模板/二维码）
GET  /api/admin/quiz/page          → 网页刷题单页
POST /api/admin/import             body={"path":"题库根或md路径"} → 目录/单文件导入
POST /api/admin/upload?name=x.zip  原始字节流拖拽上传（.md/.zip，zip自动解压递归导入；
                                   零文件时400拒绝——防误清空题库，T-117守卫）
GET  /api/admin/import/{log_id}    → 历史导入报告
GET  /api/admin/stats              → 分科目统计
GET  /api/admin/subjects           → 可用出题模板科目列表（docs/templates/）
GET  /api/admin/template?kind=md   → text/plain 官方模板
GET  /api/admin/template/subject/{name} → text/plain 科目出题模板
DELETE /api/admin/subject/{id}     → 删除指定科目（v2.1/T-118：级联删章/题/答题记录
                                     + 清理不再被引用的图片文件；不可恢复）
                                   → {"deleted":{"chapters":n,"questions":n,"images":n}}
GET  /static/images/<sha1名>.png    → 题目图片（存储于 %LOCALAPPDATA%/UpMark/static/images）
GET  /static/marked.min.js         → 网页渲染库（本地内嵌，零CDN）
```

导入报告 report 结构（节选，完整见《MD格式规范v2.2》第十节）：
```json
{"imported": 38, "questions_skipped": 1,
 "skipped_questions": [{"line":57,"code":"W302","reason":"…","stem_preview":"…"}],
 "warnings": [{"code":"W310","line":88,"msg":"…"}]}
```

## 5. 状态码约定

| 码 | 场景 |
|----|------|
| 200 | 成功 |
| 302 | GET / 重定向管理台 |
| 400 | 请求非法（含导入零文件防误清空守卫、zip非法路径） |
| 404 | 资源不存在 |
| 422 | 请求体校验失败（Pydantic自动） |
| 500 | 服务器异常 |

> App侧**禁止**自行解析任何MD；一切以 /api/sync 返回的结构化JSON为准。
> 契约修订规则：只增不改名；破坏性变更须升 schema_version 并同步机器契约 api_contract_v2.json。
