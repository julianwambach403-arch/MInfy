#!/usr/bin/env bash
# Startet den MInfy-Server ohne Grafik.
# Voraussetzung: Godot 4.4+ ist installiert und als "godot" im PATH
# (oder Pfad unten per GODOT=/pfad/zu/godot angeben).
GODOT="${GODOT:-godot}"
PORT="${1:-7777}"
cd "$(dirname "$0")/.." || exit 1
exec "$GODOT" --headless --xr-mode off --path . -- --server --port="$PORT"
