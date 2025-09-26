@echo off
echo Super Fast Windows Build (No Firebase)
echo ======================================

echo.
echo This build excludes Firebase for maximum speed
echo Estimated time: 1-2 minutes
echo.

flutter clean
flutter pub get

echo.
echo Building lightweight Windows app...
flutter build windows --debug --target=lib/main_windows_light.dart --dart-define=EXCLUDE_FIREBASE=true

echo.
echo ✅ Super fast build completed!
echo 📁 Location: build\windows\x64\runner\Debug\
echo 🚀 Run: build\windows\x64\runner\Debug\tra_list.exe
echo.
echo Note: This version works offline with local storage only.
echo.
pause