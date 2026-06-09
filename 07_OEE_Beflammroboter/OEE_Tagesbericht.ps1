#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$LogPfad   = Join-Path $ScriptDir 'OEE_Tagesbericht.log'

$SUPABASE_URL  = 'https://tldkqifblxkdligypffr.supabase.co'
$SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRsZGtxaWZibHhrZGxpZ3lwZmZyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA1NjkwMzEsImV4cCI6MjA5NjE0NTAzMX0.Zg0Yy9uAIvuFwNfYVzfLWqmQUvTnXivYmGIXLCOa6TM'
$TABELLE       = 'oee_beflammroboter'

$EMPFAENGER = @(
    'andreas.lisin@einhaus-gmbh.de'
)

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts  [$Level]  $Msg"
    $line | Add-Content -Path $LogPfad -Encoding UTF8
    Write-Host $line
}

function Bar {
    param([int]$Pct, [string]$Farbe, [string]$Bg = '#e8eef7')
    $p = [math]::Max(0, [math]::Min($Pct, 100))
    $r = 100 - $p
    if ($p -eq 0) {
        return "<table width='100%' cellpadding='0' cellspacing='0' border='0'><tr><td bgcolor='$Bg' style='height:8px;border-radius:4px;font-size:1px;'>&nbsp;</td></tr></table>"
    } elseif ($r -eq 0) {
        return "<table width='100%' cellpadding='0' cellspacing='0' border='0'><tr><td bgcolor='$Farbe' style='height:8px;border-radius:4px;font-size:1px;'>&nbsp;</td></tr></table>"
    } else {
        return "<table width='100%' cellpadding='0' cellspacing='0' border='0'><tr><td width='$p%' bgcolor='$Farbe' style='height:8px;border-radius:4px 0 0 4px;font-size:1px;'>&nbsp;</td><td width='$r%' bgcolor='$Bg' style='height:8px;border-radius:0 4px 4px 0;font-size:1px;'>&nbsp;</td></tr></table>"
    }
}

function OeeFarbe { param($v)
    if ($null -eq $v) { return '#888888' }
    if ($v -ge 80) { return '#1a7a3c' }
    if ($v -ge 60) { return '#c47a00' }
    return '#c0392b'
}
function OeeBg { param($v)
    if ($null -eq $v) { return '#f0f0f0' }
    if ($v -ge 80) { return '#e8f8ee' }
    if ($v -ge 60) { return '#fff8e1' }
    return '#fde8e6'
}

Write-Log ('=' * 60)
Write-Log "EINHAUS OEE Tagesbericht Beflammroboter gestartet"

# Sonntag: kein Bericht
if ((Get-Date).DayOfWeek -eq 'Sunday') {
    Write-Log "Sonntag - kein Bericht wird gesendet."
    Write-Log ('-' * 60)
    exit 0
}

$gestern   = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
$gestDatum = (Get-Date).AddDays(-1).ToString('dd.MM.yyyy')
$vor7tagen = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd')
Write-Log "Datum: $gestDatum"

try {
    # Gestern (Hauptdaten)
    $url = "$SUPABASE_URL/rest/v1/$TABELLE?datum=eq.$gestern&order=created_at.asc"
    $response = Invoke-RestMethod -Uri $url -Headers @{ 'apikey' = $SUPABASE_ANON; 'Authorization' = "Bearer $SUPABASE_ANON" }
    Write-Log "$($response.Count) Schicht(en) gefunden"

    # Letzte 7 Tage fuer Verlauf
    $url7 = "$SUPABASE_URL/rest/v1/$TABELLE?datum=gte.$vor7tagen&datum=lte.$gestern&order=datum.asc"
    $verlauf = Invoke-RestMethod -Uri $url7 -Headers @{ 'apikey' = $SUPABASE_ANON; 'Authorization' = "Bearer $SUPABASE_ANON" }
    Write-Log "$($verlauf.Count) Eintraege fuer Verlauf"
} catch {
    Write-Log "Supabase-Fehler: $($_.Exception.Message)" 'FEHLER'
    exit 1
}

