# MInfy – ein kleines VR-MMORPG für Meta Quest 3

Ein selbst gehostetes VR-Rollenspiel für zwei (oder mehr) Spieler: Ihr startet in einem kleinen
Dorf auf einer Insel, nehmt Aufgaben vom Dorfältesten an, kämpft mit dem Schwert (echte
Schwungbewegung!) und Feuerbällen gegen Schleime, Wölfe und einen Steingolem, sammelt Gold,
steigt im Level auf und lasst euch bei der Schmiedin bessere Schwerter schmieden.
Euer Fortschritt wird auf **deinem eigenen Server** gespeichert.

- **Engine:** [Godot 4.4](https://godotengine.org) (kostenlos, Open Source)
- **Läuft nativ auf der Quest 3** als APK (OpenXR, kein Browser, kein PC nötig)
- **Server:** dieselbe Projektdatei, läuft ohne Grafik auf PC, Raspberry-Pi-ähnlichem Linux-Server,
  NAS oder in Docker
- **Grafik und Sound:** alles im einheitlichen Low-Poly-Stil direkt im Code erzeugt, ohne
  Lizenzprobleme und komplett kostenlos (siehe „Assets“ unten)

---

## Inhalt des Spiels

| Ort | Wo | Gegner |
|---|---|---|
| Dorf mit Lagerfeuer (heilt schnell) | Mitte | – |
| Blumenwiese | Süden | Schleime (Lv 1) |
| Dunkelwald | Osten | Wölfe (Lv 3) |
| Alte Ruinen | Norden | Steingolem (Boss, Lv 7, Stampfangriff) |

- **Ältester Bruno** (am Lagerfeuer) gibt 3 aufeinander aufbauende Aufgaben.
- **Waffen schmiedest du selbst** an Gretas Esse, mit echter Physik (siehe „Schmieden“ unten).
  Greta verkauft dir Eisenerz und erklärt, wie es geht.
- Erfahrung und Beute bekommen **alle**, die einen Gegner getroffen haben, also ideal zu zweit.
- Wer besiegt wird, wacht im Dorf auf und verliert 10 % seines Golds.

## Fähigkeiten

Mit jedem Level schaltest du eine neue Fähigkeit frei. Sie kosten Mana und haben eine
Abklingzeit. Die gewählte Fähigkeit und ihr Status stehen am linken Handgelenk, und die
leuchtende Kugel in der linken Hand zeigt ihre Farbe. Leuchtet die Kugel, ist die Fähigkeit bereit.

| Level | Fähigkeit | Mana | Abklingzeit | Wirkung |
|---|---|---|---|---|
| 1 | Feuerball | 25 | 0,8 s | Geschoss in Zielrichtung der linken Hand |
| 2 | Heilung | 35 | 8 s | Heilt dich **und** Mitspieler im Umkreis von 6 m |
| 3 | Frostnova | 30 | 10 s | Eiswelle: Schaden ringsum, Gegner 4 s lang stark verlangsamt |
| 4 | Wirbelwind | 20 | 7 s | Rundumschlag mit dem Schwert gegen alle nahen Gegner |
| 5 | Kettenblitz | 40 | 6 s | Blitz auf das anvisierte Ziel, springt auf bis zu 2 weitere über |
| 6 | Schutzschild | 30 | 20 s | 6 s lang halber Schaden (andere sehen eine goldene Kugel um dich) |

Zu zweit lohnt sich die Aufteilung: Eine Person verlangsamt mit Frostnova und schützt sich mit dem
Schild, die andere heilt und teilt mit Kettenblitz aus. Werte und neue Fähigkeiten stehen in
`scripts/game_data.gd` unter `SKILLS`, die Wirkung in `scripts/server.gd` unter `on_cast`.

## Menü und Inventar

Das Spielmenü schwebt als halbtransparentes Fenster in der Welt vor dir. Es ist inspiriert von
VR-MMO-Menüs aus Anime, hat aber ein eigenes Design.

- **Öffnen:** Rechten Trigger gedrückt halten und die Hand zügig **nach unten wischen**
  (oder die Menü-Taste an der linken Hand). Nach oben wischen schließt es wieder.
  Am PC: **I**.
- **Bedienen:** Aus der rechten Hand kommt ein Laserstrahl. Zeigen und mit dem **Trigger** klicken
  (am PC: Fadenkreuz in der Bildmitte und Linksklick). Läufst du weg, schließt sich das Menü.
- **Runde Symbole links:** Gegenstände · Ausrüstung · Fähigkeiten · Status · Schließen

| Bereich | Was du dort machst |
|---|---|
| Gegenstände | Alle Gegenstände (40 Plätze): Erze, Tränke, Waffen. Benutzen, Materialisieren, Geben, Wegwerfen |
| Ausrüstung | Aktuelle Waffe mit Schadenswerten. Waffen aus dem Inventar ausrüsten (die alte wandert ins Inventar) |
| Fähigkeiten | Alle Fähigkeiten inkl. Claudes eigener (*) ansehen und als aktive wählen |
| Status | Level, Werte, Aufgabe und alle Erfolge zum Abhaken |

**Materialisieren:** Ein Trank erscheint mit einem Lichteffekt als **echte Flasche in deiner Hand**
(Physik-Objekt). Führe sie zum **Mund**, um sie zu trinken. Loslassen (Grip) lässt sie fallen, mit Grip
hebst du sie wieder auf. Liegengelassene Tränke kehren nach 30 Sekunden ins Inventar zurück.
Am PC landet der Trank in der linken Hand, **T** trinkt ihn.

**Geben:** Gibt einen Gegenstand (auch Waffen) direkt an den nächsten Mitspieler in bis zu 4 m
Entfernung, also perfekt, um deiner Schwester einen Trank oder Erz zuzustecken.

**Tränke:** Heiltrank (+50 % HP) und Manatrank (+60 Mana). Schleime und Wölfe lassen sie
manchmal fallen, der Golem immer.

Alles liegt auf dem Server (der Client zeigt nur an), wird mit dem Spielstand gespeichert,
und alte Spielstände übernehmen ihre Erze automatisch ins Inventar.

## Schmieden (mit echter Physik)

Neben Schmiedin Greta (rechts vom Lagerfeuer) steht eine Schmiede mit **Esse, Amboss, Hammer,
Wasserfass und Bedienfeld**. Hammer und Rohling sind echte Physik-Objekte (Jolt Physics). Sie fallen
herunter, prallen ab, kollidieren mit dem Amboss und lassen sich werfen. Gegriffene Gegenstände
folgen deiner Hand über Kräfte, sind also nicht einfach festgeklebt.

**1. Erz sammeln**

| Erz | Woher |
|---|---|
| Eisenerz | Schleime (30 %), Wölfe (60 %), oder bei Greta für 15 Gold kaufen (sie ansprechen) |
| Golderz | Wölfe (15 %), Steingolem (3 Stück) |
| Kristall | Steingolem (2 Stück) |

**2. Rezept wählen:** Die Knöpfe am Bedienfeld drückst du in VR mit der Hand (antippen).
Wähle die Waffe und das Material, dann **SCHMIEDEN**.

| Material | Rezept | Schaden |
|---|---|---|
| Eisen | 3 Eisenerz | ×1,35 |
| Gold | 2 Eisenerz + 4 Golderz | ×1,8 |
| Kristall | 3 Golderz + 3 Kristall | ×2,5 |

| Waffe | Besonderheit |
|---|---|
| Schwert | ausgewogen |
| Axt | +25 % Schaden |
| Streitkolben | +10 % Schaden und stößt Gegner zurück (außer den Golem) |

**3. Erhitzen:** Der Rohling liegt in der Glut der Esse (links) und glüht langsam
grau → rot → orange → gelb. Unter 40 % Hitze lässt er sich nicht formen und kühlt außerhalb der
Glut langsam ab.

**4. Hämmern:** Greife den Rohling (Grip-Taste) und leg ihn auf den Amboss. Greife den Hammer mit
der anderen Hand und schlag zu. Ideal sind kräftige Schläge mit etwa **4–5 m/s**: zu sanft formt
kaum, zu fest verschlechtert die Qualität. Mit jedem Schlag wird der Rohling länger und flacher.
Funken, Klang und Vibration zeigen jeden Treffer. Das Bedienfeld zeigt Hitze, Form, Schläge und
Qualität. Zwischendurch nachheizen!

**5. Abschrecken:** Ist die Form bei 100 %, tauche die Klinge ins **Wasserfass** (rechts). Es zischt,
und die Waffe ist fertig und sofort in deiner Hand. Noch heiß abgeschreckt gibt es volle Qualität.

Die **Qualität** (Durchschnitt aus Schlagkraft und Hitze) verändert den Schaden von ×0,8 bis ×1,2 und
steht im Waffennamen, z. B. „Meisterhafte Kristallaxt“ oder „Grobes Eisenschwert“. Abbrechen gibt
das Erz zurück. Wer zu schnell „fertig“ meldet, dem zerspringt die Klinge, denn der Server prüft mit.

## Erfolge und eigene Fähigkeiten von Claude

Für jeden geschafften **Erfolg** programmiert **Claude** (über die Claude Code CLI auf deinem
Server) eine **ganz eigene Fähigkeit**, die zum Erfolg und zu deiner Spielweise passt. Wer viel
heilt, bekommt eher etwas Unterstützendes. Wer ständig mit dem Schwert zuschlägt, bekommt eher
etwas Wuchtiges. Claude kennt dafür deine Spielstatistik (besiegte Gegner, Lieblingsfähigkeit,
geheilte Lebenspunkte, Niederlagen …) und deine bisherigen eigenen Fähigkeiten, damit jede neu ist.

| Erfolg | Bedingung |
|---|---|
| Erster Sieg | ersten Gegner besiegen |
| Schleimjäger | 25 Schleime besiegen |
| Wolfsbezwinger | 15 Wölfe besiegen |
| Golembrecher | den Steingolem besiegen |
| Retter des Dorfes | alle Aufgaben von Bruno erfüllen |
| Erfahren / Veteran | Level 5 / Level 10 |
| Schwertmeister | 300 Schwerttreffer |
| Zauberweber | 100 Fähigkeiten einsetzen |
| Lebensretter | insgesamt 1000 Lebenspunkte heilen |
| Stehaufmännchen | 5-mal besiegt werden |
| Goldhamster | 500 Gold auf einmal besitzen |
| Kristallklinge | eine Waffe aus Kristall schmieden |
| Lehrling der Esse | die erste eigene Waffe schmieden |
| Meisterschmied | eine meisterhafte Waffe schmieden (Qualität ab 85 %) |

**So läuft es ab:**
1. Du schaffst einen Erfolg und es erscheint „Claude schmiedet jetzt eine eigene Fähigkeit für dich …“.
2. Der Server legt einen Arbeitsordner mit Anleitung, Schnittstellen-Beschreibung, Beispiel und
   deiner Statistik an und startet `claude -p …` darin. Claude Code darf dort nur Dateien lesen und
   schreiben (keine Shell, kein Internet) und schreibt die Fähigkeit als GDScript in `skill.gd`.
3. Der Server prüft den Code (verbotene Befehle, Kompilierbarkeit, Pflichtangaben). Ist er
   fehlerhaft, bekommt Claude die Fehlermeldung und einen zweiten Versuch.
4. Die Fähigkeit wird sofort geladen und erscheint in deiner Fähigkeiten-Auswahl
   (am Handgelenk mit `*` markiert, am PC mit den Tasten 7, 8, 9 und 0 wählbar).

Das dauert meist 1–3 Minuten. Du kannst währenddessen normal weiterspielen. Bist du dann schon
offline, bekommst du die Fähigkeit beim nächsten Login.

**Sicherheit und Fairness:** Der Code von Claude darf ausschließlich über eine begrenzte
Spiel-Schnittstelle (`scripts/skill_api.gd`) wirken. Schaden und Heilung pro Einsatz sind gedeckelt,
Mana und Abklingzeit liegen in festen Grenzen, und Zugriffe auf Dateien, Netzwerk oder System
werden vor dem Laden abgelehnt. Das schützt vor Fehlern und übermächtigen Fähigkeiten.
Eine echte Sandbox gegen absichtlich bösartigen Code ist es nicht; für euren eigenen Server mit
Claude als Programmierer ist das aber in Ordnung.

**Wo liegt was?** Fertige Fähigkeiten liegen unter
`…/app_userdata/MInfy/custom_skills/<name>/<erfolg>.gd`. Du kannst sie ansehen und von Hand
ändern; sie werden beim nächsten Login neu geladen. Claudes Arbeitsordner liegen unter
`…/app_userdata/MInfy/claude_work/`.

### Claude Code auf dem Server einrichten

**Du brauchst keinen API-Schlüssel.** Claude Code läuft mit deinem normalen Claude-Abo (Pro oder Max).

1. [Node.js](https://nodejs.org) (Version 18 oder neuer) installieren.
2. `npm install -g @anthropic-ai/claude-code`
3. **Auf dem Server-PC einmal `claude` im Terminal starten** und dich mit deinem Claude-Konto anmelden
   (es öffnet sich der Browser). Danach `/exit`. Die Anmeldung bleibt gespeichert.
4. Kurz testen, ob es klappt: `claude -p "Sag Hallo"`. Wenn eine Antwort kommt, ist alles bereit.
5. Server wie gewohnt starten, und zwar **mit demselben Benutzerkonto**, mit dem du dich angemeldet hast.
   Im Log steht `[Skill-Schmiede] Claude Code: an (claude)`.

Wer stattdessen einen API-Schlüssel hat, kann auch `ANTHROPIC_API_KEY` setzen. Nötig ist das nicht.

Einstellungen stehen in `scripts/config.gd` (`CLAUDE_ENABLED`, `CLAUDE_COMMAND`, `CLAUDE_MODEL`).
Startparameter: `--claude=/pfad/zu/claude` oder `--no-claude`. Ohne Claude gibt es für jeden Erfolg
eine einfache Ersatz-Fähigkeit („Echo: …“).
**Docker (mit Claude-Abo):** Im Container kann sich Claude nicht per Browser anmelden. Deshalb erzeugst
du einmalig auf deinem PC (dort, wo `claude` installiert und angemeldet ist) einen Anmelde-Token:

```bash
claude setup-token
```

Den angezeigten Token trägst du in eine Datei `.env` neben `docker-compose.yml` ein:

```
CLAUDE_CODE_OAUTH_TOKEN=der-angezeigte-token
```

Danach `docker compose up -d --build`. Die `.env`-Datei ist in `.gitignore` eingetragen, damit der Token
nicht versehentlich hochgeladen wird. Behandle ihn wie ein Passwort.

Hinweis: Jeder generierte Skill ist ein Claude-Code-Aufruf und verbraucht Nutzung deines
Claude-Abos bzw. API-Guthabens (bei 13 Erfolgen pro Spieler überschaubar).

## Steuerung

**Meta Quest 3**

| Taste | Aktion |
|---|---|
| Linker Stick | Laufen (Stick drücken = Sprinten) |
| Grip (links/rechts) | Hammer, Rohling oder Trankflasche greifen (gedrückt halten, loslassen = fallen lassen/werfen) |
| Rechter Trigger halten + nach unten wischen | Menü öffnen (nach oben wischen = schließen), auch Menü-Taste links |
| Rechter Trigger (Menü offen) | Mit dem Laserstrahl klicken |
| Rechter Stick links/rechts | Drehen in 30°-Schritten |
| **Schwert schwingen** (rechte Hand) | Angreifen: je schneller, desto mehr Schaden |
| Linker Trigger | Gewählte Fähigkeit wirken (aus der linken Hand) |
| X / Y (links) | Nächste / vorherige Fähigkeit wählen |
| A (rechts) | Mit Figuren sprechen |
| B (rechts) | Heimkehr ins Dorf (alle 20 s) |
| Linkes Handgelenk | Anzeige für Lebenspunkte, Mana, Erfahrung, Gold und Aufgabe |

**Startmenü in VR:** Rechter Stick hoch/runter wählt die Zeile, links/rechts ändert Name, Farbe
oder Server. Mit **A** verbindest du dich.

**Am PC ohne Brille (zum Testen):** WASD laufen, Maus schauen, Linksklick Schwert,
Rechtsklick oder Q Fähigkeit wirken, 1–6 oder Tab Fähigkeit wählen, 7/8/9/0 eigene Fähigkeiten, E sprechen bzw. Knopf am Bedienfeld drücken (anschauen), R Heimkehr, Shift sprinten.
Menü: I (Fadenkreuz + Linksklick), T Trank trinken.
Schmiede am PC: F Hammer greifen/loslassen, G Rohling greifen/loslassen, Linksklick mit Hammer
= Hammerschlag.

---

## 1. Einmalige Vorbereitung

1. **Godot 4.4.1** (Standard-Version, nicht .NET) herunterladen: https://godotengine.org/download
2. Projekt öffnen: Godot starten → *Importieren* → `project.godot` aus diesem Ordner wählen.
   Beim ersten Öffnen legt Godot automatisch `openxr_action_map.tres` (die Controller-Belegung) an.
3. **Android-Export einrichten** (nur einmal nötig):
   - In Godot: *Editor → Exportvorlagen verwalten → Herunterladen und installieren*.
   - Java **OpenJDK 17** und das **Android SDK** installieren (am einfachsten über Android Studio).
     Dann in *Editor → Editoreinstellungen → Export → Android* die Pfade eintragen.
     Anleitung: https://docs.godotengine.org/de/4.x/tutorials/export/exporting_for_android.html
   - *Projekt → Android-Build-Vorlage installieren*.
4. **Meta-Quest-Plugin**: *AssetLib*-Tab → nach **„Godot OpenXR Vendors“** suchen →
   herunterladen und installieren. Danach unter *Projekt → Projekteinstellungen → Plugins*
   aktivieren, falls nötig.
5. **Quest im Entwicklermodus:** In der Meta-Horizon-App auf dem Handy unter
   *Geräte → Headset-Einstellungen → Entwicklermodus* einschalten (dafür ist ein kostenloser
   Meta-Entwickler-Account nötig). Quest per USB-C mit dem PC verbinden und den Zugriff in der
   Brille erlauben.

## 2. Server-Adresse eintragen

Öffne `scripts/config.gd` und trage bei `SERVERS` die Adresse deines Servers ein, zum Beispiel
die LAN-IP deines PCs (`192.168.178.20`) und/oder eine Internet-Adresse.
Auch die Namen im Startmenü (`NAMES`) kannst du hier ändern, etwa auf deinen Namen und den
deiner Schwester. **Jeder Name hat seinen eigenen Spielstand.**

## 3. Spiel für die Quest 3 bauen und installieren

1. *Projekt → Exportieren* → Vorlage **„Meta Quest 3“** ist schon angelegt.
   Kontrolliere, dass bei *XR Features* „XR Mode: OpenXR“ und „Enable Meta Plugin“ an sind und
   unter *Permissions* „Internet“ angehakt ist.
2. Bei angeschlossener Quest oben rechts im Editor auf das **Android-Symbol (Remote Deploy)**
   klicken, dann wird das Spiel direkt auf die Brille installiert und gestartet.
   Alternativ *Projekt exportieren…* → `build/MInfy.apk` und mit
   [SideQuest](https://sidequestvr.com) oder dem *Meta Quest Developer Hub* installieren.
3. In der Quest findest du das Spiel unter *App-Bibliothek → Unbekannte Quellen*.

Für die Quest deiner Schwester einfach dieselbe APK installieren.

## 4. Den Server betreiben

Der Server braucht nur **einen offenen UDP-Port (7777)** und sehr wenig Leistung.

### Variante A: Auf deinem PC (am einfachsten)

- **Windows:** `server/start_server.bat` öffnen, den Pfad zur Godot-Datei anpassen (die
  `…_console.exe`) und doppelklicken.
- **Linux/macOS:** `GODOT=/pfad/zu/godot ./server/start_server.sh`

Oder direkt:

```bash
godot --headless --xr-mode off --path . -- --server --port=7777
```

### Variante B: Docker (Linux-Server, NAS, VPS)

```bash
docker compose up -d --build
```

Spielstände landen im Ordner `./saves`. Mit `docker compose logs -f` siehst du, wer online ist.

### Aus dem Internet erreichbar machen

Wenn ihr im **selben WLAN** spielt, reicht die LAN-IP des Server-PCs, dann ist nichts weiter nötig.

Wenn deine Schwester **woanders wohnt**, gibt es zwei Möglichkeiten:

1. **Portweiterleitung** im Router: UDP 7777 an den Server-PC weiterleiten (bei der Fritz!Box unter
   *Internet → Freigaben*). Für eine feste Adresse trotz wechselnder IP einen kostenlosen
   DynDNS-Namen verwenden (z. B. duckdns.org).
2. **Ohne Router-Basteln:** [Tailscale](https://tailscale.com) oder [ZeroTier](https://zerotier.com)
   (beide kostenlos) auf Server-PC und beiden Quests installieren. Dann die Tailscale-IP des
   Servers in `config.gd` eintragen. Das ist auch sicherer, weil sonst niemand Fremdes
   mitspielen kann.

### Spielstände

Der Server speichert pro Spielername eine JSON-Datei, und zwar automatisch alle 30 Sekunden,
bei Levelaufstieg, Quest-Abschluss und Schwert-Kauf sowie beim Verlassen:

- Linux: `~/.local/share/godot/app_userdata/MInfy/saves/`
- Windows: `%APPDATA%\Godot\app_userdata\MInfy\saves\`

---

## Am PC testen

- Godot-Editor → **F5**: Ohne angeschlossene VR-Brille startet automatisch der Desktop-Modus.
  Mit SteamVR oder Quest Link startet die VR-Version am PC.
- Server und zwei Clients lokal testen: Im Editor *Debug → Mehrere Instanzen ausführen → 3*
  wählen und bei *Debug → Instanzen anpassen* für eine Instanz `--server` als Argument
  eintragen. Oder Server per Skript starten und den Client mit dem Eintrag „Dieser PC“ verbinden.
- Startparameter für den Client: `-- --desktop --name=Test --host=127.0.0.1 --autoconnect`

## Projektaufbau

```
project.godot          Projekt-Einstellungen (OpenXR an, Mobile-Renderer, Foveated Rendering)
main.tscn              Startszene
export_presets.cfg     Exportvorlagen: Meta Quest 3 (APK) und Linux-Server
scripts/
  config.gd            ← Server-Adressen und Spielernamen (hier anpassen!)
  game_data.gd         Gegner, Quests, Schwerter, Balancing
  main.gd              Startet Server oder Client
  game.gd              Netzwerk (ENet/UDP) und alle RPCs
  server.gd            Spiellogik: Gegner-KI, Kampf, Erfahrung, Quests, Speichern
  client.gd            VR-Steuerung, Startmenü, Avatare, Effekte, HUD
  world_gen.gd         Insel, Dorf, Wald, Ruinen (gleiche Welt auf Server und Client)
  lowpoly.gd           Baukasten für Low-Poly-Modelle
  sfx.gd               Synthetisierte Soundeffekte
  skill_forge.gd       Erfolge -> Claude Code CLI -> eigene Fähigkeit (prüfen & laden)
  skill_api.gd         Begrenzte Schnittstelle für Claudes Fähigkeiten
  forge_station.gd     Physikalische Schmiede (Greifen, Hitze, Hämmern, Abschrecken)
  menu_ui.gd           Schwebendes Menü: Inventar, Ausrüstung, Fähigkeiten, Status, Tränke
server/                Startskripte für den Server
Dockerfile, docker-compose.yml
```

Balancing anpassen (mehr Leben, mehr Gold, neue Quests) geht in `scripts/game_data.gd`.
Danach den Server neu starten und eine neue APK bauen.

## Assets

Alle Modelle (Bäume, Häuser, Figuren, Monster), die Welt und die Soundeffekte werden beim Start
**prozedural im Code erzeugt**, alles im selben Low-Poly-Stil mit flachen Farben. Dadurch ist
alles kostenlos, frei von Lizenzbedingungen und passt garantiert zusammen. Außerdem bleibt die
APK winzig und läuft flüssig auf der Quest 3.

Wer später „echte“ Modelle möchte: Die kostenlosen CC0-Pakete von
[Kenney](https://kenney.nl/assets) (z. B. *Nature Kit*, *Fantasy Town Kit*, *Mini Dungeon*) und
[Quaternius](https://quaternius.com) haben genau diesen Low-Poly-Stil. Die `.glb`-Dateien einfach
ins Projekt ziehen und z. B. in `world_gen.gd` statt `LP.box(...)` laden.

## Fehlersuche

| Problem | Lösung |
|---|---|
| „Server nicht erreichbar“ | Läuft der Server? Stimmt die IP in `config.gd`? Firewall: UDP 7777 freigeben. |
| Schwarzes Bild / Spiel startet flach auf der Quest | Plugin „Godot OpenXR Vendors“ installiert? Im Export „XR Mode: OpenXR“ und „Enable Meta Plugin“ aktiv? |
| Export-Fehler wegen Gradle | *Projekt → Android-Build-Vorlage installieren* und in der Export-Vorlage „Use Gradle Build“ anhaken. |
| „Name ist schon online“ | Jeder Spieler braucht einen eigenen Namen. |
