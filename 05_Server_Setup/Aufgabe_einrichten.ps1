#Requires -Version 5.1

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ScriptPath = Join-Path $ScriptDir 'Wartung_Erinnerung.ps1'

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
    Write-Host  "  Zeitplan: Jeden Montag um 07:30 Uhr"
    Write-Host  "  Status:   Bereit"

} catch {
    Write-Host ""
    Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host " Bitte die VBS-Datei als Administrator ausfuehren."
}

Write-Host ""
Read-Host " Enter zum Beenden drucken"
