@echo off
rem Launch from source: godot --path .   (extra args are forwarded, e.g. run.bat -- --debug)
cd /d "%~dp0"
if "%GODOT%"=="" set GODOT=godot
%GODOT% --path . %*
