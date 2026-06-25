#Requires -Version 5.1
# ============================================================
#  EINHAUS - Sync Lackformeln (Excel-Master -> Supabase)
#  - Liest Lackformeln.xlsx (NUR lesen) und befuellt Tabelle lackformeln neu.
#  - Spielt Dashboard-Neuanlagen (lackformeln_eingang, status='offen') mit ein.
#  - Haengt neue Neuanlagen an die Begleitdatei Dashboard_Neu.xlsx an.
#  Der Excel-Master wird vom Skript NICHT geschrieben.
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$LogPfad   = Join-Path $ScriptDir 'Sync_Lackformeln.log'

# ----- Konfiguration -----
$SUPABASE_URL = 'https://tldkqifblxkdligypffr.supabase.co'
# Quelle ist jetzt die saubere, strukturierte Eingabedatei (nicht mehr die alte block-Excel).
$MASTER_XLSX  = 'C:\Users\lisina\einhaus-gmbh.de\Lackierung - Dokumente\4. Lackformeln\Lackformeln_Strukturiert.xlsx'
$COMPANION    = 'C:\Users\lisina\einhaus-gmbh.de\Lackierung - Dokumente\4. Lackformeln\Dashboard_Neu.xlsx'
$Python       = 'python'

$ParserPy   = Join-Path $ScriptDir 'parse_strukturiert.py'
$EingangPy  = Join-Path $ScriptDir 'eingang_to_excel.py'
$ParsedJson = Join-Path $ScriptDir 'parsed.json'
$EingangJson= Join-Path $ScriptDir 'eingang_new.json'

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  [$Level]  $Msg" | Add-Content -Path $LogPfad -Encoding UTF8
    Write-Host "$ts  [$Level]  $Msg"
}

function Get-ServiceRole {
    if ($env:SUPABASE_SERVICE_ROLE) { return $env:SUPABASE_SERVICE_ROLE.Trim() }
    $keyFile = Join-Path $ScriptDir 'service_role.key'
    if (Test-Path $keyFile) { return (Get-Content -Raw -Path $keyFile).Trim() }
    return $null
}

function Invoke-Supabase {
    param([string]$Method, [string]$Path, $BodyString, [string]$Prefer)
    $headers = @{ apikey = $SR; Authorization = "Bearer $SR" }
    if ($Prefer) { $headers['Prefer'] = $Prefer }
    $uri = "$SUPABASE_URL/rest/v1/$Path"
    if ($BodyString) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($BodyString)
        return Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $bytes -ContentType 'application/json; charset=utf-8'
    }
    return Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers
}

function Invoke-Python {
    # Ruft Python auf, leitet stderr in eine Datei (kein 2>&1 -> kein NativeCommandError
    # unter PS 5.1) und protokolliert die Meldungen. Gibt den Exit-Code zurueck.
    param([string[]]$PyArgs)
    $perr = Join-Path $ScriptDir 'py_stderr.tmp'
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $Python @PyArgs 2> $perr | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if (Test-Path $perr) {
        Get-Content $perr | Where-Object { $_ -and $_.Trim() } | ForEach-Object { Write-Log $_.Trim() }
        Remove-Item $perr -ErrorAction SilentlyContinue
    }
    return $code
}

Write-Log ('=' * 60)
Write-Log 'Sync Lackformeln gestartet'

$SR = Get-ServiceRole
if (-not $SR) {
    Write-Log 'KEIN service_role-Key gefunden. Bitte service_role.key im Ordner ablegen' 'ERROR'
    Write-Log '  (Supabase Dashboard -> Project Settings -> API -> service_role secret)' 'ERROR'
    exit 1
}
if (-not (Test-Path $MASTER_XLSX)) { Write-Log "Master fehlt: $MASTER_XLSX" 'ERROR'; exit 1 }

