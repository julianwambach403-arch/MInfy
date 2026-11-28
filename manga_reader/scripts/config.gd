extends RefCounted
## Einstellungen des Manga-Lesers. Hier anpassen!

## Ordner, in denen nach Manga gesucht wird (auf der Quest und am PC).
## Jeder Unterordner = eine Serie. Darin: Kapitel als .cbz/.zip-Dateien oder
## als Unterordner mit Bildern (jpg, png, webp). Eine einzelne .cbz direkt im
## Ordner wird als Serie mit einem Kapitel angezeigt.
##   Quest: /sdcard/Download/Manga  (per USB oder SideQuest hineinkopieren)
##          /sdcard/Android/data/com.minfy.mangavr/files/Manga  (geht immer, ohne Berechtigung)
const LOCAL_DIRS := [
	"/storage/emulated/0/Download/Manga",
	"/storage/emulated/0/Manga",
	"/storage/emulated/0/Android/data/com.minfy.mangavr/files/Manga",
	"user://Manga",
	"~/Manga",
]

## Optional: eigener Manga-Server (Komga, https://komga.org – kostenlos, selbst gehostet).
## Leer lassen, wenn du keinen hast. Beispiel: "http://192.168.178.20:25600"
const KOMGA_URL := ""
const KOMGA_USER := ""
const KOMGA_PASSWORD := ""

## Leserichtung: true = von rechts nach links (japanischer Manga), false = links nach rechts.
const RIGHT_TO_LEFT := true

## Seiten werden auf diese Höhe (Pixel) verkleinert, wenn sie größer sind.
## 2048 ist auf der Quest 3 sehr scharf und braucht pro Seite ~10 MB Grafikspeicher.
const MAX_PAGE_HEIGHT := 2048

## Wie viele Doppelseiten vor/nach der aktuellen vorgeladen werden.
const PRELOAD_SPREADS := 3

## Renderauflösung (1.0 = Standard der Quest). Höher = schärfere Schrift, mehr GPU-Last.
const RENDER_SCALE := 1.2

## Durch die Luft wischen (offene Hand) blättert um.
const SWIPE_TO_TURN := true

## Mit Passthrough (dein echtes Zimmer) starten statt im virtuellen Lesezimmer.
const START_IN_PASSTHROUGH := false
