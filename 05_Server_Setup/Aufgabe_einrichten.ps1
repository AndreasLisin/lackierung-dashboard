#Requires -Version 5.1

# Funktions-Fix 31.08.2026 (Sicherheits-/Funktionsreview): Wartung_Erinnerung.ps1
# liegt nicht in diesem Ordner, sondern in 01_Wartungsuebersicht - das Skript
# brach vorher garantiert mit "nicht gefunden" ab, sobald es ausgefuehrt wurde.
# Achtung, unabhaengig davon: SERVER_Dateien_Kopieren.bat im selben Ordner
# erwartet weiterhin eine FLACHE Ablage (alle HTML-Dateien neben den .bat-Skripten,
# nur 4 von inzwischen ~13 Tools) und passt nicht mehr zur heutigen Ordnerstruktur -
# dieser ganze 05_Server_Setup-Mechanismus wirkt veraltet, seit die Tools auf
# einhaus-report/wincarat-api umgezogen sind. Nur dieser eine Pfad wurde hier
# repariert, die groessere Frage (noch in Benutzung, oder ganz abloesen?) bitte
# separat klaeren.
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ScriptPath = Join-Path (Join-Path (Split-Path -Parent $ScriptDir) '01_Wartungsübersicht') 'Wartung_Erinnerung.ps1'

Write-Host ""
Write-Host " EINHAUS Lackierung - Wartungserinnerung einrichten" -ForegroundColor Cyan
Write-Host " ====================================================="
Write-Host ""

if (-not (Test-Path $ScriptPath)) {
    Write-Host " FEHLER: Wartung_Erinnerung.ps1 nicht gefunden!" -ForegroundColor Red
    Write-Host "         Erwartet unter: $ScriptPath"
    Read-Host "`n Enter zum Beenden"
    exit 1
}

Write-Host " Skript gefunden."
Write-Host " Registriere Aufgabe im Windows Aufgabenplaner ..."
Write-Host ""

try {
    $action  = New-ScheduledTaskAction `
                   -Execute  'powershell.exe' `
                   -Argument "-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$ScriptPath`""

    $trigger = New-ScheduledTaskTrigger -Daily -At '07:30AM'

    $task = Register-ScheduledTask `
                -TaskName 'EINHAUS Wartungserinnerung' `
                -Action   $action `
                -Trigger  $trigger `
                -RunLevel Highest `
                -Force

    Write-Host " Erfolgreich eingerichtet!" -ForegroundColor Green
    Write-Host ""
    Write-Host ("  Name:     " + $task.TaskName)
    Write-Host  "  Zeitplan: Taeglich um 07:30 Uhr"
    Write-Host  "  Status:   Bereit"

} catch {
    Write-Host ""
    Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host " Bitte die VBS-Datei als Administrator ausfuehren."
}

Write-Host ""
Read-Host " Enter zum Beenden drucken"
