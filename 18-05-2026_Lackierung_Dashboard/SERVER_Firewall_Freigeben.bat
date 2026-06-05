@echo off
title EINHAUS - Firewall freigeben
color 0A
echo.
echo  ============================================
echo   EINHAUS - Firewall Freigabe fuer Port 80
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

echo  Firewall-Regel wird hinzugefuegt...
netsh advfirewall firewall delete rule name="EINHAUS Dashboard HTTP" >nul 2>&1
netsh advfirewall firewall add rule name="EINHAUS Dashboard HTTP" dir=in action=allow protocol=TCP localport=80

echo.
echo  ============================================
echo   Fertig! Firewall ist jetzt freigegeben.
echo  ============================================
echo.
echo  Das Dashboard ist erreichbar unter:
echo.
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    set ip=%%a
    setlocal enabledelayedexpansion
    set ip=!ip: =!
    if not "!ip:~0,8!"=="169.254." echo   http://!ip!/lackierung
    endlocal
)
echo.
echo  Diese Adresse an die Kollegen schicken!
echo.
pause
