@echo off
echo Fixed Windows Build (No Web Dependencies)
echo ==========================================

echo.
echo Cleaning and getting dependencies...
flutter clean
flutter pub get

echo.
echo Building Windows application (Fixed version)...
flutter build windows --debug --target=lib/main_windows_light.dart

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ✅ BUILD SUCCESSFUL!
    echo 📁 Location: build\windows\x64\runner\Debug\
    echo 🚀 Run: build\windows\x64\runner\Debug\tra_list.exe
    echo.
    echo This version uses local file storage instead of web localStorage
    echo Storage file: tra_receipts.json
) else (
    echo.
    echo ❌ BUILD FAILED!
    echo Check the error messages above
)

echo.
pause