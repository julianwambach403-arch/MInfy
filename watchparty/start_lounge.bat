@echo off
rem MInfy Lounge starten (Windows). Node.js 18+ muss installiert sein: https://nodejs.org
cd /d "%~dp0"
if not exist node_modules (
  echo Installiere einmalig die benoetigten Pakete ...
  call npm install --omit=dev
)
node server.js
pause
