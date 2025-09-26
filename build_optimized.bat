@echo off
echo Flutter Windows Build Optimizer
echo ================================

echo.
echo Cleaning previous builds...
flutter clean

echo.
echo Getting dependencies...
flutter pub get

echo.
echo Choose build type:
echo 1. Debug (Fast build, ~2-3 minutes)
echo 2. Profile (Medium build, ~5-7 minutes) 
echo 3. Release (Full build, ~10-15 minutes)
echo.

set /p choice="Enter choice (1-3): "

if "%choice%"=="1" (
    echo Building Windows Debug version...
    flutter build windows --debug --target=lib/main_windows.dart
    echo Debug build completed!
    echo Run: build\windows\x64\runner\Debug\tra_list.exe
) else if "%choice%"=="2" (
    echo Building Windows Profile version...
    flutter build windows --profile --target=lib/main_windows.dart
    echo Profile build completed!
    echo Run: build\windows\x64\runner\Profile\tra_list.exe
) else if "%choice%"=="3" (
    echo Building Windows Release version...
    flutter build windows --release --target=lib/main_windows.dart
    echo Release build completed!
    echo Run: build\windows\x64\runner\Release\tra_list.exe
) else (
    echo Building Debug by default...
    flutter build windows --debug --target=lib/main_windows.dart
    echo Debug build completed!
)

echo.
echo Build finished! Check the build folder.
pause