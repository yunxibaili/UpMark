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
echo 启动服务: http://本机IP:8000   管理页: http://localhost:8000/api/admin/page
echo 手机App绑定方式: 输入本机局域网IP + 端口8000
echo.
uvicorn app.main:app --host 0.0.0.0 --port 8000
pause
