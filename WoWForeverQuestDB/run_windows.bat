@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>&1
if not errorlevel 1 (
  py -3 build_db.py --out dist
  goto outcome
)
where python >nul 2>&1
if not errorlevel 1 (
  python build_db.py --out dist
  goto outcome
)
echo [ERROR] Python 3.9+ not found. Install Python from python.org.
pause
exit /b 1
:outcome
if errorlevel 1 (
  echo [ERROR] Database build failed. See error details above.
  pause
  exit /b 1
)
echo [OK] Database ready in dist\
start "" "%~dp0dist\quests_browser.html"
exit /b 0