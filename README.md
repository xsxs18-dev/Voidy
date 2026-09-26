<p align="center"><img src=".github/assets/icon.png" width="112" alt="Purify"></p>

<h1 align="center">Purify</h1>

<p align="center">
Schlanker System-Cleaner für <b>rootless</b>- und <b>roothide</b>-Jailbreaks.<br>
Natives, minimalistisches iOS-Design, hell und dunkel.
</p>

<p align="center">
<a href="../../releases/latest"><b>Neueste Version herunterladen</b></a>
</p>

---

## Inhalt

- [Funktionen](#funktionen)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [Selbst bauen](#selbst-bauen)
- [Projektaufbau](#projektaufbau)
- [Sicherheit](#sicherheit)
- [Deinstallation](#deinstallation)

## Funktionen

### Reinigen

| Kategorie | Stufe | Inhalt |
|---|---|---|
| App-Caches | Empfohlen | `Library/Caches` der installierten Apps (einzelne Apps ausschließbar) |
| Safari-Cache | Empfohlen | Browser- und WebKit-Caches |
| Temporäre Dateien | Empfohlen | tmp-Ordner von System, Jailbreak und Apps (nur ältere Dateien) |
| Absturzberichte | Empfohlen | Crash- und Diagnoseberichte |
| Log-Dateien | Empfohlen | System- und Jailbreak-Logs (Ordner bleiben erhalten) |
| Paket-Cache | Empfohlen | heruntergeladene `.deb`-Archive und Paketmanager-Caches |
| Tweak-Caches | Empfohlen | Caches von Tweaks und Jailbreak-Apps |
| Repo-Listen | Erweitert | Paketlisten, werden beim nächsten Aktualisieren neu geladen |
| Browserverlauf | Datenschutz | Verlauf und zuletzt geschlossene Tabs |
| Cookies & Website-Daten | Datenschutz | Cookies und gespeicherte Website-Daten |
| Tastatur-Lerndaten | Datenschutz | gelernte Wortvorschläge |

Datenschutz-Kategorien brauchen immer eine eigene Bestätigung und werden nie automatisch gereinigt.

### Smarte Hinweise
Nach jedem Scan wertet Purify die Ergebnisse direkt auf dem Gerät aus. Es werden keine Daten gesendet.
- Zustands-Score von 0 bis 100
- erkennt, wenn ein Prozess wiederholt abstürzt, und verweist auf die Tweak-Liste
- weist auf Apps mit sehr großem Cache hin (z. B. Offline-Musik) und bietet an, sie auszuschließen
- warnt bei fast vollem Speicher

### Tweaks
- alle installierten Tweaks mit Paketname und Ziel-Apps
- Suche und Filter (alle / aktiv / deaktiviert)
- einzeln an- und ausschalten, ohne Dateien zu löschen
- **Alle deaktivieren** zur Fehlersuche und **Wiederherstellen** mit einem Tipp

### Werkzeuge
- **Große Dateien** finden und per Wischgeste löschen
- **Verwaiste Pakete** entfernen (`apt-get autoremove`)
- **Unbenutzte Sprachdateien** in Jailbreak-Apps und Tweaks entfernen
- **Launch-Daemons** des Jailbreaks starten und stoppen
- **Neustart-Optionen**: Respring, Icon-Cache neu aufbauen, Userspace-Neustart, ldrestart, Neustart

### Außerdem
- **Automatische Reinigung** im Hintergrund (alle 6 Stunden bis wöchentlich)
- **Verlauf** aller Reinigungen mit Diagramm
- **Schnellaktionen** auf dem Homescreen-Icon: Smart Clean und Respring
- Deutsch und Englisch

## Voraussetzungen

- iOS 15 oder neuer
- ein **rootless**- oder **roothide**-Jailbreak mit Paketmanager (Sileo, Zebra o. Ä.)

Nur die `.app` zu sideloaden reicht nicht: Purify braucht seinen Root-Helper, der mit dem Paket installiert wird.

## Installation

1. Auf der [Release-Seite](../../releases/latest) die passende Datei laden:

   | Datei | Jailbreak |
   |---|---|
   | `purify_<version>_rootless_iphoneos-arm64.deb` | rootless |
   | `purify_<version>_roothide_iphoneos-arm64e.deb` | roothide |

2. Die `.deb` mit Sileo, Zebra oder Filza öffnen und installieren.
3. Purify vom Homescreen starten.

## Selbst bauen

Benötigt wird [Theos](https://theos.dev) mit Swift-Unterstützung (am einfachsten unter macOS mit Xcode). Für roothide den
[roothide-Fork von Theos](https://github.com/roothide/theos) verwenden.

```sh
# rootless
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

# roothide
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide THEOS=/pfad/zu/roothide-theos
```

Die Pakete landen in `packages/`.

### Automatische Builds & Releases

Jeder Push startet den Workflow `.github/workflows/build.yml`:

1. baut die rootless- und die roothide-Variante auf macOS,
2. setzt die Version automatisch auf `<Version aus control>.<Build-Nummer>` (z. B. `1.1.7`),
3. veröffentlicht beide `.deb`s als GitHub-Release `v<Version>`.

Pull Requests werden nur gebaut, nicht veröffentlicht.

## Projektaufbau

```
app/                 SwiftUI-App
  Sources/           Oberfläche, Datenmodell, Hinweis-Logik
  Resources/         Info.plist, Icons, Übersetzungen
purifyhelper/        Root-Helper (Objective-C), antwortet mit JSON
layout/DEBIAN/       Installations- und Deinstallations-Skripte
control              Paketinformationen
```

**Wie App und Helper zusammenarbeiten:** Die App hat selbst keine Root-Rechte. Für jede Aktion startet sie
`purifyhelper` als root und liest dessen JSON-Antwort. Der Helper ermittelt den Pfad des Jailbreaks zur Laufzeit
über seinen eigenen Speicherort, deshalb läuft derselbe Code unter rootless (`/var/jb`) und roothide.

## Sicherheit

- Der Helper nimmt nur Aufrufe von root oder von der installierten Purify-App an.
- Gelöscht wird nur in fest definierten Bereichen. Fotos, Nachrichten, Kontakte, Schlüsselbund, Mail,
  Einstellungen und die Paketdatenbank sind geschützt.
- Kern-Dienste des Jailbreaks lassen sich in der Daemon-Liste nicht abschalten.
- Tweaks werden nur deaktiviert (Filter-Datei umbenannt), nie gelöscht.

Trotzdem gilt wie bei jedem Jailbreak-Werkzeug: Nutzung auf eigene Verantwortung.

## Deinstallation

Beim Entfernen des Pakets werden automatisch
- alle von Purify deaktivierten Tweaks und Daemons wieder aktiviert und
- die automatische Reinigung entfernt.
