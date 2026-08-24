# 升本通 API 契约 v1（Agent 2 后端 / Agent 3 前端 共同遵守）

> 数据结构权威定义：《MD格式规范v2.0》第十节 JSON Schema。本文只定义传输契约。
> 所有响应均为 UTF-8 JSON；错误统一走 HTTP 状态码 + body.error 描述。

## 0. 通用约定

```
BaseURL: http://<PC局域网IP>:8000
同步协议版本: schema_version = 1   （GET /api/health 与 /api/sync/all 均返回）
不兼容升级时: schema_version+1，App收到更大值 → 清空本地库重新全量同步
```

### 错误信封
```json
{"detail": "人类可读错误描述"}
```

## 1. 探测与绑定

### GET /api/health
```json
{"status": "ok", "app": "shengbentong", "schema_version": 1,
 "stats": {"subjects": 2, "chapters": 19, "questions": 812}}
```

## 2. 同步（App ← PC）

### GET /api/sync/all          （gzip可选：Accept-Encoding）
```jsonc
{
  "schema_version": 1,
  "exported_at": "2026-08-23T10:00:00",
  "subjects": [
    {"id": 1, "name": "C语言", "chapters": [
      {"id": 11, "title": "第一章 程序设计与C语言基础", "order_num": 1,
       "knowledge_md": "# 第一章 …原始Markdown…",
       "questions": [
         {"id": 90001, "type": "single_choice",     // single|multiple_choice|judgment|fill_blank
          "number": 1, "global_seq": 1,
          "material": null,                          // 【材料】块原文或null
          "stem": "题干…",
          "options": ["内容A","内容B","内容C","内容D"],  // judge/blank为[]
          "answer": "B",                              // multiple:"ABD" judgment:"T"/"F"
          "accepts": null,                            // fill_blank: [["编译","链接"]]
          "explanation": "…"}
       ]}
    ]}
  ]
}
```
App端处理：整体覆盖写入本地sqflite；进度记录不在此接口。

### GET /api/sync/chapters/{subject_id} / questions/{chapter_id}
分章懒加载变体，字段同上（去掉外层包装）。

## 3. 进度上报（App → PC）

### POST /api/sync/progress
```json
{"records": [
  {"question_id": 90001, "is_correct": true,
   "answered_at": "2026-08-23T21:03:11",
   "in_wrong_book": false, "in_favorites": true}
]}
```
响应：
```json
{"accepted": 128, "duplicate_ignored": 3}
```
语义：幂等；同一 (question_id, answered_at) 重复上报忽略。
冲突策略：同题取最新 answered_at。

## 4. 管理（PC本地网页用）

```
POST /api/admin/import           multipart: path=文件夹或文件路径(服务器本地)
                                 → {"log_id":7,"ok":true,"report":{...规范v2.0§9导入报告...}}
GET  /api/admin/import/{log_id}  → {"log_id":7,"file_path":"…","status":"success","report":{…}}
GET  /api/admin/stats            → {"subjects":[{"name":"C语言","chapters":10,"questions":520,
                                              "by_type":{"single_choice":320,...}}]}
GET  /api/admin/template?kind=md|prompt → text/plain 官方模板
```

导入报告 report 结构（节选，完整见《MD格式规范v2.0》第九节）：
```json
{"imported": 38, "skippedQuestions": [{"line":57,"code":"W302","reason":"…","stemPreview":"…"}],
 "skippedSections": [{"header":"四、简答题","startLine":190,"endLine":224,"code":"W205"}],
 "warnings": [{"code":"W310","line":88,"msg":"…"}]}
```

## 5. 状态码约定

| 码 | 场景 |
|----|------|
| 200 | 成功 |
| 404 | 资源不存在 |
| 422 | 请求体校验失败（Pydantic自动） |
| 500 | 服务器异常 |

> Agent 3 注意：App侧**禁止**自行解析任何MD；一切以 /api/sync 返回的结构化JSON为准。
