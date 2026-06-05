@echo off
cd /d "%~dp0"
echo.
echo  EINHAUS Dashboard - GitHub aktualisieren
echo  ==========================================
echo.

git add -A
git commit -m "Dashboard aktualisiert %date% %time%"
git push

echo.
if %errorlevel%==0 (
    echo  Erfolgreich auf GitHub hochgeladen!
) else (
    echo  Fehler beim Hochladen. Bitte Claude fragen.
)
echo.
pause
