# 广东专升本学习助手 - 技术文档

> 一个类似百词斩的桌面学习应用，先学知识点，再做题巩固

---

## 一、项目概述

### 1.1 项目名称
**升本通** - 广东专升本学习助手

### 1.2 项目目标
- 创建一个UI简洁、类似百词斩风格的Windows桌面应用
- 支持"先学知识点，再做题巩固"的学习模式
- 支持导入新的MD文件，实现不同科目切换
- 专注于广东专升本C语言和数据结构考试

### 1.3 技术选型

| 方案 | 框架 | 语言 | 优点 | 缺点 | 推荐度 |
|------|------|------|------|------|--------|
| **方案A** | Electron | JavaScript/TypeScript | 生态成熟、跨平台、MD支持好 | 包体大(~150MB) | ⭐⭐⭐⭐⭐ |
| 方案B | Tauri | Rust + Web前端 | 包体小(~10MB)、性能好 | Rust学习曲线陡 | ⭐⭐⭐⭐ |
| 方案C | WPF | C# | 原生Windows、性能好 | 仅Windows、UI定制复杂 | ⭐⭐⭐ |
| 方案D | .NET MAUI | C# | 跨平台 | 生态较新、文档少 | ⭐⭐ |

**推荐方案A - Electron**：
- 前端开发者友好，Markdown解析库丰富
- UI框架成熟（React/Vue + TailwindCSS）
- 打包成Windows安装包简单

---

