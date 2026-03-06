# Zeiterfassungs-App für macOS – Allgemeiner Überblick

## Ziel

Eine native macOS-Menubar-App, die auf Knopfdruck aufzeichnet, welche Anwendungen wie lange aktiv waren. Für Firefox wird zusätzlich die Domain des aktiven Tabs erfasst. Die Daten werden als CSV-Datei pro Aufzeichnungszyklus gespeichert.

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
start_time,end_time,duration_seconds,app_name,firefox_domain
2025-01-15 09:00:00,2025-01-15 09:04:23,263,Firefox,github.com
2025-01-15 09:04:23,2025-01-15 09:11:05,402,Xcode,
2025-01-15 09:11:05,2025-01-15 09:13:00,115,Firefox,stackoverflow.com
```

- `firefox_domain` ist nur befüllt, wenn die aktive App Firefox ist
- Dateiname: `session_YYYY-MM-DD_HH-mm-ss.csv`
- Speicherort: frei wählbar (z. B. `~/Documents/TimeTracking/`)

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

## Offene Fragen / Entscheidungspunkte

1. **Menubar-App oder Dock-App?** — Menubar ist weniger aufdringlich, da sie immer läuft
2. **Polling-Intervall für Firefox-URL** — Die Accessibility API wird nicht benachrichtigt bei Tab-Wechseln; es muss gepollt werden (z. B. alle 2 Sekunden). Welches Intervall ist sinnvoll?
3. **Mindeststdauer für Einträge** — Sollen App-Wechsel unter 1 Sekunde ignoriert werden?
4. **Speicherort der CSV** — Festes Verzeichnis vs. wählbarer Ordner per Dialog
5. **Chromium-basierte Browser** (Chrome, Edge, Brave) — Gleiches Prinzip wie Firefox; soll das ebenfalls unterstützt werden?
