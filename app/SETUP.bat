@echo off
chcp 65001 >nul
cd /d "%~dp0"
title WOLFICH Market - установка
echo.
echo   WOLFICH Market - установка / обновление
echo.
taskkill /IM WOLFICH-Market.exe /F >nul 2>&1
timeout /t 2 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $d=(Get-Location).Path; $exe=Join-Path $d 'WOLFICH-Market.exe'; if (-not (Test-Path -LiteralPath $exe)) { if (-not (Test-Path -LiteralPath (Join-Path $d 'electron.exe'))) { Write-Host '  Скачиваю Electron с GitHub (около 110 МБ), пара минут...'; $z=Join-Path $d 'electron-download.zip'; Invoke-WebRequest -Uri 'https://github.com/electron/electron/releases/download/v33.4.11/electron-v33.4.11-win32-x64.zip' -OutFile $z -UseBasicParsing; Write-Host '  Распаковываю...'; Expand-Archive -LiteralPath $z -DestinationPath $d -Force; Remove-Item -LiteralPath $z -Force -ErrorAction SilentlyContinue }; Rename-Item -LiteralPath (Join-Path $d 'electron.exe') -NewName 'WOLFICH-Market.exe' } else { Write-Host '  Программа уже установлена - обновляю только её файлы.' }; Remove-Item -LiteralPath (Join-Path $d 'resources\default_app.asar') -Force -ErrorAction SilentlyContinue; $app=Join-Path $d 'resources\app'; New-Item -ItemType Directory -Force -Path $app | Out-Null; Get-ChildItem -LiteralPath (Join-Path $d 'program') | Copy-Item -Destination $app -Recurse -Force; $s=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'WOLFICH Market.lnk')); $s.TargetPath=$exe; $s.WorkingDirectory=$d; $s.IconLocation=(Join-Path $app 'icon.ico'); $s.Save()"
if errorlevel 1 (
  echo.
  echo   Не получилось. Проверьте интернет и запустите SETUP.bat ещё раз.
  pause
  exit /b 1
)
echo.
echo   Готово! Ярлык «WOLFICH Market» на рабочем столе. Запускаю программу...
start "" "%~dp0WOLFICH-Market.exe"
timeout /t 3 >nul
