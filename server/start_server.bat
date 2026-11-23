@echo off
REM Startet den MInfy-Server ohne Grafik (Windows).
REM Passe den Pfad zu deiner Godot-Datei an:
set GODOT=C:\Godot\Godot_v4.4.1-stable_win64_console.exe
cd /d "%~dp0\.."
"%GODOT%" --headless --xr-mode off --path . -- --server --port=7777
pause