## 二、系统架构

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                    升本通 (Electron)                      │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   渲染进程   │  │   渲染进程   │  │   渲染进程   │     │
│  │  (学习页面)  │  │  (练习页面)  │  │  (设置页面)  │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
├─────────────────────────────────────────────────────────┤
│                    主进程 (Main Process)                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │  MD文件解析  │  │  数据存储    │  │  窗口管理    │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
├─────────────────────────────────────────────────────────┤
│                    本地文件系统                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │  C语言/*.md  │  │ 数据结构/*.md│  │  自定义科目   │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
└─────────────────────────────────────────────────────────┘
```

### 2.2 目录结构

```
shengben-tong/
├── package.json
├── electron/
│   ├── main.js              # 主进程入口
│   ├── preload.js           # 预加载脚本
│   └── ipc-handlers.js      # IPC通信处理
├── src/
│   ├── index.html
│   ├── main.js              # 渲染进程入口
│   ├── styles/
│   │   └── global.css       # 全局样式
│   ├── components/
│   │   ├── Sidebar.js       # 侧边栏组件
│   │   ├── ChapterList.js   # 章节列表
│   │   ├── KnowledgeView.js # 知识点展示
│   │   ├── QuizView.js      # 练习题界面
│   │   ├── ProgressTracker.js # 进度追踪
│   │   └── SubjectManager.js # 科目管理
│   ├── utils/
│   │   ├── mdParser.js      # MD文件解析器
│   │   ├── questionParser.js # 题目解析器
│   │   └── storage.js       # 本地存储
│   └── data/
│       └── subjects.json    # 科目配置
├── assets/
│   └── icons/
├── build/
│   └── installer.nsi        # NSIS安装脚本
└── dist/                    # 打包输出
```

---

## 三、核心功能模块

### 3.1 科目管理模块

#### 功能描述
- 内置C语言和数据结构两个科目
- 支持导入新的MD文件科目
- 科目切换功能

#### 数据结构
```json
// subjects.json
{
  "subjects": [
    {
      "id": "c-language",
      "name": "C语言程序设计",
      "icon": "📝",
      "path": "./data/C语言",
      "chapters": [
        {
          "id": "ch01",
          "name": "01-程序设计与C语言基础",
          "knowledgeFile": "知识点总结.md",
          "exerciseFile": "练习题.md",
          "progress": 0
        }
      ]
    },
    {
      "id": "data-structure",
      "name": "数据结构",
      "icon": "🌲",
      "path": "./data/数据结构",
      "chapters": [...]
    }
  ]
}
```

#### 导入新科目流程
```
用户点击"导入科目" 
    ↓
选择MD文件夹（包含知识点总结.md和练习题.md）
    ↓
系统验证文件格式
    ↓
自动解析章节结构
    ↓
添加到科目列表
    ↓
更新subjects.json
```

### 3.2 MD文件解析模块

#### 支持的MD格式
```markdown
# 章节标题

## 核心知识点

### 1. 知识点标题
- 要点1
- 要点2

| 表格标题 |
|----------|
| 内容     |

## 易错点

1. 易错点1
2. 易错点2

---

## 一、单选题

1. 题目内容
   A. 选项A
   B. 选项B
   C. 选项C
   D. 选项D
**【答案】X**
**【讲解】** 讲解内容

## 二、判断题

1. 题目内容()
**【答案】√**
**【讲解】** 讲解内容

## 三、填空题

1. 题目内容______
**【答案】** 答案内容
**【讲解】** 讲解内容
```

#### 解析器实现
```javascript
// mdParser.js
class MDParser {
  // 解析知识点文件
  static parseKnowledge(content) {
    const sections = [];
    const lines = content.split('\n');
    
    for (const line of lines) {
      if (line.startsWith('# ')) {
        // 一级标题 - 章节名
        sections.push({ type: 'title', content: line.slice(2) });
      } else if (line.startsWith('## ')) {
        // 二级标题 - 知识模块
        sections.push({ type: 'module', content: line.slice(3) });
      } else if (line.startsWith('### ')) {
        // 三级标题 - 知识点
        sections.push({ type: 'point', content: line.slice(4) });
      } else if (line.startsWith('| ')) {
        // 表格行
        sections.push({ type: 'table-row', content: line });
      } else if (line.startsWith('- ')) {
        // 列表项
        sections.push({ type: 'list-item', content: line.slice(2) });
      }
    }
    
    return sections;
  }
  
  // 解析练习题文件
  static parseExercises(content) {
    const questions = [];
    const sections = content.split(/\n(?=## )/);
    
    for (const section of sections) {
      if (section.includes('单选题')) {
        questions.push(...this.parseMultipleChoice(section));
      } else if (section.includes('判断题')) {
        questions.push(...this.parseTrueFalse(section));
      } else if (section.includes('填空题')) {
        questions.push(...this.parseFillBlank(section));
      }
    }
    
    return questions;
  }
  
  // 解析单选题
  static parseMultipleChoice(section) {
    const questions = [];
    const regex = /(\d+)\.\s+(.+?)(?=\n\s+[A-D]\.)/gs;
    
    let match;
    while ((match = regex.exec(section)) !== null) {
      const question = {
        type: 'choice',
        number: parseInt(match[1]),
        content: match[2].trim(),
        options: this.extractOptions(section, match.index),
        answer: this.extractAnswer(section, match.index),
        explanation: this.extractExplanation(section, match.index)
      };
      questions.push(question);
    }
    
    return questions;
  }
}
```

### 3.3 学习流程模块

#### 学习模式设计
```
┌─────────────────────────────────────────────────────────┐
│                     学习流程                              │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ 选择章节  │ → │ 学习知识  │ → │ 做题巩固  │          │
│  └──────────┘    └──────────┘    └──────────┘          │
│       ↓               ↓               ↓                  │
│  显示章节列表    展示知识点      显示练习题               │
│  显示学习进度    支持收藏/标记   实时反馈答案             │
│                  支持搜索        显示讲解                 │
│                                  记录错题                │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

#### 页面布局（百词斩风格）
```
┌─────────────────────────────────────────────────────────┐
│  📚 升本通                           [设置] [导入科目]   │
├─────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────────────────────────────────┐ │
│  │ C语言     │  │                                      │ │
│  │ ──────── │  │     第一章 程序设计与C语言基础         │ │
│  │ ☑ 01基础  │  │                                      │ │
│  │ ☑ 02存储  │  │     ═══════════════════════════════  │ │
│  │ ☐ 03顺序  │  │                                      │ │
│  │ ☐ 04选择  │  │     1. C语言是哪种类型的程序设计语言？  │ │
│  │ ☐ 05循环  │  │                                      │ │
│  │ ...       │  │     ○ A. 面向对象                     │ │
│  │           │  │     ● B. 面向过程                     │ │
│  │ 数据结构  │  │     ○ C. 函数式                       │ │
│  │ ──────── │  │     ○ D. 逻辑式                       │ │
│  │ ☐ 01绪论  │  │                                      │ │
│  │ ☐ 02线性  │  │     ┌──────────────────────────────┐ │ │
│  │ ...       │  │     │ ✅ 正确！                      │ │ │
│  │           │  │     │                              │ │ │
│  │           │  │     │ C语言是面向过程的程序设计语言， │ │ │
│  │           │  │     │ 它通过函数来组织程序逻辑。      │ │ │
│  │           │  │     └──────────────────────────────┘ │ │
│  │           │  │                                      │ │
│  │           │  │     [上一题]  1/25  [下一题]          │ │
│  └──────────┘  └──────────────────────────────────────┘ │
│                                                          │
│  ┌──────────────────────────────────────────────────────┐│
│  │ 进度: ████████████░░░░░░░░ 60%  错题: 3  收藏: 5    ││
│  └──────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### 3.4 练习题模块

#### 题型支持
| 题型 | 展示方式 | 交互方式 |
|------|----------|----------|
| 单选题 | 圆形单选按钮 | 点击选择，即时反馈 |
| 判断题 | 对错按钮 | 点击选择，即时反馈 |
| 填空题 | 输入框 | 输入答案，点击提交 |
| 简答题 | 文本区域 | 输入答案，参考对比 |

#### 答题流程
```
用户选择答案
    ↓
即时判断对错
    ↓
┌─────────────────────────────────────┐
│ 答对了！                            │
│ ✅ 正确答案: B                      │
│                                     │
│ 【讲解】                            │
│ C语言是面向过程的程序设计语言...     │
│                                     │
│ [收藏] [下一题] [查看知识点]        │
└─────────────────────────────────────┘
    ↓
记录学习进度
    ↓
更新错题本（如果答错）
```

### 3.5 进度追踪模块

#### 数据存储结构
```javascript
// 用户进度数据
const userProgress = {
  userId: "default",
  subjects: {
    "c-language": {
      chapters: {
        "ch01": {
          knowledgeLearned: true,    // 是否学习了知识点
          exercisesCompleted: 15,    // 已完成题目数
          totalExercises: 25,        // 总题目数
          correctCount: 12,          // 答对数
          wrongQuestions: [2, 5, 8], // 错题题号
          favoriteQuestions: [1, 3], // 收藏题号
          lastStudyTime: "2026-08-23T10:30:00"
        },
        "ch02": { ... }
      },
      overallProgress: 45           // 整体进度百分比
    },
    "data-structure": { ... }
  },
  statistics: {
    totalStudyTime: 3600,           // 总学习时间（秒）
    totalQuestions: 150,             // 总做题数
    totalCorrect: 120,              // 总答对数
    streakDays: 5                   // 连续学习天数
  }
};
```

#### 进度展示
- 章节完成度百分比
- 知识点学习状态（已学/未学）
- 练习题完成进度条
- 错题本统计
- 收藏夹管理

---

## 四、UI设计规范

### 4.1 设计风格
- **主色调**: #4A90D9 (蓝色) + #FFFFFF (白色)
- **辅助色**: #52C41A (绿色-正确) + #FF4D4F (红色-错误)
- **字体**: 微软雅黑 / 思源黑体
- **圆角**: 8px
- **阴影**: 轻微阴影，增加层次感

### 4.2 组件库
使用 **TailwindCSS** + 自定义组件：

```css
/* 全局样式 */
:root {
  --primary: #4A90D9;
  --success: #52C41A;
  --error: #FF4D4F;
  --background: #F5F7FA;
  --card-bg: #FFFFFF;
  --text-primary: #333333;
  --text-secondary: #666666;
}

