@echo off
REM Cinema Audio Luxe - iOS Build Preparation (Windows)

echo.
echo ========================================
echo Cinema Audio Luxe - iOS Build Prep
echo ========================================
echo.

REM Check Flutter
flutter --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter not found. Please install Flutter SDK
    pause
    exit /b 1
)

echo [OK] Flutter found

REM Step 1: Clean
echo.
echo [STEP 1] Cleaning project...
call flutter clean
if exist ios\Pods rmdir /s /q ios\Pods
if exist ios\Podfile.lock del ios\Podfile.lock
if exist ios\.symlinks rmdir /s /q ios\.symlinks

REM Step 2: Get dependencies
echo.
echo [STEP 2] Getting Flutter dependencies...
call flutter pub get

REM Step 3: Verify files
echo.
echo [STEP 3] Verifying iOS configuration...
if not exist ios\Runner\AppDelegate.swift (
    echo [ERROR] AppDelegate.swift not found
    pause
    exit /b 1
)
if not exist ios\Runner\Info.plist (
    echo [ERROR] Info.plist not found
    pause
    exit /b 1
)

echo [OK] All files verified

REM Step 4: Summary
echo.
echo ========================================
echo [SUCCESS] Project ready for Codemagic!
echo ========================================
echo.
echo Next steps:
echo 1. Push to GitHub: git add . && git commit -m "Cinema Audio Luxe iOS" && git push
echo 2. Go to https://codemagic.io
echo 3. Connect your GitHub repo
echo 4. Build will start automatically
echo 5. Download .ipa from email
echo.
pause
