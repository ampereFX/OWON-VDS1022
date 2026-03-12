# Reverse Engineering Notes

Diese Datei soll spaetere Sessions abkuerzen. Sie dokumentiert, was dieses Repository
enthaelt, wie die Desktop-App tatsaechlich aufgebaut ist, wie der Decompilation-/Patch-
Workflow funktioniert und welche konkreten Erkenntnisse bereits gewonnen wurden.

Stand: 2026-03-12

## 1. Repo-Typ und Grundstruktur

Dieses Repository ist kein vollstaendiges Java-Quellrepo der Desktop-App.
Es ist ein Distributions-Repo mit:

- Installer-Skripten fuer macOS, Linux, Windows
- vorgebauter Java-Desktop-App als JAR
- nativen USB-Bibliotheken fuer mehrere Plattformen
- Firmware-Binaerdateien fuer verschiedene FPGA-/Board-Versionen
- Dokumentation
- einer vollstaendigen Python-API mit offenem Quelltext

Wichtige Dateien/Ordner:

- `README.md`
- `install-mac.sh`
- `install-linux.sh`
- `install-win.cmd`
- `lib/owon-vds-tiny-1.1.5-cf19.jar`
- `lib/ch.ntb.usb-0.5.9.jar`
- `fwr/*.bin`
- `api/python/vds1022/*.py`

## 2. Wie die Desktop-App gestartet wird

Der macOS-Installer baut nichts. Er kopiert Dateien nach
`/Applications/OWON VDS1022.app` und startet dann:

```bash
/usr/libexec/java_home --exec java -cp 'lib/*' com.owon.vds.tiny.Main
```

Wichtige Konsequenz:

- Die App-Logik liegt in der JAR.
- Es gibt im Repo keinen originalen Java-Quellbaum fuer die Desktop-App.
- Fuer App-Aenderungen muss man dekompilieren, patchen, kompilieren und die JAR aktualisieren.

## 3. JAR-Inhalt und Architektur

Die JAR ist gross und in mehrere Schichten gegliedert.

Wichtige Paketbereiche:

- `com.owon.vds.tiny.*`
  - Tiny-spezifischer Einstieg und Firmware-/Kalibrierungslogik
- `com.owon.uppersoft.dso.view.*`
  - Swing-UI
- `com.owon.uppersoft.dso.control.*`
  - Eingaben, Mouse/Key-Gesten, Interaktion
- `com.owon.uppersoft.dso.global.*`
  - Runtime-Orchestrierung, MainWindow, WorkBench, DataHouse
- `com.owon.uppersoft.dso.mode.control.*`
  - Timebase, Trigger, FFT, Sampling
- `com.owon.uppersoft.dso.model.*`
  - Waveform-/Render-Modell
- `com.owon.uppersoft.dso.source.*`
  - USB-/Netz-Kommunikation
- `com.owon.uppersoft.vds.socket.*`
  - SCPI-Server
- `com.owon.uppersoft.vds.core.zoom.*`
  - vorhandene Zoom-/Assist-Struktur

## 4. Wichtige Kernobjekte

### `com.owon.vds.tiny.Main`

Eintrittspunkt der Desktop-App.

### `ControlAppsTiny`, `ControlManagerTiny`, `CoreControlTiny`

Tiny-spezifische Runtime-Orchestrierung.

Grob:

- `ControlAppsTiny` haengt Tiny-Kommunikation und Daemon-Logik an
- `ControlManagerTiny` verbindet UI, Runtime und SourceManager
- `CoreControlTiny` kapselt Trigger-/Waveform-/Maschinenlogik

### `DataHouse`

Zentrales Laufzeitobjekt. Helt:

- Status der Anwendung
- Verweis auf `WorkBench`
- `WaveFormManager`
- `ControlManager`
- repaint-/paint-nahe globale Zustandsaspekte

Praktisch ist `DataHouse` der Knoten zwischen Acquisition, Chart, UI und Zusatzfunktionen.

### `WaveFormManager`

Verwaltet die sichtbaren Wellenformen, Rendering-nahe X/Y-Transformationen,
Referenzwellen, Math/Composite-Wellenform und das Zusammenspiel mit der
aktuellen Timebase.

Wichtige Erkenntnis:

- `WaveFormManager.addWaveFormsRTXloc(...)` und `addWaveFormsDMXloc(...)`
  verschieben die aktuell sichtbare Wellenformdarstellung horizontal.
