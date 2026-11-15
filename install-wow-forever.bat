@echo off
setlocal

REM Set this to your active WoW Forever installation path.
set "WOW_FOREVER_PATH=C:\Games\WoWForever"

set "REPO_DIR=%~dp0"
if "%REPO_DIR:~-1%"=="\" set "REPO_DIR=%REPO_DIR:~0,-1%"

set "SOURCE_ADDON_DIR=%REPO_DIR%\addons\Krust"
set "TARGET_ADDONS_DIR=%WOW_FOREVER_PATH%\Interface\AddOns"
set "TARGET_ADDON_DIR=%TARGET_ADDONS_DIR%\Krust"

if not exist "%SOURCE_ADDON_DIR%\Krust.lua" (
    echo [ERROR] Could not find addon source at "%SOURCE_ADDON_DIR%".
    exit /b 1
)

if not exist "%TARGET_ADDONS_DIR%" (
    echo [ERROR] Could not find WoW AddOns folder at "%TARGET_ADDONS_DIR%".
    echo [ERROR] Update WOW_FOREVER_PATH at the top of this file.
    exit /b 1
)

if exist "%TARGET_ADDON_DIR%" (
    echo Removing existing Krust addon from "%TARGET_ADDON_DIR%"...
    rmdir /S /Q "%TARGET_ADDON_DIR%"
    if errorlevel 1 (
        echo [ERROR] Failed to remove existing addon directory.
        exit /b 1
    )
)

echo Installing Krust addon to "%TARGET_ADDON_DIR%"...
xcopy "%SOURCE_ADDON_DIR%" "%TARGET_ADDON_DIR%\" /E /I /Y >nul
if errorlevel 2 (
    echo [ERROR] Copy failed.
    exit /b 1
)

echo [OK] Krust installed successfully.
exit /b 0