/* 按钮样式 */
.btn {
  @apply px-4 py-2 rounded-lg font-medium transition-all duration-200;
}

.btn-primary {
  @apply bg-blue-500 text-white hover:bg-blue-600;
}

.btn-success {
  @apply bg-green-500 text-white hover:bg-green-600;
}

/* 卡片样式 */
.card {
  @apply bg-white rounded-lg shadow-md p-4;
}

/* 选项样式 */
.option {
  @apply border-2 border-gray-200 rounded-lg p-3 cursor-pointer transition-all;
}

.option:hover {
  @apply border-blue-400 bg-blue-50;
}

.option.selected {
  @apply border-blue-500 bg-blue-100;
}

.option.correct {
  @apply border-green-500 bg-green-100;
}

.option.wrong {
  @apply border-red-500 bg-red-100;
}
```

### 4.3 响应式布局
- 最小窗口尺寸: 800x600
- 侧边栏宽度: 240px (可折叠)
- 内容区域: 自适应
- 移动端适配（未来扩展）

---

## 五、技术实现细节

### 5.1 Electron主进程

```javascript
// main.js
const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const fs = require('fs');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  
  mainWindow.loadFile('src/index.html');
}

// IPC处理 - 导入科目
ipcMain.handle('import-subject', async (event) => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory'],
    title: '选择科目文件夹'
  });
  
  if (!result.canceled) {
    const folderPath = result.filePaths[0];
    return processSubjectFolder(folderPath);
  }
});

