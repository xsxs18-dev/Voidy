<p align="center"><img src=".github/assets/icon.png" width="120" alt="Purify icon"></p>

<h1 align="center">Purify</h1>
<p align="center"><b>Smarter System-Cleaner für rootless & roothide Jailbreaks</b><br>
Die Idee von iCleaner Pro, neu gebaut für moderne Jailbreaks: sauberer Code, modernes UI, weniger Ballast.</p>

---

## Features

### Reinigen
| Kategorie | Stufe | Was passiert |
|---|---|---|
| App-Caches | Empfohlen | `Library/Caches` aller App-Container (Ausschlüsse möglich) |
| Safari-Cache | Empfohlen | Safari- & WebKit-Caches |
| Temporäre Dateien | Empfohlen | tmp-Ordner (System, Jailbreak, Apps) – nur Dateien älter als 24 h bzw. 1 h |
| Absturzberichte | Empfohlen | CrashReporter / DiagnosticReports |
| Log-Dateien | Empfohlen | Jailbreak-Logs & `/var/mobile/Library/Logs` (Ordner bleiben erhalten) |
| Paket-Cache | Empfohlen | alte `.deb`-Archive, APT-`*.bin`, Sileo/Zebra/Cydia/Filza-Caches |
| Tweak- & geteilte Caches | Empfohlen | Caches von Tweaks und Drittanbieter-Diensten (nie `com.apple.*`) |
| Repo-Listen | Erweitert | APT-/Sileo-Listen (werden beim nächsten Refresh neu geladen) |
| Browserverlauf | Datenschutz | Safari `History.db`, zuletzt geschlossene Tabs |
| Cookies & Website-Daten | Datenschutz | Cookies, LocalStorage, WebsiteData |
| Tastatur-Lerndaten | Datenschutz | dynamisches Wörterbuch / Wortvorschläge |

Laufende Prozesse (Safari, kbd, Sileo, Zebra) werden vor dem Reinigen beendet, damit nichts Halbes übrig bleibt.

### Purify Intelligence (Smart-Assistent)
Eine Regel-Engine, die komplett **auf dem Gerät** läuft (keine Cloud, kein Tracking). Aus dem Scan macht sie:
- eine Zusammenfassung in normaler Sprache („Ich habe 1,4 GB gefunden…“)
- einen **Zustands-Score** (0–100)
- **Smart Insights** mit Ein-Tipp-Aktionen, z. B.:
  - erkennt **Absturzschleifen** („SpringBoard ist 12-mal abgestürzt – vielleicht macht ein Tweak Probleme“)
  - warnt, wenn eine App riesige Caches hat (evtl. Offline-Musik/Karten) und bietet an, sie auszuschließen
  - warnt bei fast vollem Speicher und führt direkt zu „Große Dateien“
  - schlägt die automatische Reinigung vor, wenn du länger nicht gereinigt hast

### Tweaks
- alle Tweaks mit Paketname und Ziel-Apps (Filter), Suche, Filter Aktiv/Deaktiviert
- einzeln an/aus (umbenennen der Filter-`.plist` – die dylib bleibt unangetastet)
- **„Alle deaktivieren“** zur Fehlersuche + **Wiederherstellen** mit einem Tipp
- versteht auch das alte iCleaner-Format (`Tweak.disabled`)

### Werkzeuge
- **Große Dateien** finden & löschen (Fotos, Nachrichten, Keychain & dpkg-Datenbank sind geschützt)
- **Verwaiste Pakete** (`apt-get autoremove`)
- **Unbenutzte Sprachen** in Jailbreak-Apps & Tweaks (System-Apps werden nie angefasst)
- **Launch-Daemons** des Jailbreaks starten/stoppen (Kern-Dienste von Dopamine/roothide/ElleKit sind gesperrt)
- **Neustart-Optionen**: Respring, uicache, Userspace-Reboot, ldrestart, Reboot

### Design
Natives, minimalistisches iOS-Design wie in den Einstellungen oder Filza: gruppierte Listen, Systemfarben,
Wischgesten, Suche und Pull-to-Refresh – automatisch im Hell- und Dunkelmodus.

### Sonstiges
- **Automatische Reinigung** per LaunchDaemon (6 h … wöchentlich), Datenschutz-Kategorien sind davon ausgeschlossen
- **Verlauf & Statistik** (inkl. automatischer Reinigungen)
- **Homescreen-Quick-Actions**: „Smart Clean“ und „Respring“ (lange auf das Icon drücken)
- Deutsch & Englisch

## Aufbau

```
app/            SwiftUI-App (iOS 15+)
purifyhelper/   Root-Helper in Objective-C, spricht JSON auf stdout
layout/DEBIAN/  postinst/prerm/postrm
```

Die App startet `purifyhelper` mit der Root-Persona (wie TrollStore-Apps) und fällt sonst auf das setuid-Bit zurück.
Der Helper findet den Jailbreak-Root **zur Laufzeit** über seinen eigenen Pfad – deshalb funktioniert dieselbe Codebasis unter
rootless (`/var/jb`) und roothide (`.jbroot-XXXX`), ohne harte Pfade. Er akzeptiert nur Aufrufe von root oder von der installierten Purify.app.

Bei Deinstallation werden von Purify deaktivierte Tweaks und Daemons automatisch wieder aktiviert und der Zeitplan entfernt.

## Bauen

Voraussetzung: [Theos](https://theos.dev) (für roothide der [roothide-Fork](https://github.com/roothide/theos)) mit Swift-Unterstützung (macOS + Xcode empfohlen).

```sh
# rootless (Dopamine, palera1n rootless, …)
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

# roothide (Dopamine roothide / Bootstrap)
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide THEOS=/pfad/zu/roothide-theos
```

Einfacher: Jeder Push baut beide Pakete über **GitHub Actions** und veröffentlicht sie automatisch als
**Release** (`v<Version>.<Build-Nummer>`, z. B. `v1.1.12`). Die neuesten `.deb`s findest du also immer unter
**Releases** rechts auf der Repo-Seite.

## Installation

Die `.deb` mit Sileo/Zebra/Filza installieren. **Nur die .app zu sideloaden reicht nicht** – ohne den Root-Helper kann Purify keine Systembereiche reinigen.

## Hinweis

Purify löscht nur Daten aus klar definierten Bereichen und bietet für alles, was Anmeldungen oder Verlauf betrifft, eine eigene
Bestätigung. Trotzdem gilt wie bei jedem Jailbreak-Tool: Nutzung auf eigenes Risiko.