- Das wird aus `TimeControl.c_setHorizontalTriggerPosition(...)` heraus benutzt.
- Es gibt also bereits eine Render-/Transform-Schicht, die nicht nur "harte"
  Geraete-Kommandos abfeuert, sondern die Sicht auch lokal transformiert.

### `TimeControl`

Verwaltet:

- `timebaseIdx`
- horizontale Triggerposition `horTrgPos`
- Label-/Range-Berechnung
- Submit an die Maschine
- View-Transformation beim Verschieben

Wichtige Erkenntnis:

- Die Zeitbasis ist intern diskret (`timebaseIdx`), nicht kontinuierlich.
- Das spricht dafuer, dass die Live-Hardware nur feste Timebase-Stufen kennt.
- Trotzdem erlaubt die Render-Schicht zusaetzliche lokale Verschiebungen.

## 5. Python-API als Referenz

Die Python-API ist komplett offen und extrem hilfreich, um das Geraeteprotokoll
zu verstehen:

- `api/python/vds1022/vds1022.py`
- `api/python/vds1022/plotter.py`
- `api/python/vds1022/decoder.py`

Wichtige Punkte:

- USB-VID/PID und Befehlsformat sind dort dokumentiert.
- Flash-Layout und FPGA-Download sind dort dokumentiert.
- Channel-/Trigger-/Sampling-Konfiguration ist dort offen nachvollziehbar.

Die Python-API ist die beste "Ground Truth" fuer das Geraet, waehrend die
Java-JAR eher die Ground Truth fuer UI-/Runtime-Verhalten ist.

## 6. Lokaler Decompilation-Workflow

### Verwendete Tools

Lokal vorhanden:

- `java`
- `javac`
- `jar`
- `javap`
- `jdeps`

Nicht lokal vorhanden:

- `cfr`
- `jadx`
- `procyon`

Fuer diese Session wurde CFR lokal in das Workspace geholt:

```bash
mkdir -p .codex-work/tools
curl -L -o .codex-work/tools/cfr.jar https://www.benf.org/other/cfr/cfr-0.152.jar
```

### Extraktion einzelner Klassen

```bash
mkdir -p .codex-work/jar
cd .codex-work/jar
jar xf ../../lib/owon-vds-tiny-1.1.5-cf19.jar \
  com/owon/uppersoft/dso/control/ChartScreenMouseGesture.class
```

### Dekompilieren

```bash
java -jar .codex-work/tools/cfr.jar \
  .codex-work/jar/com/owon/uppersoft/dso/control/ChartScreenMouseGesture.class \
  --outputdir .codex-work/decompile \
  --silent true
```

### Kompilieren gegen die vorhandene JAR

Wichtige Erkenntnis:

- Man muss nicht den kompletten dekompilierten Baum neu bauen.
- Eine einzelne gepatchte Klasse kann gegen die bestehende App-JAR kompiliert werden.
- Das funktioniert gut, solange Signaturen und Imports konsistent bleiben.

Beispiel:

```bash
javac --release 8 \
  -cp 'lib/owon-vds-tiny-1.1.5-cf19.jar:lib/ch.ntb.usb-0.5.9.jar:lib/gson-2.7.0.jar:lib/jxl-2.6.6.jar' \
  -d .codex-work/test-classes \
  .codex-work/decompile/com/owon/uppersoft/dso/control/ChartScreenMouseGesture.java
```

### JAR patchen

Vor dem Patch wurde eine lokale Sicherung angelegt:

```bash
mkdir -p .codex-work/backups
cp lib/owon-vds-tiny-1.1.5-cf19.jar .codex-work/backups/owon-vds-tiny-1.1.5-cf19.jar.orig
```

Danach wurde die neue Klasse eingespielt:

```bash
jar uf lib/owon-vds-tiny-1.1.5-cf19.jar \
  -C .codex-work/test-classes \
  com/owon/uppersoft/dso/control/ChartScreenMouseGesture.class
```

### Verifikation

Die gepatchte Klasse wurde per `javap` gegen die aktualisierte JAR geprueft.

Wichtige Erkenntnis:

- Das ist ein praktikabler Workflow fuer gezielte UI- oder Runtime-Patches.
- Es ist kein Showstopper, dass die Originalquellen fehlen.
- Fuer groessere Umbauten ist das trotzdem deutlich langsamer als mit echten Quellen.

## 7. Relevante UI-/Input-Klassen

Fuer Maus-/Wheel-/Key-Interaktionen sind insbesondere diese Klassen relevant:

- `com.owon.uppersoft.dso.control.ChartScreenMouseGesture`
- `com.owon.uppersoft.dso.control.LeftScreenGesture`
- `com.owon.uppersoft.dso.control.RightScreenGesture`
- `com.owon.uppersoft.dso.control.IntermediateMouseAdapter`
- `com.owon.uppersoft.dso.view.CKeyAdapter`
- `com.owon.uppersoft.dso.view.sub.DetailPane`
- `com.owon.uppersoft.vds.core.zoom.AssitControl`
- `com.owon.uppersoft.dso.view.pane.function.ZoomPane`

### Was diese Klassen tun

#### `ChartScreenMouseGesture`

Primarer Maus-Hotspot fuer das Hauptchart.

Zustaendig fuer:

- Drag auf linker Seite: Kanal-Offset / Pos0
- Drag auf rechter Seite: Trigger-Level
- Drag oben: horizontale Triggerposition
- Center/Mark-Cursor-Interaktion
- Mausrad

Vor dem Patch war `mouseWheelMoved(...)` extrem schlicht:

- Wheel-Rotation wurde direkt an `DetailPane.nextTimeBase(rotation)` gereicht
- also immer nur Timebase hoch/runter
- keine Shift-/Alt-/Middle-Button-Sonderbehandlung

#### `LeftScreenGesture`

Verarbeitet vertikales Verschieben von Kanaelen ueber die linke Kante
und zeigt dabei Pos0-Hilfen an.

#### `RightScreenGesture`

Verarbeitet Trigger-Level-DnD an der rechten Seite.

#### `DetailPane`

Zeigt unten rechts:

- Timebase
- Triggerposition
- Speichertiefe
- Samplingrate

`nextTimeBase(int)` war die alte Wheel-Route.

#### `AssitControl`

Vorhandene Zoom-/Assist-Struktur der App.

Wichtige Erkenntnisse:

- Es gibt Status fuer Main / Assist / Zoom
- `b1` und `b2` sind Zoom-/Assist-Grenzen
- horizontale Verschiebung innerhalb dieser Logik existiert bereits
- die vorhandene Zoom-Logik ist aber nicht direkt modern auf Chart-Gesten gelegt

## 8. In dieser Session gepatchte Interaktion

Die Klasse `ChartScreenMouseGesture` wurde erweitert.

Umgesetzte Belegungen:

- Wheel:
  - unveraendert: Haupt-Timebase wechseln
- `Shift + Wheel`:
  - horizontales Panning
- `Alt + Wheel`:
  - vorhandene Zoom-Assist-Logik verwenden
- `Alt + Shift + Wheel`:
  - feinere horizontale Verschiebung
- `Middle Drag` auf dem Hauptchart:
  - horizontales Panning
  - vertikale Verschiebung des naheliegenden Kanals
- `Shift + Middle Drag` auf dem Hauptchart:
  - horizontale Skalierung ueber die vorhandene Zoom-Assist-Logik

### Wichtige technische Erkenntnis nach dem ersten Realtest

Der erste Implementierungsstand hatte einen zentralen Folgefehler:

- `Shift + Wheel` im gestoppten Zustand bewegte anfangs nur den kleinen grünen
  Horizontal-Trigger-Marker oben im Chart
- die eigentliche Wellenform/Ansicht bewegte sich erst, nachdem vorher einmal
  eine normale Zoom-/Timebase-Aktion ausgefuehrt wurde
- `Alt + Wheel` und `Shift + Middle Drag` veraenderten teilweise bereits die
  angezeigten Werte (`M`, `W`, `Tm`, `Tw`), aber nicht sichtbar die Wellenform

Die Ursache war **nicht primaer in `ChartScreenMouseGesture`**, sondern tiefer
in der Render-/Transform-Gate-Logik:

- `TimeControl.c_setHorizontalTriggerPosition(...)` ruft fuer RT-Daten
  `WaveFormManager.addWaveFormsRTXloc(...)`
- `WaveFormManager.addWaveFormsRTXloc(...)` transformierte die X-Positionen aber
  nur, wenn `ControlManager.allowTransformScreenWaveForm_Ready()` true war
- `allowTransformScreenWaveForm_Ready()` war effektiv nur fuer echten
  Runtime-Betrieb offen
