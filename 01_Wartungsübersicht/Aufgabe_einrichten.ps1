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

Write-Host " Skript gefunden: $ScriptPath"
Write-Host " Registriere Aufgabe im Windows Aufgabenplaner ..."
Write-Host ""

# Alte Aufgabe entfernen falls vorhanden
Get-ScheduledTask -TaskName 'EINHAUS Wartungserinnerung' -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

try {
    $action = New-ScheduledTaskAction `
        -Execute  'powershell.exe' `
        -Argument "-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$ScriptPath`""

    $trigger = New-ScheduledTaskTrigger -Daily -At '07:30AM'

    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -StartWhenAvailable `
        -RestartCount 0

    $task = Register-ScheduledTask `
        -TaskName    'EINHAUS Wartungserinnerung' `
        -Action      $action `
        -Trigger     $trigger `
        -Settings    $settings `
        -Description 'Sendet taeglich um 07:30 Uhr Wartungserinnerungen per Outlook fuer EINHAUS Lackierung' `
        -Force

    Write-Host " Erfolgreich eingerichtet!" -ForegroundColor Green
    Write-Host ""
    Write-Host ("  Name:      " + $task.TaskName)
    Write-Host  "  Zeitplan:  Taeglich um 07:30 Uhr"
    Write-Host  "  Skript:    $ScriptPath"
    Write-Host  "  Status:    Bereit"
    Write-Host ""
    Write-Host " Die Aufgabe laeuft ab morgen automatisch." -ForegroundColor Green

} catch {
    Write-Host ""
    Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host " Bitte die VBS-Datei als Administrator ausfuehren." -ForegroundColor Yellow
}

Write-Host ""
Read-Host " Enter zum Beenden druecken"
