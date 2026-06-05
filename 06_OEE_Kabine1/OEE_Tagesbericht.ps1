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

$gestern   = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
$gestDatum = (Get-Date).AddDays(-1).ToString('dd.MM.yyyy')
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

$hatDaten = ($response.Count -gt 0)

if ($hatDaten) {
    $schicht   = $response[0]
    $oee       = if ($null -ne $schicht.oee)               { [math]::Round($schicht.oee, 1) }               else { $null }
    $verfueg   = if ($null -ne $schicht.verfuegbarkeit)     { [math]::Round($schicht.verfuegbarkeit, 1) }    else { $null }
    $qualit    = if ($null -ne $schicht.qualitaet)          { [math]::Round($schicht.qualitaet, 1) }         else { $null }
    $stoerung  = if ($null -ne $schicht.stoerung_min)       { $schicht.stoerung_min }                        else { 0 }
    $menge     = if ($null -ne $schicht.gesamtmenge)        { $schicht.gesamtmenge }                         else { 0 }
    $ausschuss = if ($null -ne $schicht.ausschuss)          { $schicht.ausschuss }                           else { 0 }
    $notiz     = if ($schicht.notiz)                        { $schicht.notiz }                               else { '' }
    $belegung  = if ($null -ne $schicht.belegungszeit_min)  { $schicht.belegungszeit_min }                   else { 0 }

    # Farben + Bewertung
    if ($null -eq $oee -or $belegung -eq 0) {
        $oeeFarbe  = '#888888'; $oeeBg = '#f0f0f0'; $bewertung = 'Kein Produktionstag'; $oeeText = '-'
    } elseif ($oee -ge 80) {
        $oeeFarbe  = '#1a7a3c'; $oeeBg = '#e8f8ee'; $bewertung = 'GUT';      $oeeText = "$oee %"
    } elseif ($oee -ge 60) {
        $oeeFarbe  = '#c47a00'; $oeeBg = '#fff8e1'; $bewertung = 'MITTEL';   $oeeText = "$oee %"
    } else {
        $oeeFarbe  = '#c0392b'; $oeeBg = '#fde8e6'; $bewertung = 'KRITISCH'; $oeeText = "$oee %"
    }

    $verfText  = if ($null -ne $verfueg) { "$verfueg %" } else { '-' }
    $qualText  = if ($null -ne $qualit)  { "$qualit %" }  else { '-' }
    $notizHtml = if ($notiz) { "<tr><td style='padding:6px 0;color:#555;font-size:13px;'>Notiz / Stoerungsgrund</td><td style='padding:6px 0;font-weight:600;font-size:13px;'>$notiz</td></tr>" } else { '' }

    $betreff = "OEE Tagesbericht $gestDatum - Kabine 1: $oeeText [$bewertung]"

    $htmlBody = @"
<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'></head>
<body style='margin:0;padding:0;background:#eef1f5;font-family:Segoe UI,Arial,sans-serif;'>
<div style='max-width:600px;margin:0 auto;padding:24px 16px;'>

  <!-- Header -->
  <div style='background:#1F4E79;border-radius:12px 12px 0 0;padding:20px 28px;'>
    <div style='color:#fff;font-size:18px;font-weight:700;'>EINHAUS Lackierung</div>
    <div style='color:rgba(255,255,255,0.75);font-size:13px;margin-top:4px;'>OEE Tagesbericht &ndash; Lackierroboter Kabine 1 &ndash; $gestDatum</div>
  </div>

  <!-- OEE Hauptwert -->
  <div style='background:$oeeBg;border:3px solid $oeeFarbe;padding:28px;text-align:center;'>
    <div style='font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#888;margin-bottom:8px;'>OEE</div>
    <div style='font-size:56px;font-weight:900;color:$oeeFarbe;line-height:1;'>$oeeText</div>
    <div style='font-size:14px;font-weight:700;color:$oeeFarbe;margin-top:8px;letter-spacing:.05em;'>$bewertung</div>
  </div>

  <!-- KPI Kacheln -->
  <div style='display:flex;gap:0;background:#fff;'>
    <div style='flex:1;padding:18px;text-align:center;border-right:1px solid #dce1e7;'>
      <div style='font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.05em;color:#888;margin-bottom:6px;'>Verfuegbarkeit</div>
      <div style='font-size:26px;font-weight:800;color:#2E75B6;'>$verfText</div>
    </div>
    <div style='flex:1;padding:18px;text-align:center;border-right:1px solid #dce1e7;'>
      <div style='font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.05em;color:#888;margin-bottom:6px;'>Qualitaet</div>
      <div style='font-size:26px;font-weight:800;color:#2E75B6;'>$qualText</div>
    </div>
    <div style='flex:1;padding:18px;text-align:center;'>
      <div style='font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.05em;color:#888;margin-bottom:6px;'>Stillstand</div>
      <div style='font-size:26px;font-weight:800;color:$(if($stoerung -gt 45){'#c0392b'}elseif($stoerung -gt 20){'#c47a00'}else{'#1a7a3c'});'>$stoerung min</div>
    </div>
  </div>

  <!-- Details -->
  <div style='background:#fff;border-top:1px solid #dce1e7;padding:20px 28px;'>
    <table style='width:100%;border-collapse:collapse;'>
      <tr><td style='padding:6px 0;color:#555;font-size:13px;'>Belegungszeit</td><td style='padding:6px 0;font-weight:600;font-size:13px;'>$belegung min</td></tr>
      <tr><td style='padding:6px 0;color:#555;font-size:13px;'>Stoerung / Stillstand</td><td style='padding:6px 0;font-weight:600;font-size:13px;'>$stoerung min</td></tr>
      <tr><td style='padding:6px 0;color:#555;font-size:13px;'>Gesamtmenge</td><td style='padding:6px 0;font-weight:600;font-size:13px;'>$menge Stueck</td></tr>
      <tr><td style='padding:6px 0;color:#555;font-size:13px;'>Ausschuss + Nacharbeit</td><td style='padding:6px 0;font-weight:600;font-size:13px;'>$ausschuss Stueck</td></tr>
      $notizHtml
    </table>
  </div>

  <!-- Button -->
  <div style='background:#fff;border-top:1px solid #dce1e7;padding:20px 28px;text-align:center;border-radius:0 0 12px 12px;'>
    <a href='$DASHBOARD_URL' style='display:inline-block;background:#1F4E79;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:700;font-size:14px;'>
      Dashboard oeffnen &rarr;
    </a>
    <div style='margin-top:16px;font-size:11px;color:#aaa;'>
      EINHAUS Oberflaechenveredelung GmbH &middot; Saarlandstr. 375a, 55411 Bingen
    </div>
  </div>

</div>
</body>
</html>
"@

} else {
    $betreff = "OEE Tagesbericht $gestDatum - Kabine 1: KEIN EINTRAG"
    $htmlBody = @"
<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'></head>
<body style='margin:0;padding:0;background:#eef1f5;font-family:Segoe UI,Arial,sans-serif;'>
<div style='max-width:600px;margin:0 auto;padding:24px 16px;'>
  <div style='background:#1F4E79;border-radius:12px 12px 0 0;padding:20px 28px;'>
    <div style='color:#fff;font-size:18px;font-weight:700;'>EINHAUS Lackierung</div>
    <div style='color:rgba(255,255,255,0.75);font-size:13px;margin-top:4px;'>OEE Tagesbericht &ndash; Lackierroboter Kabine 1 &ndash; $gestDatum</div>
  </div>
  <div style='background:#fde8e6;border:3px solid #c0392b;padding:28px;text-align:center;'>
    <div style='font-size:32px;font-weight:900;color:#c0392b;'>Kein Eintrag</div>
    <div style='font-size:14px;color:#c0392b;margin-top:8px;'>Fuer den $gestDatum wurde keine Schicht erfasst.</div>
  </div>
  <div style='background:#fff;padding:20px 28px;text-align:center;border-radius:0 0 12px 12px;'>
    <p style='font-size:13px;color:#555;margin-bottom:16px;'>Bitte pruefen, ob die Schichterfassung eingetragen wurde.</p>
    <a href='$DASHBOARD_URL' style='display:inline-block;background:#1F4E79;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:700;font-size:14px;'>
      Dashboard oeffnen &rarr;
    </a>
    <div style='margin-top:16px;font-size:11px;color:#aaa;'>
      EINHAUS Oberflaechenveredelung GmbH &middot; Saarlandstr. 375a, 55411 Bingen
    </div>
  </div>
</div>
</body>
</html>
"@
}

# Outlook starten
try {
    $outlook  = New-Object -ComObject Outlook.Application
    $null     = $outlook.GetNamespace('MAPI')
    $absender = $outlook.Session.Accounts.Item(1).SmtpAddress
    Write-Log "Absender: $absender"
} catch {
    Write-Log "Outlook nicht verfuegbar: $($_.Exception.Message)" 'FEHLER'
    exit 1
}

$gesendet = 0
$fehler   = 0

foreach ($empfaenger in $EMPFAENGER) {
    try {
        $mail            = $outlook.CreateItem(0)
        $mail.To         = $empfaenger
        $mail.Subject    = $betreff
        $mail.HTMLBody   = $htmlBody
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
