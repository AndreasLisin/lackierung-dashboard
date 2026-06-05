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

    # Balkenbreiten (0-100) fuer CSS
    $oeeBalken  = if ($null -ne $oee)    { [math]::Min([math]::Max([int]$oee,    0), 100) } else { 0 }
    $verfBalken = if ($null -ne $verfueg){ [math]::Min([math]::Max([int]$verfueg, 0), 100) } else { 0 }
    $qualBalken = if ($null -ne $qualit) { [math]::Min([math]::Max([int]$qualit,  0), 100) } else { 0 }
    $oeeRest    = 100 - $oeeBalken
    $verfRest   = 100 - $verfBalken
    $qualRest   = 100 - $qualBalken

    $stFarbe    = if ($stoerung -gt 45) { '#c0392b' } elseif ($stoerung -gt 20) { '#c47a00' } else { '#1a7a3c' }
    $notizZeile = if ($notiz) {
        "<tr><td colspan='3' style='padding:0;'><table width='100%' cellpadding='0' cellspacing='0' border='0'><tr><td width='180' style='padding:8px 16px;font-size:12px;color:#666;border-top:1px solid #eee;'>Notiz / Storungsgrund</td><td style='padding:8px 16px;font-size:12px;font-weight:600;color:#333;border-top:1px solid #eee;'>$notiz</td></tr></table></td></tr>"
    } else { '' }

    $betreff = "OEE Tagesbericht $gestDatum - Kabine 1: $oeeText [$bewertung]"

    $htmlBody = @"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/></head>
<body style="margin:0;padding:0;background-color:#eef1f5;">
<table width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#eef1f5">
<tr><td align="center" style="padding:20px 10px;">

<table width="600" cellpadding="0" cellspacing="0" border="0" style="font-family:Arial,sans-serif;">

  <!-- HEADER -->
  <tr><td bgcolor="#1F4E79" style="padding:20px 28px;border-radius:10px 10px 0 0;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <td style="color:#ffffff;font-size:20px;font-weight:bold;">EINHAUS Lackierung</td>
        <td align="right" style="color:rgba(255,255,255,0.7);font-size:12px;">$gestDatum</td>
      </tr>
      <tr><td colspan="2" style="color:rgba(255,255,255,0.75);font-size:12px;padding-top:4px;">OEE Tagesbericht &ndash; Lackierroboter Kabine 1</td></tr>
    </table>
  </td></tr>

  <!-- OEE HAUPTWERT -->
  <tr><td bgcolor="$oeeBg" style="padding:28px;text-align:center;border-left:4px solid $oeeFarbe;border-right:4px solid $oeeFarbe;">
    <div style="font-size:11px;font-weight:bold;text-transform:uppercase;letter-spacing:2px;color:#888;margin-bottom:6px;">OEE Gesamt</div>
    <div style="font-size:64px;font-weight:900;color:$oeeFarbe;line-height:1.1;">$oeeText</div>
    <div style="font-size:13px;font-weight:bold;color:$oeeFarbe;margin-top:6px;letter-spacing:1px;">$bewertung</div>
    <!-- OEE Balken -->
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:14px;">
      <tr>
        <td width="${oeeBalken}%" bgcolor="$oeeFarbe" style="height:10px;border-radius:5px 0 0 5px;font-size:1px;">&nbsp;</td>
        <td width="${oeeRest}%" bgcolor="#dce1e7" style="height:10px;border-radius:0 5px 5px 0;font-size:1px;">&nbsp;</td>
      </tr>
    </table>
    <div style="font-size:10px;color:#888;margin-top:4px;">Ziel: 80 %</div>
  </td></tr>

  <!-- KPI KACHELN -->
  <tr><td bgcolor="#ffffff" style="padding:0;border-top:1px solid #dce1e7;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <!-- Verfuegbarkeit -->
        <td width="33%" style="padding:18px 16px;text-align:center;border-right:1px solid #dce1e7;">
          <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#888;margin-bottom:6px;">Verfuegbarkeit</div>
          <div style="font-size:28px;font-weight:900;color:#2E75B6;">$verfText</div>
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:8px;">
            <tr>
              <td width="${verfBalken}%" bgcolor="#2E75B6" style="height:6px;border-radius:3px 0 0 3px;font-size:1px;">&nbsp;</td>
              <td width="${verfRest}%"  bgcolor="#dce1e7" style="height:6px;border-radius:0 3px 3px 0;font-size:1px;">&nbsp;</td>
            </tr>
          </table>
        </td>
        <!-- Qualitaet -->
        <td width="33%" style="padding:18px 16px;text-align:center;border-right:1px solid #dce1e7;">
          <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#888;margin-bottom:6px;">Qualitaet</div>
          <div style="font-size:28px;font-weight:900;color:#2E75B6;">$qualText</div>
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:8px;">
            <tr>
              <td width="${qualBalken}%" bgcolor="#2E75B6" style="height:6px;border-radius:3px 0 0 3px;font-size:1px;">&nbsp;</td>
              <td width="${qualRest}%"  bgcolor="#dce1e7" style="height:6px;border-radius:0 3px 3px 0;font-size:1px;">&nbsp;</td>
            </tr>
          </table>
        </td>
        <!-- Stillstand -->
        <td width="34%" style="padding:18px 16px;text-align:center;">
          <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#888;margin-bottom:6px;">Stillstand</div>
          <div style="font-size:28px;font-weight:900;color:$stFarbe;">$stoerung min</div>
          <div style="font-size:10px;color:#aaa;margin-top:8px;">von $belegung min Belegung</div>
        </td>
      </tr>
    </table>
  </td></tr>

  <!-- DETAILS TABELLE -->
  <tr><td bgcolor="#f8fafc" style="padding:0;border-top:1px solid #dce1e7;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr bgcolor="#1F4E79">
        <td style="padding:10px 16px;font-size:11px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#ffffff;">Kennzahl</td>
        <td style="padding:10px 16px;font-size:11px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#ffffff;">Wert</td>
      </tr>
      <tr bgcolor="#ffffff"><td width="180" style="padding:10px 16px;font-size:13px;color:#555;border-bottom:1px solid #eee;">Belegungszeit</td><td style="padding:10px 16px;font-size:13px;font-weight:bold;color:#222;border-bottom:1px solid #eee;">$belegung min</td></tr>
      <tr bgcolor="#f8fafc"><td width="180" style="padding:10px 16px;font-size:13px;color:#555;border-bottom:1px solid #eee;">Stoerung / Stillstand</td><td style="padding:10px 16px;font-size:13px;font-weight:bold;color:$stFarbe;border-bottom:1px solid #eee;">$stoerung min</td></tr>
      <tr bgcolor="#ffffff"><td width="180" style="padding:10px 16px;font-size:13px;color:#555;border-bottom:1px solid #eee;">Gesamtmenge</td><td style="padding:10px 16px;font-size:13px;font-weight:bold;color:#222;border-bottom:1px solid #eee;">$menge Stueck</td></tr>
      <tr bgcolor="#f8fafc"><td width="180" style="padding:10px 16px;font-size:13px;color:#555;$(if($notiz){'border-bottom:1px solid #eee;'})">Ausschuss + Nacharbeit</td><td style="padding:10px 16px;font-size:13px;font-weight:bold;color:#222;$(if($notiz){'border-bottom:1px solid #eee;'})">$ausschuss Stueck</td></tr>
      $(if($notiz){"<tr bgcolor='#ffffff'><td width='180' style='padding:10px 16px;font-size:13px;color:#555;'>Notiz / Stoerungsgrund</td><td style='padding:10px 16px;font-size:13px;font-weight:bold;color:#222;'>$notiz</td></tr>"})
    </table>
  </td></tr>

  <!-- FOOTER -->
  <tr><td bgcolor="#ffffff" style="padding:16px 28px;text-align:center;border-top:1px solid #dce1e7;border-radius:0 0 10px 10px;">
    <div style="font-size:11px;color:#aaa;">EINHAUS Oberflaechenveredelung GmbH &middot; Saarlandstr. 375a, 55411 Bingen</div>
  </td></tr>

