@echo off
echo Quick Windows Debug Build...

REM Build debug version (much faster)
flutter build windows --debug

echo.
echo Debug build completed! 
echo Location: build\windows\x64\runner\Debug\
echo.
echo To run: build\windows\x64\runner\Debug\tra_list.exe
echo.
pause