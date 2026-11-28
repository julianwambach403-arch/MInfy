#!/usr/bin/env sh
# MInfy Lounge starten (Linux/macOS). Node.js 18+ muss installiert sein.
cd "$(dirname "$0")" || exit 1
[ -d node_modules ] || npm install --omit=dev
exec node server.js "$@"
