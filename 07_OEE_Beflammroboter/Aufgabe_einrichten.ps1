#Requires -Version 5.1

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ScriptPath = Join-Path $ScriptDir 'OEE_Tagesbericht.ps1'

Write-Host ""
Write-Host " EINHAUS Lackierung - OEE Tagesbericht Beflammroboter einrichten" -ForegroundColor Cyan
Write-Host " ================================================================"
Write-Host ""

if (-not (Test-Path $ScriptPath)) {
    Write-Host " FEHLER: OEE_Tagesbericht.ps1 nicht gefunden!" -ForegroundColor Red
    Write-Host "         Erwartet unter: $ScriptPath"
    Read-Host "`n Enter zum Beenden"
    exit 1
}

Write-Host " Skript gefunden: $ScriptPath"
Write-Host " Registriere Aufgabe im Windows Aufgabenplaner ..."
Write-Host ""

# Alte Aufgabe entfernen falls vorhanden
Get-ScheduledTask -TaskName 'EINHAUS OEE Tagesbericht Beflammroboter' -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

try {
    $action = New-ScheduledTaskAction `
        -Execute          'powershell.exe' `
        -Argument         "-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$ScriptPath`"" `
        -WorkingDirectory $ScriptDir

    $trigger = New-ScheduledTaskTrigger -Daily -At '08:30AM'

    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -StartWhenAvailable `
        -RestartCount 0

    $task = Register-ScheduledTask `
        -TaskName    'EINHAUS OEE Tagesbericht Beflammroboter' `
        -Action      $action `
        -Trigger     $trigger `
        -Settings    $settings `
        -Description 'Sendet taeglich um 08:30 Uhr den OEE-Tagesbericht per Outlook fuer den Beflammroboter' `
        -Force

    Write-Host " Erfolgreich eingerichtet!" -ForegroundColor Green
    Write-Host ""
    Write-Host ("  Name:      " + $task.TaskName)
    Write-Host  "  Zeitplan:  Taeglich um 08:30 Uhr"
    Write-Host  "  Skript:    $ScriptPath"
    Write-Host  "  Status:    Bereit"
    Write-Host ""
    Write-Host " Die Aufgabe laeuft ab morgen automatisch." -ForegroundColor Green
    Write-Host ""
    Write-Host " Test-Mail jetzt senden? (J/N)" -ForegroundColor Yellow
    $antwort = Read-Host " Eingabe"
    if ($antwort -match '^[Jj]') {
        Write-Host ""
        Write-Host " Sende Test-Mail ..." -ForegroundColor Cyan
        & powershell.exe -ExecutionPolicy Bypass -NonInteractive -File "$ScriptPath"
        Write-Host " Test-Mail wurde versendet." -ForegroundColor Green
    }

} catch {
    Write-Host ""
    Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host " Bitte die VBS-Datei als Administrator ausfuehren." -ForegroundColor Yellow
}

Write-Host ""
Read-Host " Enter zum Beenden druecken"
