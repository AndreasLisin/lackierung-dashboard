#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogPfad   = Join-Path $ScriptDir 'OEE_Tagesbericht.log'

$SUPABASE_URL  = 'https://tldkqifblxkdligypffr.supabase.co'
$SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRsZGtxaWZibHhrZGxpZ3lwZmZyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA1NjkwMzEsImV4cCI6MjA5NjE0NTAzMX0.Zg0Yy9uAIvuFwNfYVzfLWqmQUvTnXivYmGIXLCOa6TM'

$EMPFAENGER = @(
    'christoph.saar@einhaus-gmbh.de',
    'andreas.lisin@einhaus-gmbh.de'
)

$DASHBOARD_URL = 'https://andreaslisin.github.io/lackierung-dashboard/06_OEE_Kabine1/OEE_Auswertung.html'

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts  [$Level]  $Msg"
    $line | Add-Content -Path $LogPfad -Encoding UTF8
    Write-Host $line
}

Write-Log ('=' * 60)
Write-Log "EINHAUS OEE Tagesbericht gestartet"

# Gestern berechnen
$gestern    = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
$gestDatum  = (Get-Date).AddDays(-1).ToString('dd.MM.yyyy')
Write-Log "Datum: $gestDatum"

# Supabase abfragen
try {
    $url = "$SUPABASE_URL/rest/v1/oee_erfassung?datum=eq.$gestern&order=created_at.asc"
    $response = Invoke-RestMethod -Uri $url -Headers @{
        'apikey'        = $SUPABASE_ANON
        'Authorization' = "Bearer $SUPABASE_ANON"
    }
    Write-Log "$($response.Count) Schicht(en) gefunden"
} catch {
    Write-Log "Supabase-Fehler: $($_.Exception.Message)" 'FEHLER'
    exit 1
}

# E-Mail auch bei keinen Daten senden (kein Produktionstag)
$hatDaten = ($response.Count -gt 0)

# Werte aufbereiten
if ($hatDaten) {
    $schicht = $response[0]

    $oee      = if ($schicht.oee          -ne $null) { [math]::Round($schicht.oee,          1) } else { $null }
    $verfueg  = if ($schicht.verfuegbarkeit -ne $null) { [math]::Round($schicht.verfuegbarkeit, 1) } else { $null }
    $qualit   = if ($schicht.qualitaet    -ne $null) { [math]::Round($schicht.qualitaet,    1) } else { $null }
    $stoerung = if ($schicht.stoerung_min -ne $null) { $schicht.stoerung_min } else { 0 }
    $menge    = if ($schicht.gesamtmenge  -ne $null) { $schicht.gesamtmenge  } else { 0 }
    $ausschuss = if ($schicht.ausschuss   -ne $null) { $schicht.ausschuss    } else { 0 }
    $notiz    = if ($schicht.notiz) { $schicht.notiz } else { '' }
    $belegung = if ($schicht.belegungszeit_min -ne $null) { $schicht.belegungszeit_min } else { 0 }

    # OEE-Bewertung
    if ($oee -eq $null -or $belegung -eq 0) {
        $bewertung = 'Kein Produktionstag'
        $oeeAnzeige = '–'
    } elseif ($oee -ge 80) {
        $bewertung = 'GUT'
        $oeeAnzeige = "$oee %"
    } elseif ($oee -ge 60) {
        $bewertung = 'MITTEL'
        $oeeAnzeige = "$oee %"
    } else {
        $bewertung = 'KRITISCH'
        $oeeAnzeige = "$oee %"
    }

    $verfAnzeige  = if ($verfueg -ne $null) { "$verfueg %" } else { '–' }
    $qualAnzeige  = if ($qualit  -ne $null) { "$qualit %" }  else { '–' }
    $notizZeile   = if ($notiz) { "`r`nNotiz / Storungsgrund:  $notiz" } else { '' }

    $mailBody = @"
Guten Morgen,

anbei der OEE-Tagesbericht fuer den Lackierroboter Kabine 1 vom $gestDatum.

╔══════════════════════════════════════╗
  OEE TAGESBERICHT  –  $gestDatum
  Lackierroboter Kabine 1
╚══════════════════════════════════════╝

OEE:                    $oeeAnzeige  [$bewertung]
Verfuegbarkeit:         $verfAnzeige
Qualitaet:              $qualAnzeige

Belegungszeit:          $belegung min
Stoerung / Stillstand:  $stoerung min
Gesamtmenge:            $menge Stueck
Ausschuss + Nacharbeit: $ausschuss Stueck$notizZeile

Dashboard: $DASHBOARD_URL

Mit freundlichen Gruessen
Lackierung – EINHAUS Oberflaechenveredelung GmbH
Saarlandstr. 375a, 55411 Bingen
"@

    $betreff = "OEE Tagesbericht $gestDatum - Kabine 1: $oeeAnzeige [$bewertung]"

} else {
    # Keine Daten eingetragen
    $mailBody = @"
Guten Morgen,

fuer den $gestDatum wurde kein OEE-Eintrag fuer den Lackierroboter Kabine 1 erfasst.

Bitte pruefen, ob die Schichterfassung eingetragen wurde:
$DASHBOARD_URL

Mit freundlichen Gruessen
Lackierung – EINHAUS Oberflaechenveredelung GmbH
Saarlandstr. 375a, 55411 Bingen
"@
    $betreff = "OEE Tagesbericht $gestDatum - Kabine 1: KEIN EINTRAG"
}

# Outlook starten
try {
    $outlook = New-Object -ComObject Outlook.Application
    $null    = $outlook.GetNamespace('MAPI')
    $absender = $outlook.Session.Accounts.Item(1).SmtpAddress
    Write-Log "Absender: $absender"
} catch {
    Write-Log "Outlook nicht verfuegbar: $($_.Exception.Message)" 'FEHLER'
    exit 1
}

# E-Mail senden
$gesendet = 0
$fehler   = 0

foreach ($empfaenger in $EMPFAENGER) {
    try {
        $mail         = $outlook.CreateItem(0)
        $mail.To      = $empfaenger
        $mail.Subject = $betreff
        $mail.Body    = $mailBody
        $mail.Send()
        $gesendet++
        Write-Log "Gesendet -> $empfaenger"
    } catch {
        $fehler++
        Write-Log "Sendefehler ($empfaenger): $($_.Exception.Message)" 'FEHLER'
    }
}

try {
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook)
} catch { }
[GC]::Collect()
[GC]::WaitForPendingFinalizers()

Write-Log "Abgeschlossen - $gesendet E-Mail(s) gesendet, $fehler Fehler"
Write-Log ('-' * 60)
