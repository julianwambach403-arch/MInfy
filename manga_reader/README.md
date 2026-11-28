# MInfy Manga VR: Manga wie echte Bücher lesen (Meta Quest 3)

Ein Manga-Leser für die **Meta Quest 3** mit **Handtracking**. Dein Manga liegt als aufgeschlagenes
3D-Buch vor dir. Du blätterst die Seiten mit den Fingern um, hältst das Buch in den Händen und ziehst
es mit beiden Händen größer oder kleiner. Du liest in einem gemütlichen Lesezimmer oder per
Passthrough in deinem echten Zimmer.

- **Engine:** Godot 4.4 (wie das MMORPG im Hauptordner), läuft nativ als APK auf der Quest 3
- **Manga-Quellen:** deine eigenen Dateien (CBZ/ZIP oder Bilder-Ordner) und optional ein eigener
  [Komga](https://komga.org)-Server
- **Ohne Brille testbar:** am PC mit Maus und Tastatur

> **Zu „Manga Infinity“:** Die App lädt nichts direkt von Manga-Webseiten. Seiten wie diese bieten
> Manga meist ohne Lizenz der Verlage an. Ein Programm, das sie automatisch herunterlädt, würde ich
> deshalb nicht bauen, und es würde außerdem bei jeder Änderung der Seite kaputtgehen. Die App liest
> stattdessen **jeden Manga, den du als Datei hast**: gekaufte DRM-freie Manga (z. B. als CBZ),
> eigene Scans, Webcomics mit Download-Erlaubnis oder deine Komga-Bibliothek. Weitere Quellen lassen
> sich leicht ergänzen (siehe „Eigene Quelle hinzufügen“).

---

## So liest du

| Was | Handtracking | Controller | PC (Testmodus) |
|---|---|---|---|
| **Umblättern** | Seite mit **Daumen + Zeigefinger** am Rand greifen (Pinch) und rüberziehen. Loslassen nach der Mitte = umgeblättert, vorher = zurück | Trigger am Seitenrand drücken und ziehen, oder rechter Stick links/rechts | Seite mit der Maus ziehen, oder Pfeiltasten |
| **Schnell blättern** | Mit offener Hand über das Buch **wischen** | Stick | Pfeiltasten |
| **Buch festhalten** | **Faust** am Buchrand oder Rücken machen, das Buch folgt der Hand | Grip | (Taste R legt es zurück) |
| **Größer/kleiner** | Mit **beiden Händen** greifen und auseinanderziehen | beide Grips | Mausrad oder + / − |
| **Knöpfe** | mit dem Zeigefinger **antippen**, oder aus der Ferne zeigen + Pinch | zeigen + Trigger | klicken |
| **Menü** | **Linke Handfläche zum Gesicht drehen**, dann erscheint das Menü über der Hand | Knopf „Menü“ unter dem Buch | M |

**Leserichtung:** Standard ist japanisch, also **von rechts nach links**. Die erste Seite liegt rechts,
und zum Weiterlesen nimmst du die **linke** Seite und legst sie nach rechts um, wie bei einem echten
Manga-Band. Für Comics und Webtoons kannst du im Menü auf „links → rechts“ umstellen.

**Doppelseiten:** Bilder im Querformat (Doppelseiten im Scan) werden automatisch über beide Buchseiten
gelegt. Wenn Doppelseiten, die aus zwei Einzelbildern bestehen, verrutscht aussehen, hilft im Menü
„Doppelseiten versetzen“.

**Leiste unter dem Buch:** Bibliothek · « Kapitel · < · > · Kapitel » · − · + · Menü.
Am Ende eines Kapitels blätterst du einfach weiter, dann öffnet sich das nächste Kapitel.

**Menü:** Bibliothek · Buch zu mir (legt es wieder bequem vor dich) · Leserichtung ·
Doppelseiten versetzen · Echtes Zimmer (Passthrough) an/aus · Helligkeit.

Der **Lesefortschritt** wird pro Kapitel gespeichert. In der Kapitelliste steht „S. 12“ oder
„(gelesen)“, und **Weiterlesen** in der Bibliothek öffnet direkt die letzte Stelle.

---

## Manga auf die Quest bringen

Lege pro Serie einen Ordner an. Darin liegen die Kapitel als `.cbz`/`.zip` **oder** als Unterordner
mit Bildern (`jpg`, `png`, `webp`):

```
Manga/
  Meine Serie/
    Band 01.cbz
    Band 02.cbz
  Andere Serie/
    Kapitel 001/
      001.jpg
      002.jpg
    Kapitel 002/
      ...
  Einzelner Band.cbz        <- wird als eigene Serie angezeigt
```

Die Sortierung ist „natürlich“, also kommt Kapitel 2 vor Kapitel 10.

**Wohin auf der Quest?** Quest per USB-C an den PC anschließen (im Headset „Zugriff erlauben“) und
den Ordner `Manga` kopieren nach:

- `Interner Speicher/Download/Manga` (am einfachsten). Beim ersten Start fragt die App nach der
  Berechtigung für Dateien. Bitte erlauben (unter neuerem Android heißt sie „Zugriff auf alle Dateien“).
- oder ohne Berechtigung: `Interner Speicher/Android/data/com.minfy.mangavr/files/Manga`

Mit [SideQuest](https://sidequestvr.com) geht das Kopieren auch per Drag & Drop. Danach in der
Bibliothek auf **Neu laden** tippen.

Weitere Ordner trägst du in `scripts/config.gd` unter `LOCAL_DIRS` ein.

### Optional: Komga-Server (deine Bibliothek über WLAN)

[Komga](https://komga.org) ist ein kostenloser Manga- und Comic-Server für PC, NAS oder Raspberry Pi.
Damit musst du nichts auf die Quest kopieren. Trage in `scripts/config.gd` ein:

```gdscript
const KOMGA_URL := "http://192.168.178.20:25600"
const KOMGA_USER := "du@example.com"
const KOMGA_PASSWORD := "dein-passwort"
```

Die Serien vom Server erscheinen dann zusätzlich in der Bibliothek.

---

## Bauen und auf die Quest 3 installieren

Die Schritte sind dieselben wie beim MMORPG (siehe Haupt-README, Abschnitt „Einmalige Vorbereitung“):

1. **Godot 4.4.1** öffnen → *Importieren* → `manga_reader/project.godot` wählen.
2. *AssetLib* → **„Godot OpenXR Vendors“** installieren und unter *Projekteinstellungen → Plugins*
   aktivieren. Das Plugin wird für Handtracking und Passthrough auf der Quest gebraucht.
3. Android-Exportvorlagen, OpenJDK 17 und Android SDK einrichten, dann *Projekt →
   Android-Build-Vorlage installieren*.
4. *Projekt → Exportieren* → Vorlage **„Meta Quest 3“**. Unter *Meta XR Features* sind
   **Hand Tracking** und **Passthrough** bereits auf „Optional“ gestellt.
5. Quest im Entwicklermodus anschließen → **Remote Deploy** (Android-Symbol oben rechts) oder
   `build/MInfyManga.apk` mit SideQuest installieren.
6. In der Quest unter *App-Bibliothek → Unbekannte Quellen* „Manga VR“ starten.

**Handtracking einschalten:** Auf der Quest unter *Einstellungen → Bewegungsverfolgung →
Hand- und Körpertracking* aktivieren. Leg die Controller weg, dann schaltet die App automatisch auf
Hände um. Nimmst du sie wieder in die Hand, funktionieren sie sofort.

## Am PC testen (ohne Brille)

```bash
python3 tools/make_demo_manga.py ~/Manga      # kleiner, selbst gezeichneter Demo-Manga
godot --path manga_reader -- --desktop
```

Bedienung: Seite mit der Maus ziehen oder klicken, Pfeiltasten blättern, Mausrad = Größe,
mittlere Maustaste + Maus = umschauen, L = Bibliothek, M = Menü, R = Buch zurücklegen,
D = Leserichtung.

Automatischer Test (Bibliothek → Kapitel → Blättern mit simulierter Hand → nächstes Kapitel):

```bash
godot --path manga_reader -s res://test/run_test.gd -- --desktop
```

## Einstellungen (`scripts/config.gd`)

| Einstellung | Bedeutung |
|---|---|
| `LOCAL_DIRS` | Ordner, in denen nach Manga gesucht wird |
| `KOMGA_URL`, `KOMGA_USER`, `KOMGA_PASSWORD` | eigener Komga-Server (optional) |
| `RIGHT_TO_LEFT` | Leserichtung beim Start |
| `MAX_PAGE_HEIGHT` | maximale Seitenauflösung (2048 ist auf der Quest 3 sehr scharf) |
| `PRELOAD_SPREADS` | wie viele Doppelseiten im Voraus geladen werden |
| `RENDER_SCALE` | Renderauflösung (höher = schärfere Schrift, mehr Last) |
| `SWIPE_TO_TURN` | Wischen zum Umblättern an/aus |
| `START_IN_PASSTHROUGH` | direkt im echten Zimmer starten |

## Technik

```
manga_reader/
  project.godot          OpenXR, Handtracking-Erweiterungen, Mobile-Renderer
  export_presets.cfg     Quest-3-Export (Handtracking + Passthrough optional, Speicherzugriff)
  scripts/
    config.gd            ← Einstellungen
    main.gd              Start, Lesezimmer, Bibliothek, Kapitel, Menü, Buch greifen, Fortschritt
    book.gd              3D-Buch: Doppelseiten, Umblättern per Hand, Seitenstapel, Rascheln
    hands.gd             Handtracking (Pinch, Faust, Fingerspitze), Controller, Maus
    ui3d.gd              Antipp-Knöpfe und Zeigestrahl
    page_cache.gd        Bilder im Hintergrund laden, verkleinern, Mipmaps
    local_source.gd      CBZ/ZIP und Bilder-Ordner
    komga_source.gd      Komga-REST-API
  shaders/
    page.gdshader        Seite mit Papierrand und Schatten am Falz
    sheet.gdshader       biegsames Blatt beim Umblättern
  tools/make_demo_manga.py
  test/run_test.gd
```

- **Umblättern:** Das Blatt ist am Falz befestigt. Sein Winkel folgt der Hand. Damit es sich wie
  Papier biegt, nimmt der Winkel entlang des Blatts zu, die Form ist also ein Kreisbogen, den der
  Vertex-Shader geschlossen berechnet. Vorder- und Rückseite zeigen verschiedene Seiten.
- **Schärfe:** Seiten werden mit Mipmaps und anisotroper Filterung dargestellt. So bleibt kleine
  Schrift ruhig und flimmert nicht. Foveated Rendering steht auf niedrig, damit auch der Rand des
  Buchs scharf bleibt.
- **Kein Ruckeln:** Bilder werden in Hintergrund-Threads dekodiert. Pro Frame werden höchstens etwa
  4 ms für das Hochladen auf die Grafikkarte verwendet.

### Eigene Quelle hinzufügen

Eine Quelle ist ein Skript mit diesen Methoden (Vorlage: `local_source.gd` oder `komga_source.gd`):
`list_series(cb)`, `list_chapters(series, cb)`, `list_pages(chapter, cb)`, `is_threaded()` und
entweder `read_bytes(ref)` (im Thread) oder `fetch_bytes(ref, cb)` (asynchron). Eingebunden wird sie
in `main.gd` unter `_setup_sources()`. So lassen sich z. B. ein Kavita-Server oder ein
OPDS-Katalog anschließen.