// IPC处理 - 读取MD文件
ipcMain.handle('read-md-file', async (event, filePath) => {
  const content = fs.readFileSync(filePath, 'utf-8');
  return content;
});
```

### 5.2 预加载脚本

```javascript
// preload.js
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // 科目管理
  importSubject: () => ipcRenderer.invoke('import-subject'),
  getSubjects: () => ipcRenderer.invoke('get-subjects'),
  
  // 文件操作
  readMdFile: (path) => ipcRenderer.invoke('read-md-file', path),
  
  // 数据存储
  saveProgress: (data) => ipcRenderer.invoke('save-progress', data),
  loadProgress: () => ipcRenderer.invoke('load-progress'),
  
  // 错题本
  getWrongQuestions: () => ipcRenderer.invoke('get-wrong-questions'),
  addWrongQuestion: (question) => ipcRenderer.invoke('add-wrong-question', question)
});
```

### 5.3 MD解析器

```javascript
// utils/mdParser.js
export class KnowledgeParser {
  static parse(content) {
    const sections = [];
    const lines = content.split('\n');
    let currentSection = null;
    
    for (const line of lines) {
      const trimmed = line.trim();
      
      if (trimmed.startsWith('# ')) {
        // 章节标题
        currentSection = {
          type: 'title',
          content: trimmed.slice(2),
          children: []
        };
        sections.push(currentSection);
      } else if (trimmed.startsWith('## ')) {
        // 模块标题
        currentSection = {
          type: 'module',
          content: trimmed.slice(3),
          children: []
        };
        sections.push(currentSection);
      } else if (trimmed.startsWith('### ')) {
        // 知识点
        sections.push({
          type: 'point',
          content: trimmed.slice(4)
        });
      } else if (trimmed.startsWith('- ')) {
        // 列表项
        sections.push({
          type: 'list-item',
          content: trimmed.slice(2)
        });
      } else if (trimmed.startsWith('| ')) {
        // 表格行
        sections.push({
          type: 'table-row',
          content: trimmed
        });
      } else if (trimmed === '---') {
        // 分隔线
        sections.push({ type: 'separator' });
      }
    }
    
    return sections;
  }
}

