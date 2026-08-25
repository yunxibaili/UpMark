@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ========================================
echo   升本通 服务端启动中...
echo ========================================
if not exist venv (
    python -m venv venv
)
call venv\Scripts\activate.bat
python -m pip install -r requirements.txt -q
echo.
if exist shengbentong.db (
    python -c "import shutil,datetime,os,glob; base=os.path.join(os.environ['LOCALAPPDATA'],'UpMark'); db=os.path.join(base,'shengbentong.db'); bk=os.path.join(base,'backup'); os.makedirs(bk,exist_ok=True); ts=datetime.datetime.now().strftime('%%Y%%m%%d_%%H%%M%%S'); shutil.copy2(db, os.path.join(bk,'upmark_'+ts+'.db')) if os.path.exists(db) else None; olds=sorted(glob.glob(os.path.join(bk,'upmark_*.db'))); [os.remove(x) for x in olds[:-10]]" 2>nul && echo [backup] 题库已备份到 %%LOCALAPPDATA%%\UpMark\backup\ （保留最近10份） || echo [backup] 备份失败（不影响启动）
)
echo 启动服务: http://本机IP:8000   管理页: http://localhost:8000/api/admin/page
echo 手机App绑定方式: 输入本机局域网IP + 端口8000
echo.
uvicorn app.main:app --host 0.0.0.0 --port 8000
pause
