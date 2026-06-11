#Requires -Version 5.1

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ScriptPath = Join-Path $ScriptDir 'Sync_Lackformeln.ps1'
$TaskName   = 'EINHAUS Lackformeln Sync'

Write-Host ""
Write-Host " EINHAUS Lackierung - Lackformeln Sync einrichten" -ForegroundColor Cyan
Write-Host " ================================================="
Write-Host ""

if (-not (Test-Path $ScriptPath)) {
    Write-Host " FEHLER: Sync_Lackformeln.ps1 nicht gefunden!" -ForegroundColor Red
    Write-Host "         Erwartet unter: $ScriptPath"
    Read-Host "`n Enter zum Beenden"
    exit 1
}

# Hinweis service_role.key
$keyFile = Join-Path $ScriptDir 'service_role.key'
if (-not (Test-Path $keyFile) -and -not $env:SUPABASE_SERVICE_ROLE) {
    Write-Host " HINWEIS: service_role.key fehlt noch im Ordner." -ForegroundColor Yellow
    Write-Host "          Supabase -> Project Settings -> API -> service_role secret kopieren"
    Write-Host "          und als Datei service_role.key in diesem Ordner speichern."
    Write-Host ""
}

Write-Host " Registriere Aufgabe im Windows Aufgabenplaner ..."
Write-Host ""

# Alte Aufgabe entfernen falls vorhanden
Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

try {
    $action = New-ScheduledTaskAction `
        -Execute          'powershell.exe' `
        -Argument         "-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$ScriptPath`"" `
        -WorkingDirectory $ScriptDir

    # Stuendlich 07:00-18:00 Uhr
    $tDay = New-ScheduledTaskTrigger -Daily -At '07:00AM'
    $tDay.Repetition = (New-ScheduledTaskTrigger -Once -At '07:00AM' `
        -RepetitionInterval (New-TimeSpan -Hours 1) `
        -RepetitionDuration (New-TimeSpan -Hours 11)).Repetition
    # Zusaetzlich bei Anmeldung
    $tLogon = New-ScheduledTaskTrigger -AtLogOn

    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -StartWhenAvailable `
        -RestartCount 0

    $task = Register-ScheduledTask `
        -TaskName    $TaskName `
        -Action      $action `
        -Trigger     @($tDay, $tLogon) `
        -Settings    $settings `
        -Description 'Synchronisiert die Lackformeln aus Lackformeln.xlsx stuendlich in das Dashboard (Supabase) und exportiert Dashboard-Neuanlagen.' `
        -Force

    Write-Host " Erfolgreich eingerichtet!" -ForegroundColor Green
    Write-Host ""
    Write-Host ("  Name:      " + $task.TaskName)
    Write-Host  "  Zeitplan:  Stuendlich 07:00-18:00 Uhr + bei Anmeldung"
    Write-Host  "  Skript:    $ScriptPath"
    Write-Host ""

    Write-Host " Jetzt einmal synchronisieren? (J/N)" -ForegroundColor Yellow
    $antwort = Read-Host " Eingabe"
    if ($antwort -match '^[Jj]') {
        Write-Host ""
        Write-Host " Starte Sync ..." -ForegroundColor Cyan
        & powershell.exe -ExecutionPolicy Bypass -NonInteractive -File "$ScriptPath"
    }
}
catch {
    Write-Host ""
    Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host " Enter zum Beenden druecken"
