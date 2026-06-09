# DashboardFlow Mac

Native macOS-App für das ServerFlow/Laravel-Dashboard. Sie zeigt die
Dashboard-Oberfläche als WebView in einem eigenen Mac-Fenster und ergänzt sie um
eine native Navigation und ein Menüleisten-Symbol mit Server-Auslastung.

## Voraussetzungen

- macOS 13 oder neuer
- Xcode oder die Xcode Command Line Tools (`xcode-select --install`) – stellt `swiftc` bereit

## Build

```bash
./build.sh
```

Das fertige App-Bundle liegt danach unter:

```text
build/DashboardFlow.app
```

Starten mit:

```bash
open build/DashboardFlow.app
```

## Funktionen

- WebView-Wrapper für die Routen Dashboard, Workflow, Server, Docker,
  Cloudflare, Kosten, Alerts und Profil in einem nativen Mac-Fenster
- Native **Flow Map** mit einer Übersicht über die DashboardFlow-Architektur
- Umgebungs-Umschalter in der Toolbar: **Production**
  (`https://serverflow.careflow-pflege.de`), **Lokal :8000** und **Lokal :8080**
- Menüleisten-Symbol mit kompakter CPU-/RAM-/Disk-Übersicht für alle Server
  (Label `DF`)
- Eigenes DashboardFlow-App-Icon

## Menüleiste: Server-Auslastung

Klick auf das Server-/Gauge-Symbol in der macOS-Menüleiste. Beim ersten Mal
meldest du dich mit deiner ServerFlow-E-Mail und deinem Passwort an; daraus wird
ein Sanctum-API-Token erstellt. Das Token wird lokal in den App-Einstellungen
gespeichert, und der Popover aktualisiert die Server-Auslastung alle 60 Sekunden,
solange die App läuft.

Ist das Menüleisten-Symbol nicht sichtbar, beende eine bereits laufende
DashboardFlow-Instanz und öffne die neu gebaute App erneut.

## Lokale Nutzung

Laravel lokal starten und dann in der Toolbar **Lokal :8000** oder
**Lokal :8080** auswählen.
