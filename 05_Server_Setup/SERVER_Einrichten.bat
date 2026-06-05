@echo off
title EINHAUS - Server Einrichten
color 0A
echo.
echo  ============================================
echo   EINHAUS - Lackierung Dashboard Server
echo   Schritt 1: Server einrichten
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

echo  [1/4] Windows-Webserver wird aktiviert...
dism /online /enable-feature /featurename:IIS-WebServer          /all /quiet >nul 2>&1
dism /online /enable-feature /featurename:IIS-DefaultDocument    /all /quiet >nul 2>&1
dism /online /enable-feature /featurename:IIS-StaticContent      /all /quiet >nul 2>&1
dism /online /enable-feature /featurename:IIS-HttpCompressionStatic /all /quiet >nul 2>&1
echo  [1/4] Fertig!

echo  [2/4] Dashboard-Ordner wird erstellt...
if not exist "C:\inetpub\wwwroot\lackierung" mkdir "C:\inetpub\wwwroot\lackierung"
echo  [2/4] Fertig!

echo  [3/4] Webserver wird gestartet...
net start W3SVC >nul 2>&1
sc config W3SVC start=auto >nul 2>&1
echo  [3/4] Fertig!

echo  [4/4] IP-Adresse wird ermittelt...
echo.
echo  ============================================
echo   Ihre IP-Adresse im Firmennetz:
echo  ============================================
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    set ip=%%a
    setlocal enabledelayedexpansion
    set ip=!ip: =!
    if not "!ip:~0,8!"=="169.254." echo   http://!ip!/lackierung
    endlocal
)
echo  ============================================
echo.
echo  Naechster Schritt:
echo  Fuehre "SERVER_Dateien_Kopieren.bat" aus!
echo.
pause