export class ExerciseParser {
  static parse(content) {
    const questions = [];
    const sections = content.split(/\n(?=## )/);
    
    for (const section of sections) {
      if (section.includes('单选题')) {
        questions.push(...this.parseChoiceQuestions(section));
      } else if (section.includes('判断题')) {
        questions.push(...this.parseTrueFalseQuestions(section));
      } else if (section.includes('填空题')) {
        questions.push(...this.parseFillBlankQuestions(section));
      }
    }
    
    return questions;
  }
  
  static parseChoiceQuestions(section) {
    const questions = [];
    const lines = section.split('\n');
    let currentQuestion = null;
    
    for (const line of lines) {
      const trimmed = line.trim();
      
      // 匹配题目: "1. 题目内容"
      const questionMatch = trimmed.match(/^(\d+)\.\s+(.+)/);
      if (questionMatch) {
        if (currentQuestion) {
          questions.push(currentQuestion);
        }
        currentQuestion = {
          type: 'choice',
          number: parseInt(questionMatch[1]),
          content: questionMatch[2],
          options: [],
          answer: '',
          explanation: ''
        };
        continue;
      }
      
      // 匹配选项: "A. 选项内容"
      const optionMatch = trimmed.match(/^([A-D])\.\s+(.+)/);
      if (optionMatch && currentQuestion) {
        currentQuestion.options.push({
          label: optionMatch[1],
          content: optionMatch[2]
        });
        continue;
      }
      
      // 匹配答案: "【答案】X"
      const answerMatch = trimmed.match(/【答案】\s*([A-D])/);
      if (answerMatch && currentQuestion) {
        currentQuestion.answer = answerMatch[1];
        continue;
      }
      
      // 匹配讲解: "【讲解】..."
      const explanationMatch = trimmed.match(/【讲解】\s*(.+)/);
      if (explanationMatch && currentQuestion) {
        currentQuestion.explanation = explanationMatch[1];
        continue;
      }
    }
    
    if (currentQuestion) {
      questions.push(currentQuestion);
    }
    
    return questions;
  }
}
```

---

## 六、打包与分发

### 6.1 打包配置

```json
// package.json
{
  "name": "shengben-tong",
  "version": "1.0.0",
  "description": "广东专升本学习助手",
  "main": "electron/main.js",
  "scripts": {
    "start": "electron .",
    "dev": "concurrently \"vite\" \"wait-on http://localhost:5173 && electron .\"",
    "build": "vite build",
    "package": "electron-builder --win",
    "package:dir": "electron-builder --win --dir"
  },
  "build": {
    "appId": "com.shengben.tong",
    "productName": "升本通",
    "directories": {
      "output": "dist"
    },
    "files": [
      "electron/**/*",
      "src/**/*",
      "dist/**/*"
    ],
    "win": {
      "target": [
        {
          "target": "nsis",
          "arch": ["x64"]
        }
      ],
      "icon": "assets/icons/icon.ico"
    },
    "nsis": {
      "oneClick": false,
      "allowToChangeInstallationDirectory": true,
      "installerIcon": "assets/icons/icon.ico",
      "uninstallerIcon": "assets/icons/icon.ico"
    }
  },
  "dependencies": {
    "marked": "^9.0.0"
  },
  "devDependencies": {
    "electron": "^28.0.0",
    "electron-builder": "^24.0.0",
    "vite": "^5.0.0",
    "tailwindcss": "^3.3.0"
  }
}
```

### 6.2 安装包制作

使用 **electron-builder** 打包NSIS安装包：

```bash
# 安装依赖
npm install

# 开发模式
npm run dev

# 打包Windows安装包
npm run package
```

生成文件：
- `dist/升本通 Setup 1.0.0.exe` - NSIS安装包
- `dist/win-unpacked/` - 免安装版本

---

## 七、开发计划

### 7.1 阶段一：基础框架（1-2周）
- [ ] 搭建Electron项目框架
- [ ] 实现基础UI布局（侧边栏+内容区）
- [ ] 实现MD文件解析器
- [ ] 实现科目切换功能

### 7.2 阶段二：学习功能（2-3周）
- [ ] 实现知识点展示页面
- [ ] 实现练习题界面（单选/判断/填空）
- [ ] 实现答题反馈和讲解展示
- [ ] 实现进度追踪

### 7.3 阶段三：增强功能（1-2周）
- [ ] 实现错题本功能
- [ ] 实现收藏夹功能
- [ ] 实现搜索功能
- [ ] 实现学习统计

### 7.4 阶段四：打包发布（1周）
- [ ] 优化性能
- [ ] 制作安装包
- [ ] 编写用户手册
- [ ] 发布v1.0版本

---

## 八、扩展性设计

### 8.1 科目扩展
用户可通过导入MD文件夹添加新科目：

```
导入的文件夹结构：
新科目/
├── 01-章节1/
│   ├── 知识点总结.md
│   └── 练习题.md
├── 02-章节2/
│   ├── 知识点总结.md
│   └── 练习题.md
└── ...
```

### 8.2 题型扩展
支持自定义题型：
- 简答题
- 编程题
- 分析题

### 8.3 数据同步（未来）
- 云端同步学习进度
- 多设备同步
- 学习数据导出

---

## 九、参考资源

### 9.1 依赖库
| 库名 | 用途 | 版本 |
|------|------|------|
| Electron | 桌面应用框架 | ^28.0.0 |
| Vite | 前端构建工具 | ^5.0.0 |
| TailwindCSS | UI样式框架 | ^3.3.0 |
| marked | Markdown解析 | ^9.0.0 |
| electron-builder | 打包工具 | ^24.0.0 |

### 9.2 学习资源
- [Electron官方文档](https://www.electronjs.org/docs)
- [TailwindCSS文档](https://tailwindcss.com/docs)
- [marked库文档](https://marked.js.org/)

---

*文档版本: v1.0*
*创建日期: 2026年8月23日*
*作者: 升本通开发团队*
