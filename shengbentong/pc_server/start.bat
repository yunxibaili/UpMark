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
    python -c "import shutil,datetime,os,glob; os.makedirs('backup',exist_ok=True); ts=datetime.datetime.now().strftime('%%Y%%m%%d_%%H%%M%%S'); shutil.copy2('shengbentong.db', os.path.join('backup','upmark_'+ts+'.db')); olds=sorted(glob.glob('backup/upmark_*.db')); [os.remove(x) for x in olds[:-10]]" 2>nul && echo [backup] 题库已备份到 backup\ （保留最近10份） || echo [backup] 备份失败（不影响启动）
)
echo 启动服务: http://本机IP:8000   管理页: http://localhost:8000/api/admin/page
echo 手机App绑定方式: 输入本机局域网IP + 端口8000
echo.
uvicorn app.main:app --host 0.0.0.0 --port 8000
pause
