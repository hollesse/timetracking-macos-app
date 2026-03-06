# Zeiterfassungs-App für macOS – Allgemeiner Überblick

## Ziel

Eine native macOS-Menubar-App, die auf Knopfdruck aufzeichnet, welche Anwendungen wie lange aktiv waren. Für Firefox wird zusätzlich die Domain des aktiven Tabs erfasst. Die Daten werden als CSV-Datei pro Aufzeichnungszyklus gespeichert.

> **Getroffene Entscheidungen:** Browser-Tracking initial nur für Firefox. Speicherort wird beim ersten App-Start per Ordner-Dialog ausgewählt und kann in den App-Settings geändert werden. App-Wechsel kürzer als 2 Sekunden werden ignoriert.

---

## Kernfunktionalität

| Funktion | Beschreibung |
|---|---|
| **Start/Stopp** | Nutzer startet und beendet eine Aufzeichnungssession manuell |
| **App-Tracking** | Erkennt, welche App gerade im Vordergrund ist, und misst die Nutzungsdauer |
| **Firefox-Tab-Tracking** | Liest zusätzlich die Domain des aktuell geöffneten Firefox-Tabs aus |
| **CSV-Export** | Pro Session wird eine CSV-Datei mit allen Einträgen gespeichert |

---

## Technischer Ansatz

### Plattform & Sprache
- **Native macOS-App** mit Swift + SwiftUI
- Deployment Target: macOS 13+ (Ventura)
- Verteilt als eigenständige `.app` ohne App Store (kein Sandboxing-Zwang)

### App-Tracking
macOS stellt über das Framework `NSWorkspace` Benachrichtigungen bereit, wenn der Nutzer zwischen Anwendungen wechselt:
- `NSWorkspace.didActivateApplicationNotification` — feuert bei jedem App-Wechsel
- Darüber werden Start- und Endzeitpunkt jedes App-Fokus-Zeitraums erfasst

### Firefox-Tab-Tracking
Firefox bietet keine vollständige AppleScript-Unterstützung für URLs. Es gibt zwei realistische Wege:

#### Option A – Accessibility API (kein Extension-Aufwand)
- macOS erlaubt es, via `AXUIElement` die Inhalte von UI-Elementen anderer Apps auszulesen
- Die Adressleiste von Firefox ist über die Accessibility-Hierarchie erreichbar
- **Voraussetzung:** Der Nutzer muss der App einmalig Berechtigung unter *Systemeinstellungen → Datenschutz → Bedienungshilfen* erteilen
- Die vollständige URL wird ausgelesen, danach wird nur die Domain (Host) extrahiert und gespeichert

#### Option B – Native Messaging + Firefox-Extension
- Eine kleine Firefox-Erweiterung sendet die aktuelle URL über die Native Messaging API an die macOS-App
- Zuverlässiger, aber deutlich mehr Aufwand (Extension + Messaging Host)

**Empfehlung: Option A** für den ersten Ansatz, da kein Browser-Addon nötig ist.

### CSV-Format

```
start_time,end_time,duration_seconds,duration_formatted,app_name,web_domain
2025-01-15 09:00:00,2025-01-15 09:04:23,263,00:04:23,Firefox,github.com
2025-01-15 09:04:23,2025-01-15 09:11:05,402,00:06:42,Xcode,
2025-01-15 09:11:05,2025-01-15 09:13:00,115,00:01:55,Firefox,stackoverflow.com
```

- `duration_seconds` — rohe Sekunden für maschinelle Weiterverarbeitung
- `duration_formatted` — menschenlesbare Darstellung im Format `HH:MM:SS` (z. B. `01:12:05` für 1h 12m 5s)
- `web_domain` — nur befüllt, wenn die aktive App ein unterstützter Browser (aktuell: Firefox) ist; Feldname ist browser-agnostisch gehalten für spätere Erweiterung
- App-Wechsel mit einer Dauer < 2 Sekunden werden **nicht** aufgezeichnet
- Dateiname: `session_YYYY-MM-DD_HH-mm-ss.csv`
- Speicherort: beim ersten App-Start via Ordner-Dialog festgelegt, änderbar in den App-Settings

---

## App-Architektur (Komponenten-Überblick)

```
┌─────────────────────────────────────────────────┐
│                  macOS Menu Bar App              │
│                                                 │
│  ┌─────────────┐    ┌──────────────────────┐    │
│  │  UI Layer   │    │   TrackingService    │    │
│  │  (SwiftUI)  │◄──►│  (NSWorkspace +      │    │
│  │             │    │   AXUIElement)       │    │
│  │  [Start]    │    └──────────┬───────────┘    │
│  │  [Stop]     │               │                │
│  │  Status-    │    ┌──────────▼───────────┐    │
│  │  anzeige    │    │   SessionManager     │    │
│  └─────────────┘    │  (Zeitstempel,       │    │
│                     │   Einträge sammeln)  │    │
│                     └──────────┬───────────┘    │
│                                │                │
│                     ┌──────────▼───────────┐    │
│                     │    CSVExporter       │    │
│                     │  (Datei schreiben)   │    │
│                     └──────────────────────┘    │
└─────────────────────────────────────────────────┘
```

### Komponenten

- **TrackingService** – Beobachtet App-Wechsel via `NSWorkspace`, fragt bei Firefox die URL per Accessibility API ab
- **SessionManager** – Verwaltet den laufenden Aufzeichnungszyklus und akkumuliert `TrackingEntry`-Objekte
- **CSVExporter** – Wandelt die gesammelten Einträge am Sitzungsende in eine CSV-Datei um
- **UI (SwiftUI / MenuBar)** – Einfache Menubar-App mit Start/Stopp und optionalem Popover für den Status

---

## Berechtigungen & Datenschutz

| Berechtigung | Zweck | Wo erteilen |
|---|---|---|
| **Bedienungshilfen (Accessibility)** | URL-Leiste von Firefox auslesen | Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen |
| *(optional)* Screen Recording | Nicht zwingend nötig, nur falls Fenstertitel ausgelesen werden sollen | Systemeinstellungen → Datenschutz & Sicherheit → Bildschirmaufnahme |

Die App greift **nicht** auf persönliche Daten zu – sie liest lediglich den sichtbaren Inhalt der Adressleiste.

---

## Entscheidungen (getroffen)

| Thema | Entscheidung |
|---|---|
| Browser-Support | Initial nur Firefox; Feld `web_domain` ist bereits browser-agnostisch benannt |
| Speicherort | Erster Start: Ordner-Dialog; danach änderbar direkt aus dem Menü via `NSOpenPanel` (kein Extra-Fenster nötig) |
| Mindestdauer | App-Wechsel < 2 Sekunden werden verworfen |
| Dauer-Format | Zwei Spalten: `duration_seconds` (roh) + `duration_formatted` (HH:MM:SS) |
| App-Typ | Menubar-App (kein Dock-Icon), weniger aufdringlich |
| Polling-Intervall Firefox | 2 Sekunden (deckt sich mit Mindestdauer-Filter) |
| Berechtigungs-Onboarding | Beim ersten Start: Hinweis-Popover mit Button, der direkt in *Systemeinstellungen → Bedienungshilfen* springt (`NSWorkspace.open` mit Deep-Link); Tracking kann erst starten, wenn Berechtigung erteilt ist |
| Settings-Fenster | Kein eigenes Fenster — Ordner-Auswahl öffnet `NSOpenPanel` direkt aus dem Menüeintrag heraus |

## Offene Fragen

Alle wesentlichen Designentscheidungen sind getroffen. Der Plan ist bereit für die Implementierung.
