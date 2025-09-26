@echo off
echo Building Flutter Windows App (Optimized)...

REM Clean previous builds
flutter clean

REM Get dependencies
flutter pub get

REM Build Windows app with optimizations
flutter build windows --release --dart-define=FLUTTER_WEB_USE_SKIA=true --tree-shake-icons

echo.
echo Build completed! 
echo Location: build\windows\x64\runner\Release\
echo.
pause