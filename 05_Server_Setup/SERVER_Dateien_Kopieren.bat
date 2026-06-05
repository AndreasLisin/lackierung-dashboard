@echo off
title EINHAUS - Dateien auf Server kopieren
color 0A
echo.
echo  ============================================
echo   EINHAUS - Lackierung Dashboard Server
echo   Schritt 2: Dateien kopieren
echo  ============================================
echo.

REM Pruefen ob Administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo  FEHLER: Bitte als Administrator ausfuehren!
    echo  Rechtsklick auf diese Datei und "Als Administrator ausfuehren"
    echo.
    pause
    exit
)

REM Zielordner
set ZIEL=C:\inetpub\wwwroot\lackierung

REM Pruefen ob Zielordner existiert
if not exist "%ZIEL%" (
    echo  FEHLER: Ordner nicht gefunden!
    echo  Bitte zuerst SERVER_Einrichten.bat ausfuehren.
    echo.
    pause
    exit
)

echo  Dateien werden kopiert...
echo.

REM Alle HTML Dateien aus dem gleichen Ordner wie diese BAT-Datei kopieren
set QUELLE=%~dp0

copy /Y "%QUELLE%Lackierung_Dashboard.html"    "%ZIEL%\index.html"               && echo  [OK] Lackierung_Dashboard.html
copy /Y "%QUELLE%Gestellvermessung.html"        "%ZIEL%\Gestellvermessung.html"   2>nul && echo  [OK] Gestellvermessung.html
copy /Y "%QUELLE%Ruestfreigabe_Checkliste.html" "%ZIEL%\Ruestfreigabe_Checkliste.html" 2>nul && echo  [OK] Ruestfreigabe_Checkliste.html
copy /Y "%QUELLE%Wartung_Anlagen.html"          "%ZIEL%\Wartung_Anlagen.html"     2>nul && echo  [OK] Wartung_Anlagen.html

echo.
echo  ============================================
echo   Alle Dateien wurden kopiert!
echo  ============================================
echo.
echo  Das Dashboard ist jetzt erreichbar unter:
echo.
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    set ip=%%a
    setlocal enabledelayedexpansion
    set ip=!ip: =!
    echo   http://!ip!/lackierung
    endlocal
)
echo.
echo  Im Homeoffice: VPN verbinden, dann gleiche Adresse!
echo.
echo  TIPP: Diese Datei erneut ausfuehren wenn neue
echo  Dateien hinzugefuegt oder aktualisiert wurden.
echo.
pause
