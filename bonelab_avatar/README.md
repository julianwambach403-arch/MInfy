# Sternenelf – eigener BONELAB-Avatar

Ein Custom-Avatar für BONELAB nach deinem Profilbild: Haut wie eine Galaxie, türkise, wilde
Haare mit Antenne, lange Elfenohren, leuchtende goldene Sternenaugen, schiefes Lächeln mit zwei
Kinn-Piercings und ein mintgrüner Hoodie mit offenem Reißverschluss.

| Porträt | Pose-Test (Rig) | T-Pose |
|---|---|---|
| ![Porträt](export/preview_portrait.png) | ![Pose](export/preview_pose.png) | ![T-Pose](export/preview_full.png) |

## Was ist drin?

| Datei | Inhalt |
|---|---|
| `export/SternenElf.fbx` | Fertiges Modell mit Skelett und eingebetteten Texturen, das du in Unity importierst |
| `export/SternenElf.blend` | Dieselbe Szene für Blender, falls du etwas ändern willst |
| `export/textures/` | Alle Texturen als PNG (Galaxie-Haut, Augen, Haare, Stoffe, dazu Emissions-Maps) |
| `generate_avatar.py` | Skript, das alles oben neu erzeugt (Farben, Haare usw. lassen sich dort anpassen) |

Technische Daten:

- **Größe:** ca. 1,80 m (mit Antenne 1,93 m), T-Pose, Blickrichtung nach vorne
- **Skelett:** 52 Knochen im Mixamo-Namensschema (`Hips`, `Spine`, `LeftArm`, `LeftHandIndex1` …),
  mit Fingern, damit Unity es automatisch als **Humanoid** erkennt
- **Zwei Meshes:** `Body` (Körper und Kleidung) und `Head` (Kopf, Gesicht, Ohren, Haare).
  BONELAB blendet die Kopf-Meshes in der Ego-Perspektive aus, deshalb sind sie getrennt.
- **Ca. 37.000 Dreiecke** zusammen. Für PC kein Problem. Für die Quest-Standalone-Version
  ist das an der oberen Grenze, läuft aber in der Regel.

## In BONELAB bringen (Schritt für Schritt)

### 1. Unity und das Marrow SDK einrichten

1. **Unity Hub** installieren und darüber die Unity-Version installieren, die das
   **Marrow SDK** verlangt (steht in der Readme des SDK, bei BONELAB eine 2021.3-Version).
   Wenn du auch für Quest bauen willst, beim Installieren **Android Build Support** mit anhaken.
2. Das offizielle **Marrow SDK** von Stress Level Zero laden
   (GitHub: `StressLevelZero/MarrowSDK`) und so installieren, wie es dort beschrieben ist.
   Danach erscheint in Unity oben das Menü **Stress Level Zero**.

### 2. Modell importieren

1. Den Ordner `export/` (FBX und `textures/`) per Drag & Drop in den Unity-Ordner
   `Assets/SternenElf/` ziehen.
2. `SternenElf.fbx` anklicken, im Inspector:
   - Reiter **Rig** → *Animation Type*: **Humanoid**, *Avatar Definition*: **Create From This
     Model** → **Apply**. Mit **Configure…** kannst du prüfen, ob alle Knochen grün sind.
     (Das sollten sie, weil die Namen dem Mixamo-Schema folgen.)
   - Reiter **Materials** → **Extract Textures…** und danach **Extract Materials…** in
     `Assets/SternenElf/` klicken.

### 3. Materialien auf BONELAB-Shader umstellen

BONELAB nutzt eigene Shader. Für jedes der 9 Materialien den Shader auf
**SLZ/LitMAS/LitMAS Opaque** stellen (oder einen Toon-Shader aus dem SDK, wenn du
den Comic-Look möchtest) und als **Albedo** die gleichnamige Textur aus `textures/` setzen.

