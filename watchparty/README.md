# 🍿 MInfy Lounge: zusammen schauen, teilen und zocken in VR

Eine VR-Lounge für dich und deine Freunde: Ihr sitzt zusammen auf dem Sofa in einem gemütlichen Kinosaal,
schaut **YouTube, Twitch und Videos** synchron auf einer riesigen Leinwand, **teilt eure Bildschirme**
(auch mehrere gleichzeitig) und **zockt zusammen**. Dabei hört ihr euch per Sprachchat, und zwar räumlich:
Die Stimme kommt von dort, wo der Avatar sitzt.

- **Läuft im Browser der Meta Quest** (WebXR): einfach Link öffnen und „VR starten“, kein APK, kein Entwicklermodus.
- **Auch ohne Brille** am PC, Laptop, Tablet oder im Quest-Browserfenster. VR- und PC-Leute sind im selben Raum.
- **Selbst gehostet:** Ein kleiner Node.js-Server auf deinem PC. Bild und Ton laufen direkt zwischen euch (WebRTC).

| Funktion | Wie |
|---|---|
| YouTube schauen | Link einfügen → läuft bei allen synchron (Pause, Spulen, Springen) |
| Twitch schauen | Kanal-Link (live) oder Video-Link (VOD, synchron) einfügen |
| Videos/Streams | Direkte Links auf `.mp4`, `.webm` oder `.m3u8` (HLS) |
| Bildschirm teilen | 🖥️ **Teilen** (scharf, 30 FPS) oder 🎮 **Spiel teilen** (flüssig, 60 FPS), mit Ton |
| Mehrere Bildschirme | Bis zu 5 gleichzeitig: große Leinwand + 4 Seitenbildschirme. Anklicken holt einen nach vorn |
| Sprachchat | Mikrofon, räumlicher Ton, leuchtendes Visier beim Sprechen |
| Chat & Reaktionen | Textchat, 👍 😂 😮 ❤️ 🔥 👏 schweben über deinem Avatar |
| VR-Bedienung | Laserpointer, schwebendes Menü, Teleport, Laufen, Drehen |

---

## Warum im Browser und nicht als Godot-App wie MInfy?

YouTube und Twitch lassen sich nur in einem Browser abspielen, und Bildschirm teilen per WebRTC gibt
es fertig nur im Browser. Eine native Quest-App müsste dafür einen eigenen Browser einbauen.
Mit WebXR bekommt ihr echtes VR (6DoF, Controller, Hand-Tracking) und alle Web-Funktionen auf einmal.

---

## 1. Schnellstart (5 Minuten)