- fuer den Zustand "frisch gelaufen, dann gestoppt" (`recentRunThenStop`) gab es
  bereits eine Sonderbehandlung fuer **vertikale** Transformationen
  (`DataHouse.allowTransformScreenWaveFormVertical()`), aber **keine
  entsprechende horizontale Freigabe**

Deshalb wurde im Stop-Zustand zwar der Trigger-Offset geaendert, aber die
Wellenform blieb auf ihrer alten X-Transformation stehen.

### Nachtraeglicher Fix in dieser Session

Ergaenzt/angepasst:

- `DataHouse.allowTransformScreenWaveFormHorizontal()`
- `WaveFormManager.allowScreenWaveFormTransform()`
- `WaveFormManager.addWaveFormsRTXloc(...)`
- `WaveFormManager.setWaveFormTimebaseRTIndex(...)`

Wirkung:

- horizontales Panning darf nun im Zustand `recentRunThenStop` ebenfalls die
  Bildschirm-Wellenform transformieren
- die vorhandene Zoom-Assist-Schicht kann ihre sichtbaren Zeitbasis-Aenderungen
  im gestoppten Zustand jetzt ebenfalls rendern

Zusatzpatch fuer `Middle Drag`:

- `ChartScreenMouseGesture.applyVerticalMiddlePan(...)` aktualisiert jetzt
  zusaetzlich Cursor-/Pos0-Anzeigen (`computeYValues`, `updatePos0`,
  `update_Pos0`), damit die UI bei vertikalem Verschieben konsistenter bleibt

### Praktische Einschraenkung

Die Timebase des eigentlichen Geraets ist weiterhin diskret.
`Alt + Wheel` und `Shift + Middle Drag` liefern also eine deutlich bessere,
interaktivere Bedienung, aber noch kein mathematisch komplett kontinuierliches
"Pixel-perfect arbitrary zoom".

Fuer einen echten, komplett kontinuierlichen Viewport ueber gestoppte Samples
waere ein tieferer Patch in der Render-/TimeScope-Schicht noetig, wahrscheinlich
um `WFTimeScopeControl`, `WaveFormManager` und ggf. `AssitControl` um einen
eigenen frei skalierbaren Offline-Viewport zu erweitern.

## 9. Noch offene bzw. nicht umgesetzte Punkte

Noch nicht umgesetzt:

- Zoom-to-rectangle / rechteckige Auswahl auf dem Hauptchart
- sauberer, expliziter "Viewport reset"-Shortcut fuer die neuen Gesten
- separate, komplett kontinuierliche Offline-Ansicht nur fuer gestoppte Daten
- Trackpad-freundliche Alternative zur mittleren Maustaste

Empfohlene naechste Schritte:

1. Rechteck-Zoom ueber `ChartScreenMouseGesture`
2. expliziten Reset fuer Viewport/Zoom-Modus einfuehren
3. pruefen, ob bestehende Zoom-/Assist-Schicht fuer gestoppte Frames komplett
   vom Geraetestatus entkoppelt werden kann
4. optional eine sichtbare Hilfe/Overlay fuer die neuen Gesten einbauen

## 10. Vorsichtspunkte

- Die Java-App liegt nur als Binärdatei vor. Vor jeder weiteren Aenderung die JAR sichern.
- Die dekompilierten Quellen in `.codex-work/decompile` sind Arbeitsmaterial, nicht Originalquellen.
- Manche dekompilierten Variablennamen und Kontrollfluesse sind nicht perfekt.
- Die App ist Java-8-kompatibel gebaut; bei Rebuilds immer gegen Bytecode-Level 8 kompilieren.
- Nicht blind die ganze JAR neu bauen. Einzelklassen-Patches sind deutlich robuster.

## 11. Pfade aus dieser Session

- Decompiler-JAR:
  - `.codex-work/tools/cfr.jar`
- dekompilierte Quellen:
  - `.codex-work/decompile/`
- Test-/Patch-Classes:
  - `.codex-work/test-classes/`
- Backup der Original-JAR:
  - `.codex-work/backups/owon-vds-tiny-1.1.5-cf19.jar.orig`

## 12. Kurzes Fazit

Trotz fehlender Original-Java-Quellen ist die App gezielt patchbar.
Der sinnvollste Workflow ist:

1. relevante Klasse per CFR dekompilieren
2. nur diese Klasse patchen
3. gegen die bestehende JAR kompilieren
4. `.class` in die JAR zurueckschreiben
5. Verhalten pruefen

Dieser Ansatz ist fuer gezielte UX-/Input-Patches gut geeignet.
