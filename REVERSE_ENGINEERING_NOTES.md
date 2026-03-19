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

### Stabiler Minimalstand nach Rollback und Neuansatz

Nach dem fehlgeschlagenen ersten Versuch wurde die App-JAR vollstaendig auf das
Backup zurueckgesetzt und anschliessend nur **ein einzelner, kleiner Patch**
neu aufgebaut.

Der funktionierende Minimalpatch aendert ausschliesslich:

- `ChartScreenMouseGesture.mouseWheelMoved(...)`

Und zwar nur fuer:

- `Shift + Wheel`
- `Alt + Shift + Wheel`

Technischer Ansatz:

- **kein** Patch mehr in `DataHouse`
- **kein** Patch mehr in `WaveFormManager`
- **kein** Patch mehr in der TimeScope-/Render-Gate-Logik
- horizontales Panning laeuft stattdessen ueber denselben UI-Pfad wie die
  funktionierenden Tastaturbefehle:
  `DetailPane.getHorizontalTriggerPosition()` ->
  `DetailPane.setHorizontalTriggerPosition(...)`

Das ist wichtig, weil damit exakt der bereits vorhandene und im Original
funktionierende Horizontal-Trigger-/Panning-Mechanismus genutzt wird, statt
neue Transformationslogik in die Render-Schicht einzubauen.

Verifiziert durch Realtest:

- App startet normal
- Samples werden normal angezeigt
- `Shift + Wheel` verschiebt im Stop-Modus direkt die sichtbaren Samples
- der gruene Marker wandert konsistent mit
- `T` unten rechts wird passend aktualisiert
- `Alt + Shift + Wheel` erlaubt feinere horizontale Verschiebungen
- `Middle Drag` funktioniert stabil als reines horizontales Panning
- `Shift + Middle Drag` funktioniert als erster Continuous-Zoom-Prototyp im Stop-Modus
- die Skalierung erfolgt ueber vertikale Mausbewegung, nicht ueber links/rechts
- eine zu enge erste Zoom-Grenze wurde bereits erweitert

Umgesetzte Belegungen:

- Wheel:
  - unveraendert: Haupt-Timebase wechseln
- `Shift + Wheel`:
  - horizontales Panning
- `Alt + Shift + Wheel`:
  - feinere horizontale Verschiebung

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

### Fehlansatz aus dem ersten Versuch

Im ersten Versuch wurden zusaetzlich folgende Kernklassen veraendert:

- `DataHouse`
- `WaveFormManager`
- Teile der `Middle Drag`-Logik in `ChartScreenMouseGesture`

Das war zu invasiv. Ergebnis:

- Samples wurden nicht mehr korrekt angezeigt
- Connect/Offline-Status zeigte fehlerhaftes Verhalten
- die App war funktional regressiv

### Praktische Einschraenkung

Die Timebase des eigentlichen Geraets ist weiterhin diskret. Der aktuell
funktionierende Patch verbessert bislang nur die horizontale Navigation im
Stop-Modus; er fuehrt noch **keinen** neuen frei skalierbaren Software-Viewport
ein.

Fuer einen echten, komplett kontinuierlichen Viewport ueber gestoppte Samples
waere ein tieferer Patch in der Render-/TimeScope-Schicht noetig, wahrscheinlich
um `WFTimeScopeControl`, `WaveFormManager` und ggf. `AssitControl` um einen
eigenen frei skalierbaren Offline-Viewport zu erweitern.

## 9. Noch offene bzw. nicht umgesetzte Punkte

Noch nicht umgesetzt:

- `Alt + Wheel`
- Zoom-to-rectangle / rechteckige Auswahl auf dem Hauptchart
- sauberer, expliziter "Viewport reset"-Shortcut fuer die neuen Gesten
- vertikales Panning per `Middle Drag`
- Verbesserung des Zoom-Ankerpunkts bei `Shift + Middle Drag`
- Absicherung, dass `ms/div` und Raster bei Continuous Zoom semantisch sauber zusammenpassen
- separate, komplett kontinuierliche Offline-Ansicht nur fuer gestoppte Daten
- Trackpad-freundliche Alternative zur mittleren Maustaste

### Erkenntnis zu `Middle Drag`

Ein Zwischenstand hatte `Middle Drag` so umgesetzt, dass vertikale Mausbewegungen
den Kanal-`pos0` bzw. den vertikalen Kanal-Offset veraenderten.

Das war aus UI-Sicht falsch:

- die grünen Horizontal-Linien und deren Spannungslabels blieben an ihrer
  Bildschirmposition
- nur die numerischen Werte wurden neu berechnet
- das Verhalten entsprach also einer Kanal-/Referenzverschiebung, nicht einem
  Viewport-Pan

Deshalb wurde der vertikale Anteil wieder entfernt.

Aktueller Stand:

- `Middle Drag` = **nur horizontales Panning**