$hatDaten = ($response.Count -gt 0)

# Immer volles Dashboard anzeigen - bei keinen Daten mit Leer-Werten
if ($hatDaten) {
    $s = $response[0]
} else {
    $s = [PSCustomObject]@{ oee=$null; verfuegbarkeit=$null; qualitaet=$null; stoerung_min=0; gesamtmenge=0; ausschuss=0; notiz=''; belegungszeit_min=0 }
}

# Verlauf-Chart als quickchart.io Bild generieren
function GenVerlaufChart {
    param($daten)
    # Labels + Datenpunkte
    $n = $daten.Count
    if ($n -eq 0) {
        $labels = "''"
        $oeeData = 'null'
    } else {
        $labels = ($daten | ForEach-Object { "'" + [datetime]::Parse($_.datum).ToString('dd.MM') + "'" }) -join ','
        $oeeData = ($daten | ForEach-Object {
            if ($null -ne $_.oee) { [math]::Round([double]$_.oee, 1) } else { 'null' }
        }) -join ','
    }
    $fill = if ($n -gt 0) { $n } else { 2 }

    # Punktfarben je Zone
    $ptColors = if ($n -gt 0) {
        ($daten | ForEach-Object {
            $v = if ($null -ne $_.oee) { [double]$_.oee } else { 0 }
            if ($v -ge 85) { "'#1a7a3c'" } elseif ($v -ge 75) { "'#2E75B6'" } elseif ($v -ge 60) { "'#f39c12'" } else { "'#c0392b'" }
        }) -join ','
    } else { "'#ccc'" }

    # Chart.js Konfiguration - Legende deaktiviert, als HTML eingebaut
    $chartConfig = "{type:'line',data:{labels:[$labels],datasets:[" +
        "{label:'',data:[$oeeData],borderColor:'#2E75B6',backgroundColor:'rgba(46,117,182,0.08)',pointBackgroundColor:[$ptColors],pointBorderColor:'white',pointBorderWidth:1,pointRadius:5,borderWidth:2,tension:0.3,fill:true}," +
        "{label:'85%',data:[$(($fill..1 | ForEach-Object { '85' }) -join ',')],borderColor:'#1a7a3c',borderDash:[6,4],pointRadius:0,borderWidth:1.5,fill:false}," +
        "{label:'75%',data:[$(($fill..1 | ForEach-Object { '75' }) -join ',')],borderColor:'#f39c12',borderDash:[6,4],pointRadius:0,borderWidth:1.5,fill:false}," +
        "{label:'60%',data:[$(($fill..1 | ForEach-Object { '60' }) -join ',')],borderColor:'#c0392b',borderDash:[6,4],pointRadius:0,borderWidth:1.5,fill:false}" +
        "]},options:{legend:{display:false},scales:{yAxes:[{ticks:{fontSize:9,min:0,max:100},gridLines:{color:'rgba(0,0,0,0.05)'}}],xAxes:[{ticks:{fontSize:9}}]}}}"

    # URL encodieren (Net.WebUtility ist immer verfuegbar, auch NonInteractive)
    $encoded = [Net.WebUtility]::UrlEncode($chartConfig)
    $url = "https://quickchart.io/chart?c=$encoded&w=380&h=185&backgroundColor=white&devicePixelRatio=2"

    # HTML-Legende unter dem Chart
    $legende = "<table cellpadding='0' cellspacing='0' border='0' style='margin-top:6px;'><tr>" +
        "<td style='font-size:9px;color:#1a7a3c;padding-right:14px;'>&#8212; 85%</td>" +
        "<td style='font-size:9px;color:#f39c12;padding-right:14px;'>&#8212; 75%</td>" +
        "<td style='font-size:9px;color:#c0392b;'>&#8212; 60%</td>" +
        "</tr></table>"

    return "<img src='$url' width='380' height='185' alt='OEE Verlauf' style='display:block;max-width:100%;'/>$legende"
}

$verlaufChartHtml = GenVerlaufChart $verlauf