try {
    # 1) Excel parsen -> JSON
    Write-Log 'Parse Excel-Master ...'
    $pcode = Invoke-Python @($ParserPy, $MASTER_XLSX, '--out', $ParsedJson)
    if ($pcode -ne 0 -or -not (Test-Path $ParsedJson)) { throw "Parser-Fehler (Exit $pcode)" }
    $parsedBody = Get-Content -Raw -Path $ParsedJson -Encoding UTF8
    $parsedArr  = $parsedBody | ConvertFrom-Json
    Write-Log "$($parsedArr.Count) Formeln aus Excel geparst"

    # 2) Full-Refresh: alte Formeln loeschen
    Write-Log 'Loesche bestehende lackformeln ...'
    Invoke-Supabase -Method 'Delete' -Path 'lackformeln?id=gte.0' -Prefer 'return=minimal' | Out-Null

    # 3) Neue Formeln einspielen (in Bloecken zu 200)
    $chunk = 200
    for ($i = 0; $i -lt $parsedArr.Count; $i += $chunk) {
        $slice = $parsedArr[$i..([math]::Min($i + $chunk - 1, $parsedArr.Count - 1))]
        $body  = ConvertTo-Json @($slice) -Depth 12 -Compress
        Invoke-Supabase -Method 'Post' -Path 'lackformeln' -BodyString $body -Prefer 'return=minimal' | Out-Null
    }
    Write-Log "Formeln eingespielt: $($parsedArr.Count)"

    # 4) Dashboard-Neuanlagen (status='offen') zusaetzlich einspielen
    $offen = Invoke-Supabase -Method 'Get' -Path "lackformeln_eingang?status=eq.offen&order=erstellt_am.asc"
    if ($offen -and $offen.Count -gt 0) {
        $inject = $offen | ForEach-Object {
            $note = 'Dashboard-Neuanlage (noch nicht im Excel-Master)'
            if ($_.notiz) { $note = "$note | $($_.notiz)" }
            [pscustomobject]@{
                kunde = $_.kunde; farbname = $_.farbname; farbcode = $null; system = $_.system
                typ = $null; komponenten = $_.komponenten; primer = $_.primer; klarlack = $_.klarlack
                haerter = $_.haerter; vorlage_nr = $null; notiz = $note
                quelle_blatt = 'Dashboard'; quelle_zeile = $null; geprueft = $false
            }
        }
        $body = ConvertTo-Json @($inject) -Depth 12 -Compress
        Invoke-Supabase -Method 'Post' -Path 'lackformeln' -BodyString $body -Prefer 'return=minimal' | Out-Null
        Write-Log "Dashboard-Neuanlagen eingespielt: $($offen.Count)"
    } else {
        Write-Log 'Keine offenen Dashboard-Neuanlagen'
    }

    # 5) Noch nicht exportierte Neuanlagen -> Begleitdatei Dashboard_Neu.xlsx
    $neu = Invoke-Supabase -Method 'Get' -Path "lackformeln_eingang?exportiert=eq.false&status=eq.offen&order=erstellt_am.asc"
    if ($neu -and $neu.Count -gt 0) {
        (ConvertTo-Json @($neu) -Depth 12) | Set-Content -Path $EingangJson -Encoding UTF8
        $code = Invoke-Python @($EingangPy, '--in', $EingangJson, '--file', $COMPANION)
        if ($code -eq 0) {
            foreach ($e in $neu) {
                Invoke-Supabase -Method 'Patch' -Path "lackformeln_eingang?id=eq.$($e.id)" `
                    -BodyString '{"exportiert":true}' -Prefer 'return=minimal' | Out-Null
            }
            Write-Log "In Begleitdatei exportiert: $($neu.Count)"
        } elseif ($code -eq 2) {
            Write-Log 'Begleitdatei gesperrt (in Excel offen) - naechster Lauf' 'WARN'
        } else {
            Write-Log "Export-Fehler (Exit $code)" 'WARN'
        }
        Remove-Item $EingangJson -ErrorAction SilentlyContinue
    }

    Write-Log 'Sync erfolgreich abgeschlossen'
}
catch {
    Write-Log "FEHLER: $($_.Exception.Message)" 'ERROR'
    exit 1
}
finally {
    Write-Log ('-' * 60)
}
