@echo off
rem Самый надёжный способ запуска на Windows: двойной щелчок по этому файлу.
rem Политика выполнения PowerShell обходится ключом, окно не закрывается.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1"
echo.
echo Установщик завершил работу.
pause