| Material | Albedo | Extra |
|---|---|---|
| `Skin_Galaxy` | `galaxy_skin.png` | Emission an → `galaxy_skin_emission.png` (die Sterne leuchten leicht) |
| `Eyes` | `eyes.png` | Emission an → `eyes_emission.png`, Stärke ca. 2 (Sternenaugen glühen) |
| `Hair` | `hair.png` | Glätte etwas hoch (glänzende Haare) |
| `Hoodie`, `Hoodie_Trim`, `Pants`, `Shoes`, `Dark`, `Zipper` | gleichnamiges PNG | – |

Tipp: Die Galaxie-Textur ist nahtlos kachelbar. Wenn dir die Sterne zu groß oder zu klein sind,
ändere beim Material *Tiling* (z. B. 1,5 statt 1).

### 4. Avatar-Prefab bauen

1. `SternenElf.fbx` in die Szene ziehen (Position 0/0/0).
2. Am obersten Objekt **Add Component → Avatar** (das Avatar-Script aus dem Marrow SDK).
3. Im Avatar-Component:
   - **Body Meshes:** `Body` eintragen
   - **Head Meshes:** `Head` eintragen
   - Die **Augenposition / Eye Center** auf die Höhe der Augen legen, ungefähr
     **1,63 m** hoch und knapp vor dem Gesicht. In der Szene siehst du dafür ein Gizmo.
   - Die Körpermaße berechnen lassen (Button im Avatar-Component, z. B. *Precompute* oder
     *Calculate*, je nach SDK-Version). Daraus ergeben sich Gewicht, Kraft und Tempo im Spiel.
4. Das Objekt in den Projektordner ziehen. So entsteht ein **Prefab**.

### 5. Als Mod packen

1. **Stress Level Zero → Void Tools → Pallet Center** (Name je nach SDK-Version leicht anders)
   öffnen und eine neue **Pallet** anlegen, z. B. Autor = dein Name, Titel = „Sternenelf“.
2. In der Pallet einen **Avatar Crate** anlegen und dein Prefab als *Main Asset* eintragen.
3. **Pack for PC** (Windows) bzw. **Pack for Quest** (Android) klicken.
4. Den fertigen Mod-Ordner aus dem `Built Mods`-Ordner deines Unity-Projekts kopieren nach:
   - **PC:** `%USERPROFILE%\AppData\LocalLow\Stress Level Zero\BONELAB\Mods`
   - **Quest:** `Android/data/com.StressLevelZero.BONELAB/files/Mods`
     (per USB oder mit SideQuest)

Im Spiel findest du die Sternenelfe dann im **Body Mall** oder über das **Avatar-Menü** am
Handgelenk.

## Anpassen

Die Datei `generate_avatar.py` erzeugt alles neu. Interessante Stellen:

| Was | Wo im Skript |
|---|---|
| Hoodie-, Hosen- und Schuhfarbe | `cloth_texture("hoodie", (0.62, 0.92, 0.78))` usw. (RGB von 0 bis 1) |
| Haarfarbe | `hair_texture()` → `dark`, `mid`, `light` |
| Galaxie-Farben, Anzahl der Sterne | `galaxy_texture()` |
| Augenform, Iris und Stern | `lid_top`, `lid_bot`, `eye_texture()` |
| Länge der Ohren | Abschnitt „Elfenohren“ (letzter Punkt = Ohrspitze) |
| Pony, seitliche Strähnen, Antenne | Abschnitt „Haare“ |

Neu erzeugen:

```bash
# mit installiertem Blender (4.2 oder neuer)
blender -b -P generate_avatar.py -- --out export

# oder ohne Blender-Oberfläche mit dem Python-Modul bpy (Python 3.13)
pip install bpy
python generate_avatar.py --out export
```

Mit `--no-render` werden die Vorschaubilder übersprungen. Das ist deutlich schneller.

## Bekannte Grenzen

- Das Modell ist komplett per Code gebaut, also stilisiert und nicht handmodelliert. Für mehr
  Details (Gesichtsform, Hoodie-Falten) kannst du die `.blend` in Blender weiter bearbeiten.
- Es gibt keine Blendshapes (Mimik oder Lippenbewegung). BONELAB braucht keine, aber das Gesicht
  bleibt dadurch beim Lächeln.
- Die Haare sind fest mit dem Kopf verbunden und haben keine Physik.