</table>
</td></tr>
</table>
</body>
</html>
"@

} else {
    $betreff = "OEE Tagesbericht $gestDatum - Kabine 1: KEIN EINTRAG"
    $htmlBody = @"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/></head>
<body style="margin:0;padding:0;background-color:#eef1f5;">
<table width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#eef1f5">
<tr><td align="center" style="padding:20px 10px;">
<table width="600" cellpadding="0" cellspacing="0" border="0" style="font-family:Arial,sans-serif;">
  <tr><td bgcolor="#1F4E79" style="padding:20px 28px;border-radius:10px 10px 0 0;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <td style="color:#ffffff;font-size:20px;font-weight:bold;">EINHAUS Lackierung</td>
        <td align="right" style="color:rgba(255,255,255,0.7);font-size:12px;">$gestDatum</td>
      </tr>
      <tr><td colspan="2" style="color:rgba(255,255,255,0.75);font-size:12px;padding-top:4px;">OEE Tagesbericht &ndash; Lackierroboter Kabine 1</td></tr>
    </table>
  </td></tr>
  <tr><td bgcolor="#fde8e6" style="padding:36px 28px;text-align:center;border-left:4px solid #c0392b;border-right:4px solid #c0392b;">
    <div style="font-size:11px;font-weight:bold;text-transform:uppercase;letter-spacing:2px;color:#c0392b;margin-bottom:10px;">OEE Gesamt</div>
    <div style="font-size:52px;font-weight:900;color:#c0392b;line-height:1.1;">Kein Eintrag</div>
    <div style="font-size:13px;color:#c0392b;margin-top:10px;">Fuer den $gestDatum wurde keine Schicht erfasst.</div>
    <div style="font-size:12px;color:#888;margin-top:8px;">Bitte pruefen ob die Schichterfassung am Tablet eingetragen wurde.</div>
  </td></tr>
  <tr><td bgcolor="#ffffff" style="padding:16px 28px;text-align:center;border-top:1px solid #dce1e7;border-radius:0 0 10px 10px;">
    <div style="font-size:11px;color:#aaa;">EINHAUS Oberflaechenveredelung GmbH &middot; Saarlandstr. 375a, 55411 Bingen</div>
  </td></tr>
</table>
</td></tr>
</table>
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
