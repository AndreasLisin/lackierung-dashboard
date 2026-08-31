#Requires -Version 5.1
param([int]$VorlaufTage = 90)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$JsonPfad  = Join-Path $ScriptDir 'Wartung_Daten.json'
$LogPfad   = Join-Path $ScriptDir 'Wartung_Erinnerung.log'

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts  [$Level]  $Msg"
    $line | Add-Content -Path $LogPfad -Encoding UTF8
    Write-Host $line
}

Write-Log ('=' * 60)
Write-Log "EINHAUS Lackierung - Wartungserinnerung gestartet"

if (-not (Test-Path $JsonPfad)) {
    Write-Log "Datei nicht gefunden: $JsonPfad" 'FEHLER'
    Write-Log "Bitte in der Wartungsuebersicht auf Exportieren klicken." 'FEHLER'
    exit 1
}

try {
    $data = (Get-Content -Path $JsonPfad -Encoding UTF8 -Raw) | ConvertFrom-Json
} catch {
    Write-Log "JSON-Lesefehler: $($_.Exception.Message)" 'FEHLER'
    exit 1
}

$heute = [datetime]::Today
Write-Log "$($data.Count) Anlage(n) geladen - Vorlauf: $VorlaufTage Tage - Heute: $($heute.ToString('dd.MM.yyyy'))"

$faellig = @()

foreach ($anlage in $data) {
    try {
        $letzte   = [datetime]::ParseExact($anlage.letzteWartung, 'yyyy-MM-dd', $null)
        $naechste = $letzte.AddMonths([int]$anlage.intervallMonate)
        $restTage = [int]($naechste - $heute).TotalDays
    } catch {
        Write-Log "Datumsfehler bei '$($anlage.anlage)': $($_.Exception.Message)" 'WARNUNG'
        continue
    }

    $meilensteine = @(90, 60, 30)
    $senden = ($restTage -le 0) -or ($restTage -in $meilensteine)

    if ($senden) {
        $faellig += [PSCustomObject]@{
            Anlage   = $anlage.anlage
            Typ      = $anlage.wartungstyp
            Person   = $anlage.person
            Email    = $anlage.email
            Naechste = $naechste
            RestTage = $restTage
            Notizen  = $anlage.notizen
            WFirma   = if ($anlage.PSObject.Properties['wFirma'])   { $anlage.wFirma }   else { '' }
            WKontakt = if ($anlage.PSObject.Properties['wKontakt']) { $anlage.wKontakt } else { '' }
            WTelefon = if ($anlage.PSObject.Properties['wTelefon']) { $anlage.wTelefon } else { '' }
            WEmail   = if ($anlage.PSObject.Properties['wEmail'])   { $anlage.wEmail }   else { '' }
        }
        if ($restTage -le 0) {
            Write-Log "Senden: $($anlage.anlage) - UEBERFAELLIG ($([Math]::Abs($restTage)) Tage)"
        } else {
            Write-Log "Senden: $($anlage.anlage) - faellig in $restTage Tagen (Meilenstein)"
        }
    } else {
        Write-Log "Kein Meilenstein: $($anlage.anlage) - noch $restTage Tage"
    }
}

if ($faellig.Count -eq 0) {
    Write-Log "Keine Wartungen faellig - kein E-Mail-Versand."
    Write-Log ('-' * 60)
    exit 0
}

Write-Log "$($faellig.Count) Wartung(en) faellig - starte E-Mail-Versand"

try {
    $outlook      = New-Object -ComObject Outlook.Application
    $null         = $outlook.GetNamespace('MAPI')
    $absenderMail = $outlook.Session.Accounts.Item(1).SmtpAddress
    Write-Log "Absender: $absenderMail"
} catch {
    Write-Log "Outlook nicht verfuegbar: $($_.Exception.Message)" 'FEHLER'
    exit 1
}

$gesendet = 0
$fehler   = 0

foreach ($eintrag in $faellig) {

    if ([string]::IsNullOrWhiteSpace($eintrag.Email)) {
        Write-Log "Uebersprungen (keine E-Mail): $($eintrag.Anlage)" 'WARNUNG'
        continue
    }

    $datumStr = $eintrag.Naechste.ToString('dd.MM.yyyy')

    if ($eintrag.RestTage -le 0) {
        $verzoegert = [Math]::Abs($eintrag.RestTage)
        $tagSuffix  = if ($verzoegert -ne 1) { 'en' } else { '' }
        $betreff    = "EINHAUS Lackierung: Ueberfaellige Wartung - $($eintrag.Anlage) ($($eintrag.Typ))"
        $intro      = "die Wartung fuer die unten genannte Anlage ist bereits seit $verzoegert Tag$tagSuffix ueberfaellig. Bitte veranlassen Sie die notwendigen Massnahmen umgehend."
    } else {
        $tagSuffix  = if ($eintrag.RestTage -ne 1) { 'en' } else { '' }
        $betreff    = "EINHAUS Lackierung: Wartungserinnerung - $($eintrag.Anlage) (faellig: $datumStr)"
        $intro      = "hiermit moechten wir Sie daran erinnern, dass fuer die unten genannte Anlage eine Wartung in $($eintrag.RestTage) Tag$tagSuffix ansteht ($datumStr). Bitte planen Sie die notwendigen Massnahmen rechtzeitig ein."
    }

    $notizZeile = if (-not [string]::IsNullOrWhiteSpace($eintrag.Notizen)) {
        "`r`nHinweise:         $($eintrag.Notizen)"
    } else { '' }

    $dienstleisterBlock = ''
    if (-not [string]::IsNullOrWhiteSpace($eintrag.WFirma)) {
        $dienstleisterBlock  = "`r`n`r`n-- Wartungsfirma / Dienstleister --"
        $dienstleisterBlock += "`r`nFirma:            $($eintrag.WFirma)"
        if (-not [string]::IsNullOrWhiteSpace($eintrag.WKontakt)) { $dienstleisterBlock += "`r`nAnsprechpartner:  $($eintrag.WKontakt)" }
        if (-not [string]::IsNullOrWhiteSpace($eintrag.WTelefon)) { $dienstleisterBlock += "`r`nTelefon:          $($eintrag.WTelefon)" }
        if (-not [string]::IsNullOrWhiteSpace($eintrag.WEmail))   { $dienstleisterBlock += "`r`nE-Mail:           $($eintrag.WEmail)" }
    }

    $mailBody = @"
Guten Tag $($eintrag.Person),

$intro

Anlage:           $($eintrag.Anlage)
Wartungstyp:      $($eintrag.Typ)
Naechste Wartung: $datumStr$notizZeile$dienstleisterBlock

Mit freundlichen Gruessen
Lackierung - EINHAUS Oberflaechenveredelung GmbH
Saarlandstr. 375a, 55411 Bingen
"@

    try {
        $mail         = $outlook.CreateItem(0)
        $mail.To      = $eintrag.Email
        $mail.CC      = $absenderMail
        $mail.Subject = $betreff
        $mail.Body    = $mailBody
        $mail.Save()
        $gesendet++
        Write-Log "Gesendet: $($eintrag.Anlage) -> $($eintrag.Email) (RestTage: $($eintrag.RestTage))"
    } catch {
        $fehler++
        Write-Log "Sendefehler ($($eintrag.Anlage)): $($_.Exception.Message)" 'FEHLER'
    }
}

try {
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook)
} catch { }
[GC]::Collect()
[GC]::WaitForPendingFinalizers()

Write-Log "Abgeschlossen - $gesendet E-Mail(s) gesendet, $fehler Fehler"
Write-Log ('-' * 60)
