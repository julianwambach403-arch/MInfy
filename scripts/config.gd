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
