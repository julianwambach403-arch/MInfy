extends RefCounted
## ===================== EINSTELLUNGEN =====================
## Trage hier die Adresse deines Servers ein, BEVOR du die APK
## für die Quest exportierst. Im Spiel-Menü kannst du dann
## zwischen diesen Servern wählen.
##
## Format: [Anzeigename, Adresse (IP oder Domain), Port]
const SERVERS := [
	["Zuhause (LAN)", "192.168.178.20", 7777],
	["Internet", "mein-server.duckdns.org", 7777],
	["Dieser PC", "127.0.0.1", 7777],
]

## Standard-Port des Servers (UDP).
const SERVER_PORT := 7777

## Namen, die im Startmenü zur Auswahl stehen.
## Jeder Name hat seinen eigenen Spielstand auf dem Server.
const NAMES := ["Spieler 1", "Spieler 2", "Held", "Heldin", "Abenteurer", "Magierin"]

## ===================== CLAUDE (nur Server) =====================
## Eigene Fähigkeiten für Erfolge werden von der Claude Code CLI programmiert.
## Voraussetzung auf dem Server-Rechner: `npm install -g @anthropic-ai/claude-code`
## und einmal `claude` starten und mit deinem Claude-Abo anmelden (kein API-Schlüssel nötig).
## Ist Claude nicht verfügbar, bekommt man eine einfache Ersatz-Fähigkeit.
const CLAUDE_ENABLED := true
## Befehl bzw. vollständiger Pfad zur Claude Code CLI.
const CLAUDE_COMMAND := "claude"
## Optional ein bestimmtes Modell, z. B. "sonnet" oder "opus". Leer = Standard.
const CLAUDE_MODEL := ""