1. **[Node.js](https://nodejs.org) installieren** (Version 18 oder neuer, „LTS“ nehmen).
2. **Server starten:**
   - **Windows:** Doppelklick auf `start_lounge.bat`
   - **Linux/macOS:** `./start_lounge.sh`

   Beim ersten Start werden die Pakete installiert und ein Zertifikat erstellt. Danach siehst du:
   ```
   [Lounge] MInfy Lounge läuft auf Port 8443 (HTTPS)
     Auf diesem PC:   https://localhost:8443
     Im WLAN (Quest): https://192.168.178.20:8443
   ```
3. **Am PC** `https://localhost:8443` in **Chrome oder Edge** öffnen.
4. **Auf der Quest** den Browser öffnen und die WLAN-Adresse eingeben (z. B. `https://192.168.178.20:8443`).
5. Beim ersten Mal kommt eine **Zertifikatswarnung**, weil das Zertifikat selbst erstellt ist.
   Auf **„Erweitert“ → „Weiter zu … (unsicher)“** tippen. Das ist bei deinem eigenen Server in Ordnung.
6. Namen und Raumcode eingeben, **„Lounge betreten“** und Mikrofon erlauben. Auf der Quest dann **🥽 VR starten**.

> **Wichtig:** VR, Mikrofon und Bildschirm teilen funktionieren nur über **HTTPS**. Deshalb startet der Server
> standardmäßig mit HTTPS.

## 2. Mit Freunden spielen, die woanders wohnen

Deine Freunde müssen deinen Server erreichen. Am einfachsten geht das ohne Router-Einstellungen:

### Variante A: Cloudflare-Tunnel (empfohlen, kostenlos, echte HTTPS-Adresse)

1. [`cloudflared`](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) installieren.
2. Lounge **ohne eigenes Zertifikat** starten: `npm run start:http` (läuft dann auf Port 8080)
3. In einem zweiten Fenster: `cloudflared tunnel --url http://localhost:8080`
4. Es erscheint eine Adresse wie `https://irgendwas-zufaelliges.trycloudflare.com`. Diese schickst du deinen Freunden,
   und alle (auch du) benutzen sie. Es gibt keine Zertifikatswarnung, und **Twitch funktioniert sicher**
   (Twitch verlangt einen echten Domainnamen statt einer IP-Adresse).

Bei jedem Neustart von `cloudflared` gibt es eine neue Adresse. Für eine feste Adresse brauchst du ein kostenloses
Cloudflare-Konto mit eigener Domain.

### Variante B: Tailscale (privates Netz nur für euch)

[Tailscale](https://tailscale.com) auf deinem PC, den Quests (gibt es im Meta Store) und bei den Freunden
installieren. Mit `tailscale serve --bg 8080` (bei `npm run start:http`) bekommst du eine HTTPS-Adresse
wie `https://dein-pc.tailnet-name.ts.net`, die nur eure Geräte erreichen.

### Variante C: Portweiterleitung

TCP-Port **8443** im Router auf deinen PC weiterleiten (Fritz!Box: *Internet → Freigaben*) und z. B. eine
DuckDNS-Adresse verwenden. Dann sehen alle die Zertifikatswarnung (siehe oben).

### Wenn Bild oder Ton bei Freunden nicht ankommt

Bild und Ton gehen **direkt** zwischen euren Geräten (WebRTC). Das klappt fast immer. Hinter sehr strengen
Routern (manche Mobilfunk- oder Firmennetze) braucht ihr einen **TURN-Server**, der die Daten weiterleitet,
z. B. selbst gehostet mit [coturn](https://github.com/coturn/coturn) oder einen Dienst wie Metered:

```bash
TURN_URL=turn:turn.example.com:3478 TURN_USER=name TURN_PASS=passwort node server.js
```

---

## 3. Bedienung

### Am PC oder im Quest-Browser (ohne VR)

| Aktion | So geht's |
|---|---|
| Umschauen | Maus gedrückt halten und ziehen |
| Laufen | W A S D oder Pfeiltasten |
| Bildschirm nach vorn holen | Seitenbildschirm anklicken, oder unten bei „Große Leinwand“ wählen |
| Video starten | Link unten einfügen → **▶ Abspielen** |
| Pause / Spulen / Lautstärke | Leiste unten (gilt für alle, Lautstärke nur für dich) |
| Mikrofon stumm | **M** oder 🎤 |
| Chat | **Enter**, Nachricht tippen, Enter |
| Direkt in den YouTube-Player klicken | **🖱️ Player** (nochmal drücken = zurück zum Umschauen) |

### In VR (Meta Quest)

| Taste | Aktion |
|---|---|
| Linker Stick | Laufen |
| Rechter Stick links/rechts | Drehen in 30°-Schritten |
| Trigger auf den Boden | Teleportieren (lila Ring zeigt das Ziel) |
| Trigger auf einen Bildschirm | Auf die große Leinwand holen |
| **X** oder **A** | Menü öffnen/schließen |
| **Y** | Mikrofon stumm/an |
| Trigger im Menü | Knopf drücken |

Im **Menü**: Mikrofon, Platz wechseln (Sofas, vorne stehen), was auf der großen Leinwand läuft, Pause/Spulen/Stopp,
Lautstärke, Reaktionen, die letzten Chatnachrichten und „VR verlassen“.

Hand-Tracking geht auch: Zeigen und mit Daumen und Zeigefinger „klicken“ (zusammenkneifen).

---

## 4. YouTube und Twitch in VR: das VR-Relais

Am PC und im Quest-Browserfenster läuft YouTube/Twitch direkt auf der 3D-Leinwand. **Im VR-Modus** erlauben
Browser es aber nicht, YouTube- oder Twitch-Player in eine 3D-Welt zu zeichnen (aus Sicherheitsgründen).
Den Ton hört man trotzdem, auf der Leinwand steht dann ein Hinweis.

**Die Lösung ist das 📡 VR-Relais.** Jemand am **PC mit Chrome oder Edge** klickt in der Videoleiste auf
**📡 VR-Relais**. Es öffnet sich ein kleines Fenster, das das Video synchron mitspielt. Dort auf
**„Relais starten“** klicken und im Dialog **„Diesen Tab“** mit **Tab-Audio** wählen. Ab dann sehen alle in VR
das Video samt Ton auf der Leinwand. Das Fenster offen lassen (darf im Hintergrund sein, nicht minimieren).

Ohne Relais immer in VR sichtbar: **geteilte Bildschirme** und **direkte Video-Links** (mp4, webm, m3u8).

Wenn ihr **nur Quests ohne PC** habt: Schaut YouTube/Twitch im Quest-Browserfenster (ohne „VR starten“).
Ihr seht euch dann trotzdem als Avatare im Kino und hört euch.

---

## 5. Zusammen zocken

- **Jeder kann gleichzeitig teilen.** Spielt ihr ein Online-Spiel zusammen (jeder an seinem PC), teilt jeder mit
  **🎮 Spiel teilen** sein Spiel. Die Bildschirme erscheinen nebeneinander, und per Klick holt man einen auf die große Leinwand.
- **🎮 Spiel teilen** überträgt mit 60 FPS und höherer Bitrate und bevorzugt flüssige Bewegung vor Schärfe.
- **Ein Spiel, mehrere Spieler:** Um ein lokales Koop-Spiel von einem PC aus gemeinsam zu **steuern**, nehmt
  zusätzlich **Steam Remote Play Together** (bei Steam-Spielen mit lokalem Koop) oder **Parsec**. Die Steuerung läuft
  darüber, und in der Lounge teilt der Gastgeber das Spiel, damit alle es auf der Leinwand sehen.
  Ein Browser darf aus Sicherheitsgründen keine Tastatur- oder Controller-Eingaben an andere Programme schicken.
- Fürs Spielen in VR einfach den PC-Bildschirm teilen und in der Quest auf die Leinwand schauen
  (**Platz wechseln** → „vorne stehen“).

Tipp: Bildschirmteilung braucht Upload-Bandwidth: pro Zuschauer etwa 5–8 MBit/s. Bei 4 Zuschauern also 20–30 MBit/s.

---

## 6. Gut zu wissen

- **Netflix, Disney+ usw.** (DRM-geschützt) erscheinen beim Teilen schwarz. Das ist eine Sperre der Anbieter.
- **Manche YouTube-Videos** sind für Einbettung gesperrt (Musikvideos großer Labels). Die könnt ihr per Tab-Teilen zeigen.
- **Twitch** braucht einen Domainnamen. Mit reiner IP-Adresse kann der Player streiken, mit Tunnel/Tailscale klappt es.
- **Direkte Videolinks ohne CORS:** Der Server holt sie automatisch über seinen eingebauten Proxy (nur für Teilnehmer).
- **Raumgröße:** bis zu 8 Personen (`MAX_PEERS`). Alle sind direkt miteinander verbunden, das ist für eine Freundesgruppe ideal.
- **Datenschutz:** Der Server speichert nichts. Räume verschwinden, sobald alle gegangen sind.

### Einstellungen

| Variable / Parameter | Bedeutung | Standard |
|---|---|---|
| `--port=…` / `PORT` | Port | 8443 (HTTPS) bzw. 8080 (HTTP) |
| `--http` / `HTTPS=0` | Ohne eigenes Zertifikat (für Tunnel/Tailscale) | aus |
| `CERT`, `KEY` | Eigenes Zertifikat (PEM-Dateien) verwenden | `certs/` (selbst erstellt) |
| `MAX_PEERS` | Max. Personen pro Raum | 8 |
| `STUN_URLS` | STUN-Server (kommagetrennt) | Google STUN |
| `TURN_URL`, `TURN_USER`, `TURN_PASS` | TURN-Server für strenge Netze | – |
| `PROXY=0` | Video-Proxy abschalten | an |

### Docker

```bash
docker build -t minfy-lounge .
docker run -d --name lounge -p 8443:8443 -v lounge-certs:/app/certs minfy-lounge
```

---

## Projektaufbau

```
server.js            Webserver (HTTPS), Räume, Synchronisierung, WebRTC-Vermittlung, Video-Proxy
public/
  index.html         Startseite und Bedienoberfläche
  relay.html         VR-Relais (YouTube/Twitch für VR-Zuschauer)
  style.css
  js/app.js          Hauptprogramm: Szene, PC- und VR-Steuerung, Leinwände, Teilen, Chat
  js/world.js        Der Kinosaal: Leinwände, Sofas, Licht
  js/avatar.js       Avatare mit räumlicher Stimme und Sprechanzeige
  js/media.js        YouTube/Twitch/Video abspielen und synchron halten
  js/net.js          WebSocket zum Server und WebRTC (Sprache, Bildschirme)
  js/vrui.js         Schwebendes VR-Menü
  js/relay.js        Logik des VR-Relais
start_lounge.bat/.sh Startskripte
```

Verwendete Bibliotheken: [three.js](https://threejs.org) (3D und WebXR), [ws](https://github.com/websockets/ws)
(WebSocket), [hls.js](https://github.com/video-dev/hls.js) (HLS-Streams), [selfsigned](https://github.com/jfromaniello/selfsigned)
(Zertifikat). Alle werden vom eigenen Server ausgeliefert, also ohne externes CDN.
