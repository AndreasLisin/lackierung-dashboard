@echo off
title EINHAUS - Server Diagnose und Reparatur
color 0A
echo.
echo  ============================================
echo   EINHAUS - Server Diagnose und Reparatur
echo  ============================================
echo.

REM Pruefen ob Administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo  FEHLER: Bitte als Administrator ausfuehren!
    echo  Rechtsklick: "Als Administrator ausfuehren"
    echo.
    pause
    exit
)

echo  [1/6] Webserver (IIS) wird neu installiert...
dism /online /enable-feature /featurename:IIS-WebServer              /all /quiet >nul 2>&1
dism /online /enable-feature /featurename:IIS-DefaultDocument        /all /quiet >nul 2>&1
dism /online /enable-feature /featurename:IIS-StaticContent          /all /quiet >nul 2>&1
dism /online /enable-feature /featurename:IIS-DirectoryBrowsing      /all /quiet >nul 2>&1
dism /online /enable-feature /featurename:IIS-HttpCompressionStatic  /all /quiet >nul 2>&1
echo  [1/6] OK

echo  [2/6] IIS Dienst wird gestartet...
net start W3SVC >nul 2>&1
sc config W3SVC start=auto >nul 2>&1
echo  [2/6] OK

echo  [3/6] Dashboard-Ordner wird erstellt...
if not exist "C:\inetpub\wwwroot\lackierung" mkdir "C:\inetpub\wwwroot\lackierung"
echo  [3/6] OK

echo  [4/6] Dateien werden kopiert...
set QUELLE=%~dp0
copy /Y "%QUELLE%Lackierung_Dashboard.html"     "C:\inetpub\wwwroot\lackierung\index.html"              >nul 2>&1 && echo        - Lackierung_Dashboard.html OK
copy /Y "%QUELLE%Gestellvermessung.html"         "C:\inetpub\wwwroot\lackierung\Gestellvermessung.html"  >nul 2>&1 && echo        - Gestellvermessung.html OK
copy /Y "%QUELLE%Ruestfreigabe_Checkliste.html"  "C:\inetpub\wwwroot\lackierung\Ruestfreigabe_Checkliste.html" >nul 2>&1 && echo        - Ruestfreigabe_Checkliste.html OK
copy /Y "%QUELLE%Wartung_Anlagen.html"           "C:\inetpub\wwwroot\lackierung\Wartung_Anlagen.html"    >nul 2>&1 && echo        - Wartung_Anlagen.html OK
echo  [4/6] OK

echo  [5/6] Firewall wird konfiguriert...
netsh advfirewall firewall delete rule name="EINHAUS Dashboard HTTP" >nul 2>&1
netsh advfirewall firewall add rule name="EINHAUS Dashboard HTTP" dir=in action=allow protocol=TCP localport=80 >nul 2>&1
netsh advfirewall firewall delete rule name="EINHAUS Dashboard HTTPS" >nul 2>&1
netsh advfirewall firewall add rule name="EINHAUS Dashboard HTTPS" dir=in action=allow protocol=TCP localport=443 >nul 2>&1
echo  [5/6] OK

echo  [6/6] IIS wird neu gestartet...
iisreset /restart >nul 2>&1
echo  [6/6] OK

echo.
echo  ============================================
echo   Alles erledigt! Ihre IP-Adresse:
echo  ============================================
echo.
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    set ip=%%a
    setlocal enabledelayedexpansion
    set ip=!ip: =!
    if not "!ip:~0,8!"=="169.254." echo   http://!ip!/lackierung
    endlocal
)
echo.
echo  Teste jetzt vom anderen Rechner!
echo  ============================================
echo.

REM Lokaler Test
echo  Lokaler Test laeuft...
curl -s -o nul -w "  Lokaler Zugriff: %%{http_code}" http://localhost/lackierung/ 2>nul
echo.
echo.
pause
