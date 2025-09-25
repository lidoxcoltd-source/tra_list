@echo off
echo Building TRA Receipt Management System...
flutter build web --web-renderer html --dart-define=FLUTTER_WEB_USE_SKIA=false

echo.
echo Building TRA Verification System...
copy lib\main_verify.dart lib\main.dart.backup
copy lib\main.dart lib\main_full.dart
copy lib\main_verify.dart lib\main.dart

flutter build web --web-renderer html --dart-define=FLUTTER_WEB_USE_SKIA=false --output web_verify

echo.
echo Restoring original main.dart...
copy lib\main_full.dart lib\main.dart
del lib\main.dart.backup
del lib\main_full.dart

echo.
echo Copying verification build to web_verify directory...
if not exist "build\web_verify" mkdir "build\web_verify"
xcopy "build\web\*" "build\web_verify\" /E /Y

echo.
echo Build complete!
echo - Full system: build/web
echo - Verification only: build/web_verify