Wenn spaeter vertikales Panning gewuenscht ist, braucht es einen echten
Viewport-/View-Transform-Ansatz und nicht das Wiederverwenden der bestehenden
`pos0`-Kanalverschiebung.

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

## 12. Persistenz / Preferences

Beim Analysieren von nicht gespeicherten UI-Einstellungen fiel ein wichtiger
Architekturfehler in `WorkBenchTiny` auf.

### Relevante Dateien

- `com/owon/uppersoft/dso/global/WorkBenchTiny.java`
- `com/owon/uppersoft/dso/global/ConfigFactoryTiny.java`
- `com/owon/uppersoft/vds/core/pref/Config.java`
- `com/owon/uppersoft/dso/global/ControlManager.java`
- `com/owon/uppersoft/dso/view/TipsWindow.java`

### Relevante Dateien auf Platte

Unter macOS liegen die lokalen Settings hier:

- `~/Library/Application Support/OWON VDS1022/preferences.ini`
- `~/Library/Application Support/OWON VDS1022/preferences-default.ini`

Beobachteter Zustand:

- `preferences.ini` und `preferences-default.ini` koennen gleichzeitig existieren
- `TipsWindowShow` lag in beiden Dateien auf `1`
- `CH1.couplingIdx` / `CH2.couplingIdx` konnten sich zwischen beiden Dateien
  unterscheiden

### Wichtigste Erkenntnis

`ConfigFactoryTiny.createConfig(...)` laedt beim Start zunaechst eine echte
Session-Datei in `Config.sessionProperties`.

`WorkBenchTiny` hat danach aber **zu spaet** noch einmal
`preferences-default.ini` geladen und per `config.setSessionProperties(...)`
eingesetzt, nachdem `CoreControlTiny`, `ControlManagerTiny` und der Rest der
App bereits initialisiert worden waren.

Dadurch entstanden zwei Probleme:

- Ein Teil der App wurde mit den beim Start geladenen Werten initialisiert
- spaetere `persist(...)`-Aufrufe liefen aber gegen ein anderes `Pref`-Objekt

Das ist eine sehr wahrscheinliche Ursache fuer merkwuerdig inkonsistentes
Persistenzverhalten.

### Save-/Load-Semantik

Wichtige Beobachtung:

- `ControlManager.persist(pref)` schreibt nur in ein `Pref`-Objekt im Speicher
- erst `Pref.store(...)` oder `Config.persist(...)` schreibt wirklich auf Platte

Zusatzproblem im Originalfluss:

- `WorkBenchTiny.exit()` schrieb `sessionProperties` direkt in
  `preferences-default.ini`
- davor wurde das `Pref`-Objekt aber **nicht** mit dem aktuellen Runtime-State
  per `ctrlMgr.persist(pref)` aktualisiert

Das bedeutet:

- selbst wenn sich Runtime-Flags geaendert hatten, konnte
  `preferences-default.ini` veraltete Werte enthalten

### Implementierter Fix in dieser Session

`WorkBenchTiny` wurde lokal so angepasst:

1. Beim Start wird zuerst `preferences-default.ini` verwendet, falls sie
   existiert.
2. Nur wenn diese Datei fehlt, faellt der Start auf `preferences.ini` zurueck.
3. Der spaete `config.setSessionProperties(...)`-Tausch im Konstruktor wurde
   entfernt.
4. Beim Beenden wird vor dem Schreiben von `preferences-default.ini` explizit
   `ctrlMgr.persist(sessionProperties)` aufgerufen.

Ziel des Fixes:

- konsistenteres Laden der letzten Session
- konsistenteres Schreiben der aktuellen Session
- keine nachtraegliche Entkopplung zwischen geladenen und spaeter persistierten
  `Pref`-Objekten

### Tips-Dialog

Der "Don't show again"-Schalter im Tips-Dialog macht lokal nur:

- `cm.istipsWindowShow = !hiddenCb.isSelected()`

Er persistiert **nicht direkt** selbst. Deshalb ist der korrekte Exit-/Save-Pfad
entscheidend dafuer, dass `TipsWindowShow` spaeter wirklich auf `0` landet.

### Wichtiger Debug-Hinweis

Wenn wieder Persistenzprobleme auftauchen, zuerst beide Dateien vergleichen:

- `preferences.ini`
- `preferences-default.ini`

Insbesondere diese Keys sind gute Indikatoren:

- `TipsWindowShow`
- `CH1.couplingIdx`
- `CH2.couplingIdx`
- `Timebase.index`
- `HorTrgPos`

## 13. Kurzes Fazit

Trotz fehlender Original-Java-Quellen ist die App gezielt patchbar.
Der sinnvollste Workflow ist:

1. relevante Klasse per CFR dekompilieren
2. nur diese Klasse patchen
3. gegen die bestehende JAR kompilieren
4. `.class` in die JAR zurueckschreiben
5. Verhalten pruefen

Dieser Ansatz ist fuer gezielte UX-/Input-Patches gut geeignet.
