@echo off
rem Builds standalone executables for Windows, macOS and Linux (spec 25).
rem Needs godot.exe on PATH (or set GODOT) and the matching export templates installed.
setlocal
cd /d "%~dp0"
if "%GODOT%"=="" set GODOT=godot
where %GODOT% >nul 2>nul
if errorlevel 1 (
  echo ERROR: godot not found on PATH ^(set GODOT=C:\path\to\godot.exe^)
  exit /b 1
)
mkdir build\windows 2>nul
mkdir build\macos 2>nul
mkdir build\linux 2>nul
%GODOT% --headless --path . --import >nul 2>nul
set FAIL=0
echo ==^> exporting Windows
%GODOT% --headless --path . --export-release "Windows" build/windows/MedievalMadness.exe
if errorlevel 1 set FAIL=1
echo ==^> exporting macOS
%GODOT% --headless --path . --export-release "macOS" build/macos/MedievalMadness.zip
if errorlevel 1 set FAIL=1
echo ==^> exporting Linux
%GODOT% --headless --path . --export-release "Linux" build/linux/MedievalMadness.x86_64
if errorlevel 1 set FAIL=1
echo.
echo Sizes:
for %%F in (build\windows\MedievalMadness.exe build\macos\MedievalMadness.zip build\linux\MedievalMadness.x86_64) do (
  if exist %%F ( echo   %%F  %%~zF bytes ) else ( echo   %%F  MISSING & set FAIL=1 )
)
exit /b %FAIL%