if ($true) {
    $oee       = if ($null -ne $s.oee)              { [math]::Round($s.oee, 1) }              else { $null }
    $verfueg   = if ($null -ne $s.verfuegbarkeit)   { [math]::Round($s.verfuegbarkeit, 1) }   else { $null }
    $qualit    = if ($null -ne $s.qualitaet)        { [math]::Round($s.qualitaet, 1) }        else { $null }
    $stoerung  = if ($null -ne $s.stoerung_min)     { $s.stoerung_min }                       else { 0 }
    $menge     = if ($null -ne $s.gesamtmenge)      { $s.gesamtmenge }                        else { 0 }
    $ausschuss = if ($null -ne $s.ausschuss)        { $s.ausschuss }                          else { 0 }
    $notiz     = if ($s.notiz)                      { $s.notiz }                              else { '' }
    $belegung  = if ($null -ne $s.belegungszeit_min){ $s.belegungszeit_min }                  else { 0 }

    $oeeF  = OeeFarbe $oee;  $oeeBg  = OeeBg $oee
    $vF    = OeeFarbe $verfueg
    $qF    = OeeFarbe $qualit
    $stF   = if ($stoerung -gt 45) { '#c0392b' } elseif ($stoerung -gt 20) { '#c47a00' } else { '#1a7a3c' }

    $oeeV  = if ($null -ne $oee)    { [int]$oee }    else { 0 }
    $vV    = if ($null -ne $verfueg){ [int]$verfueg } else { 0 }
    $qV    = if ($null -ne $qualit) { [int]$qualit }  else { 0 }

    $oeeT  = if ($null -ne $oee)    { "$oee %" }    else { '-' }
    $vT    = if ($null -ne $verfueg){ "$verfueg %" } else { '-' }
    $qT    = if ($null -ne $qualit) { "$qualit %" }  else { '-' }
    $bewertung = if ($null -eq $oee -or $belegung -eq 0) { 'Kein Produktionstag' } elseif ($oee -ge 80) { 'GUT' } elseif ($oee -ge 60) { 'MITTEL' } else { 'KRITISCH' }

    $oeeBar = Bar $oeeV $oeeF
    $vBar   = Bar $vV   $vF
    $qBar   = Bar $qV   $qF

    # Stillstand-Balken relativ zu Belegungszeit
    $stPct  = if ($belegung -gt 0) { [math]::Min([int](($stoerung / $belegung) * 100), 100) } else { 0 }
    $stBar  = Bar $stPct $stF

    $notizZeile = if ($notiz) {
        "<tr><td bgcolor='#f8fafc' style='padding:9px 12px;font-size:12px;color:#666;border-top:1px solid #eee;'>Notiz / Stoerungsgrund</td><td colspan='4' bgcolor='#f8fafc' style='padding:9px 12px;font-size:12px;font-weight:bold;color:#333;border-top:1px solid #eee;'>$notiz</td></tr>"
    } else { '' }

    $betreff  = "OEE Beflammroboter Tagesbericht $gestDatum"

    $htmlBody = @"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/></head>
<body style="margin:0;padding:0;background-color:#eef1f5;">
<table width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#eef1f5">
<tr><td align="center" style="padding:20px 10px;">
<table width="680" cellpadding="0" cellspacing="0" border="0" style="font-family:Arial,sans-serif;">

<!-- HEADER -->
<tr><td bgcolor="#1F4E79" style="padding:16px 24px;border-radius:10px 10px 0 0;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
    <td style="color:#fff;font-size:17px;font-weight:bold;">EINHAUS Lackierung &ndash; OEE Tagesbericht</td>
    <td align="right" style="color:rgba(255,255,255,0.75);font-size:12px;">Beflammroboter &ndash; $gestDatum</td>
  </tr></table>
</td></tr>

<!-- KPI KACHELN -->
<tr><td bgcolor="#ffffff" style="padding:14px 12px 0 12px;border-top:3px solid #dce1e7;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0">
  <tr>
    <!-- OEE -->
    <td width="25%" style="padding:0 4px 14px 4px;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr><td bgcolor="#ffffff" style="padding:14px 12px;border:2px solid $oeeF;border-radius:8px;">
        <div style="font-size:9px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#7a8a9a;margin-bottom:6px;">OEE</div>
        <div style="font-size:22px;font-weight:900;color:$oeeF;">$oeeT</div>
        <div style="font-size:9px;color:#7a8a9a;margin-top:4px;">$bewertung</div>
      </td></tr>
      </table>
    </td>
    <!-- Verfuegbarkeit -->
    <td width="25%" style="padding:0 4px 14px 4px;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr><td bgcolor="#ffffff" style="padding:14px 12px;border:2px solid #2E75B6;border-radius:8px;">
        <div style="font-size:9px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#7a8a9a;margin-bottom:6px;">Verfuegbarkeit</div>
        <div style="font-size:22px;font-weight:900;color:#2E75B6;">$vT</div>
        <div style="font-size:9px;color:#7a8a9a;margin-top:4px;">&nbsp;</div>
      </td></tr>
      </table>
    </td>
    <!-- Stillstand -->
    <td width="25%" style="padding:0 4px 14px 4px;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr><td bgcolor="#ffffff" style="padding:14px 12px;border:2px solid $stF;border-radius:8px;">
        <div style="font-size:9px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#7a8a9a;margin-bottom:6px;">Stillstand</div>
        <div style="font-size:22px;font-weight:900;color:$stF;">$stoerung min</div>
        <div style="font-size:9px;color:#7a8a9a;margin-top:4px;">min / Schicht</div>
      </td></tr>
      </table>
    </td>
    <!-- Schichten -->
    <td width="25%" style="padding:0 4px 14px 4px;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr><td bgcolor="#ffffff" style="padding:14px 12px;border:2px solid #2E75B6;border-radius:8px;">
        <div style="font-size:9px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#7a8a9a;margin-bottom:6px;">Schichten gesamt</div>
        <div style="font-size:22px;font-weight:900;color:#2E75B6;">$($response.Count)</div>
        <div style="font-size:9px;color:#7a8a9a;margin-top:4px;">im Zeitraum</div>
      </td></tr>
      </table>
    </td>
  </tr>
  </table>
</td></tr>

<!-- CHARTS ZEILE 1: OEE VERLAUF + STOERUNGSGRUENDE -->
<tr><td bgcolor="#ffffff" style="padding:0 12px 12px 12px;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
    <!-- OEE Verlauf -->
    <td width="60%" style="padding-right:6px;" valign="top">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr><td bgcolor="#ffffff" style="padding:16px;border:1px solid #dce1e7;border-radius:8px;">
        <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#1F4E79;margin-bottom:12px;">OEE VERLAUF</div>
        $verlaufChartHtml
      </td></tr>
      </table>
    </td>
    <!-- Stoerungsgruende -->
    <td width="40%" style="padding-left:6px;" valign="top">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr><td bgcolor="#ffffff" style="padding:16px;border:1px solid #dce1e7;border-radius:8px;">
        <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#1F4E79;margin-bottom:12px;">STOERUNGSGRUENDE</div>
        $(if ($notiz) {
            "<table width='100%' cellpadding='0' cellspacing='0' border='0'>" +
            "<tr><td style='padding:6px 0;font-size:11px;color:#333;border-bottom:1px solid #eee;'>$notiz</td><td align='right' style='padding:6px 0;font-size:11px;font-weight:bold;color:#c0392b;border-bottom:1px solid #eee;'>$stoerung min</td></tr>" +
            "</table>"
        } else {
            "<div style='font-size:12px;color:#aaa;text-align:center;padding:20px 0;'>Keine Stoerungsdaten</div>"
        })
      </td></tr>
      </table>
    </td>
  </tr></table>
</td></tr>

<!-- CHARTS ZEILE 2: VERFUEGBARKEIT & QUALITAET + STILLSTAND -->
<tr><td bgcolor="#ffffff" style="padding:0 12px 12px 12px;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
    <!-- Verfuegbarkeit -->
    <td width="50%" style="padding-right:6px;" valign="top">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr><td bgcolor="#ffffff" style="padding:16px;border:1px solid #dce1e7;border-radius:8px;">
        <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#1F4E79;margin-bottom:12px;">VERFUEGBARKEIT</div>
        <div style="font-size:10px;color:#7a8a9a;margin-bottom:4px;">Verfuegbarkeit (= OEE)</div>
        $vBar
        <div style="font-size:13px;font-weight:bold;color:#2E75B6;margin-bottom:0;">$vT</div>
      </td></tr>
      </table>
    </td>
    <!-- Stillstand -->
    <td width="50%" style="padding-left:6px;" valign="top">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr><td bgcolor="#ffffff" style="padding:16px;border:1px solid #dce1e7;border-radius:8px;">
        <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#1F4E79;margin-bottom:12px;">STILLSTAND PRO SCHICHT (MIN)</div>
        <div style="font-size:10px;color:#7a8a9a;margin-bottom:4px;">$gestDatum</div>
        $stBar
        <div style="font-size:13px;font-weight:bold;color:$stF;margin-bottom:0;">$stoerung min</div>
        <div style="font-size:10px;color:#aaa;margin-top:4px;">von $belegung min Belegungszeit</div>
      </td></tr>
      </table>
    </td>
  </tr></table>
</td></tr>

<!-- SCHICHTEN TABELLE -->
<tr><td bgcolor="#ffffff" style="padding:0 12px 14px 12px;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0">
  <tr><td bgcolor="#ffffff" style="padding:16px;border:1px solid #dce1e7;border-radius:8px;">
    <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#1F4E79;margin-bottom:10px;">SCHICHTEN</div>
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr bgcolor="#1F4E79">
        <td style="padding:8px 10px;font-size:10px;font-weight:bold;color:#fff;text-transform:uppercase;letter-spacing:.5px;">Datum</td>
        <td style="padding:8px 10px;font-size:10px;font-weight:bold;color:#fff;text-transform:uppercase;letter-spacing:.5px;">Belegung</td>
        <td style="padding:8px 10px;font-size:10px;font-weight:bold;color:#fff;text-transform:uppercase;letter-spacing:.5px;">Stillstand</td>
        <td style="padding:8px 10px;font-size:10px;font-weight:bold;color:#fff;text-transform:uppercase;letter-spacing:.5px;">Verfueg.</td>
        <td style="padding:8px 10px;font-size:10px;font-weight:bold;color:#fff;text-transform:uppercase;letter-spacing:.5px;">OEE</td>
      </tr>
      <tr bgcolor="#f8fafc">
        <td style="padding:9px 10px;font-size:12px;color:#333;border-top:1px solid #eee;">$gestDatum</td>
        <td style="padding:9px 10px;font-size:12px;color:#333;border-top:1px solid #eee;">$belegung min</td>
        <td style="padding:9px 10px;font-size:12px;font-weight:bold;color:$stF;border-top:1px solid #eee;">$stoerung min</td>
        <td style="padding:9px 10px;font-size:12px;color:#2E75B6;border-top:1px solid #eee;">$vT</td>
        <td style="padding:9px 10px;font-size:12px;font-weight:bold;color:$oeeF;border-top:1px solid #eee;">$oeeT</td>
      </tr>
      $notizZeile
    </table>
  </td></tr>
  </table>
</td></tr>

<!-- FOOTER -->
<tr><td bgcolor="#1F4E79" style="padding:12px 24px;border-radius:0 0 10px 10px;text-align:center;">
  <div style="font-size:11px;color:rgba(255,255,255,0.6);">EINHAUS Oberflaechenveredelung GmbH &middot; Saarlandstr. 375a, 55411 Bingen</div>
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
        $mail          = $outlook.CreateItem(0)
        $mail.To       = $empfaenger
        $mail.Subject  = $betreff
        $mail.HTMLBody = $htmlBody
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
