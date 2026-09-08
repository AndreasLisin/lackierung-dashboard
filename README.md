# Lackierung-Dashboard

Sammlung operativer Paint-Shop-Werkzeuge der EINHAUS Oberflächenveredelung GmbH als statische
HTML-Seiten (kein Build-Schritt, kein Server nötig), ausgeliefert über GitHub Pages. Die meisten
Module sind inzwischen auf einen internen Ersatz umgezogen; Details je Modul siehe unten.

## Was hier noch live ist

| Modul | Datei | Zweck |
|---|---|---|
| Rüstfreigabe Lackierkabinen | `04_Rüstfreigabe_Lackierkabinen/Ruestfreigabe_Mobil.html` | Eingabe der Rüstfreigabe-Checkliste (Tablet/Handy) |
| Rüstfreigabe Lackierkabinen | `04_Rüstfreigabe_Lackierkabinen/Ruestfreigabe_Dashboard.html` | Auswertung der erfassten Rüstfreigaben |
| Schulungsnachweis Q-Zirkel | `09_Schulungsnachweis/Schulungsnachweis_Ausschuss.html` | Übersicht Schulungsstatus (Q-Zirkel) |
| REFA-Zeitaufnahme | `11_Zeitaufnahme/Zeitaufnahme_Tablet.html` | Stoppuhr-Erfassung |
| REFA-Zeitaufnahme | `11_Zeitaufnahme/Zeitaufnahme_Auswertung.html` | Vorgabezeiten + Kapazitätsrechner |

Startseite mit allen Kacheln: `index.html`.

## Offline / migriert (nur noch als Hinweisseite in diesem Repo)

Wartungsübersicht, OEE Kabine 1, OEE Beflammroboter, Lackformeln, Lackaufbauten sind von GitHub
Pages genommen worden (öffentlicher Supabase-Zugriff war ein Sicherheitsrisiko). Die jeweilige
Datei zeigt nur noch einen Hinweis „Diese Seite ist offline" mit Link zum internen Ersatz.
Gestellvermessung und Rüstfreigabe Lackierroboter sind unverändert als eigenständige Prototypen
im Repo, aber nicht über `index.html` verlinkt.

## Starten

Kein Build, kein Server-Prozess. Datei direkt im Browser öffnen (Doppelklick oder
`start index.html` unter Windows) oder über die veröffentlichte GitHub-Pages-URL aufrufen.

## Testen

Es gibt keine automatisierten Tests (reine HTML/JS-Seiten ohne Build). Manuell prüfen:

1. Betroffene Datei im Browser öffnen, Konsole auf Fehler prüfen (F12 → Console).
2. Formular mit Testdaten durchklicken (Rüstfreigabe: alle Checkpunkte + Bemerkungsfeld inkl.
   Sonderzeichen wie `<script>` zum Prüfen der XSS-Filterung).
3. Bei Skripten mit Seiteneffekten (`*.ps1`) das jeweilige Testkonto benutzen, sofern vorhanden —
   Details stehen als Kommentar im jeweiligen Skriptkopf.

## Datenregeln

Keine echten Kunden- oder Personendaten in diesem Repo — nur erfundene Testdaten, als
`***TEST***`/`***DUMMY***` gekennzeichnet.
