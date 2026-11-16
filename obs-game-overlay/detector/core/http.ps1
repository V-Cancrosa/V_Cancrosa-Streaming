#Requires -Version 5.1
# GameRadar · część «http»: wspólne ustawienia, przekaźnik pilota (ntfy), zaufane strony, stan cenzury, wysyłanie odpowiedzi HTTP
# Wczytywana przez detector.ps1 (dot-source) w ustalonej kolejności – korzysta z rzeczy z poprzednich części.
# Ścieżki: $Root = folder detector, $DataDir = detector\data, $AppDir = folder aplikacji (nie $PSScriptRoot – to byłby folder core).

# ---------------------------------------------------------------- HTTP
# ---------------------------------------------------------------- wspólne ustawienia (panel, serwis, telefon)
$SettingsFile = Join-Path $DataDir 'settings.json'
$RestartFlag = Join-Path $DataDir 'restart.flag'
Remove-Item $RestartFlag -ErrorAction SilentlyContinue   # stara prośba o restart nie dotyczy świeżo uruchomionego wykrywacza
$script:Settings = $null; $script:SettingsRev = 0; $script:SettingsFrom = ''
if (Test-Path $SettingsFile) {
    try { $j = (Get-Content $SettingsFile -Raw -Encoding UTF8) | ConvertFrom-Json; $script:Settings = [string]$j.json; $script:SettingsRev = [int]$j.rev } catch {}
}

# ---------------------------------------------------------------- pilot z telefonu przez przekaźnik (ntfy.sh)
# Telefon (strona pilota na GitHub Pages) wysyła polecenie na prywatny temat ntfy.sh, a GameRadar je odbiera
# i wykonuje jak «!vm …» z czatu. Bez Wi-Fi, bez otwierania portów i bez pisania na czacie. Temat = długi losowy klucz
# (kto go nie zna, nie wyśle polecenia); «Nowy klucz» w panelu unieważnia stary link. Włączane z panelu.
$RelayFile = Join-Path $DataDir 'relay.json'
$script:Relay = @{ on = $false; topic = ''; since = '' }
try { $rj = (Get-Content $RelayFile -Raw -Encoding UTF8) | ConvertFrom-Json; $script:Relay = @{ on = [bool]$rj.on; topic = [string]$rj.topic; since = '' } } catch {}
$script:RelayTask = $null; $script:RelayNext = [DateTime]::MinValue; $script:RelayHttp = $null; $script:RelayLast = ''; $script:RelayErr = ''; $script:RelayPollAt = [DateTime]::MinValue
function Save-Relay { [IO.File]::WriteAllText($RelayFile, (@{ on = $script:Relay.on; topic = $script:Relay.topic } | ConvertTo-Json), $Utf8NoBom) }
function New-RelayTopic {
    $kc = 'abcdefghijkmnpqrstuvwxyz23456789'.ToCharArray()
    $script:Relay.topic = 'vm-' + (-join (1..28 | ForEach-Object { $kc[(Get-Random -Maximum $kc.Length)] })); $script:Relay.since = ''; Save-Relay
}
function Update-Relay {
    if (-not $script:Relay.on -or -not $script:Relay.topic) { return }
    if (-not $script:RelayHttp) { Add-Type -AssemblyName System.Net.Http; $script:RelayHttp = New-Object Net.Http.HttpClient; $script:RelayHttp.Timeout = [TimeSpan]::FromSeconds(10) }
    if ($script:RelayTask) {
        if (-not $script:RelayTask.IsCompleted) { return }
        $t = $script:RelayTask; $script:RelayTask = $null; $script:RelayNext = (Get-Date).AddSeconds(2)
        if ($t.IsFaulted) {
            $script:RelayNext = (Get-Date).AddSeconds(15)
            $err = $t.Exception.GetBaseException().Message
            if ($err -ne $script:RelayErr) { $script:RelayErr = $err; Log "Pilot z telefonu: nie mogę połączyć się z przekaźnikiem ntfy.sh ($err)" 'Yellow' }
            return
        }
        if ($script:RelayErr) { $script:RelayErr = ''; Log 'Pilot z telefonu: przekaźnik znowu odpowiada' 'Green' }
        $script:RelayPollAt = Get-Date
        foreach ($line in ($t.Result -split "`n")) {
            if (-not $line.Trim()) { continue }
            try { $m = $line | ConvertFrom-Json } catch { continue }
            if ($m.id) { $script:Relay.since = [string]$m.id }
            if ($m.event -ne 'message' -or -not $m.message) { continue }
            $c = ([string]$m.message).Trim() -replace '^!vm\s+', ''
            if ($c.Length -gt 120) { continue }
            Add-Event ([pscustomobject]@{ type = 'control'; cmd = $c; user = 'pilot' })
            $script:RelayLast = "$c ($(Get-Date -Format 'HH:mm:ss'))"
            Log "Pilot z telefonu: $c" 'Cyan'
            # potwierdzenie dla telefonu: «komputer odebrał» (osobny temat …-ack)
            try { [void]$script:RelayHttp.PostAsync("https://ntfy.sh/$($script:Relay.topic)-ack", (New-Object Net.Http.StringContent($c))) } catch {}
        }
        return
    }
    if ((Get-Date) -lt $script:RelayNext) { return }
    # pierwszy raz: tylko nowe polecenia (od teraz), potem od ostatniego id
    $since = if ($script:Relay.since) { $script:Relay.since } else { [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
    $script:RelayTask = $script:RelayHttp.GetStringAsync("https://ntfy.sh/$($script:Relay.topic)/json?poll=1&since=$since")
}

# wspólny magazyn stron z Kreatora i stanów (strona na GitHub Pages w zwykłej przeglądarce ↔ OBS); wartości trzymamy jako tekst JSON
$KvFile = Join-Path $DataDir 'kv.json'
$KvKeys = @('obsGameOverlay.pages', 'obsGameOverlay.pageState', 'obsGameOverlay.pageVis', 'obsGameOverlay.notes')
$script:KV = @{}; $script:KvRev = 0
if (Test-Path $KvFile) {
    try { $kj = (Get-Content $KvFile -Raw -Encoding UTF8) | ConvertFrom-Json; $script:KvRev = [int]$kj.rev
          foreach ($pp in $kj.items.PSObject.Properties) { $script:KV[$pp.Name] = @{ rev = [int]$pp.Value.rev; from = [string]$pp.Value.from; val = [string]$pp.Value.val } } } catch {}
}
function Save-Kv {
    $items = [ordered]@{}; foreach ($k in $script:KV.Keys) { if ($k -ne 'obsGameOverlay.pageVis') { $items[$k] = $script:KV[$k] } }
    try { [IO.File]::WriteAllText($KvFile, (@{ rev = $script:KvRev; items = $items } | ConvertTo-Json -Depth 4 -Compress), $Utf8NoBom) } catch {}
}

# ---------------------------------------------------------------- zaufany korytarz: kto może rozmawiać z wykrywaczem
# Wykrywacz zna hasło do OBS i steruje czatem – nie może odpowiadać każdej stronie z internetu.
#  • Twoje GitHub Pages (i adresy dopisane w data\trusted-origins.txt) – po nagłówku Origin,
#  • strony z dysku (OBS, panel z pliku) – po kluczu z ..\vm-key.js, który czyta tylko przeglądarka na tym komputerze,
#  • strony samego wykrywacza (http://localhost:7777/ui/…, pilot z telefonu z kluczem pilota).
$TrustedFile = Join-Path $DataDir 'trusted-origins.txt'
if (-not (Test-Path $TrustedFile)) {
    [IO.File]::WriteAllText($TrustedFile, "# Strony, które mogą rozmawiać z wykrywaczem (po jednej w linijce, np. https://twoje-konto.github.io)`r`nhttps://v-cancrosa.github.io`r`n", $Utf8NoBom)
}
$script:Trusted = @(Get-Content $TrustedFile -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { $_.Trim().TrimEnd('/').ToLowerInvariant() } | Where-Object { $_ -and -not $_.StartsWith('#') })
$LocalKeyFile = Join-Path $DataDir 'local-key.txt'
$script:LocalKey = ''
try { $script:LocalKey = ([string](Get-Content $LocalKeyFile -Raw -ErrorAction Stop)).Trim() } catch {}
if ($script:LocalKey.Length -lt 24) {
    $kc = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
    $script:LocalKey = -join (1..32 | ForEach-Object { $kc[(Get-Random -Maximum $kc.Length)] })
    [IO.File]::WriteAllText($LocalKeyFile, $script:LocalKey, $Utf8NoBom)
}
# klucz dla stron z dysku: obok panelu (folder obs-game-overlay); git go pomija (.gitignore)
try { [IO.File]::WriteAllText((Join-Path (Split-Path $Root -Parent) 'vm-key.js'), "window.VM_KEY = '$($script:LocalKey)';`r`n", $Utf8NoBom) } catch { }
$script:BlockedLogged = @{}
$script:AllowOrigin = '*'
function Test-Trusted($req, $q) {
    $origin = [string]$req.Headers['Origin']
    $script:AllowOrigin = if ($origin) { $origin } else { '*' }
    $self = 'http://' + $req.Url.Authority.ToLowerInvariant()
    $key = [string]$req.Headers['X-VM-Key']; if (-not $key) { $key = [string]$q['vmk'] }
    if ($key -and $key -eq $script:LocalKey) { return $true }
    if ($origin -and $origin -ne 'null') { $o = $origin.TrimEnd('/').ToLowerInvariant(); return ($o -eq $self -or $script:Trusted -contains $o) }
    if (-not $origin) {
        $ref = [string]$req.Headers['Referer']
        if ($ref -and $ref.ToLowerInvariant().StartsWith($self + '/')) { return $true }
    }
    return $false
}


# ---------------------------------------------------------------- cenzura ekranu: OCR okna na pierwszym planie (Windows.Media.Ocr)
# Działa w osobnym wątku, tylko gdy warstwa «VM · Cenzura» (censor.html) w OBS co kilka sekund o to prosi.
# Zrzut okna → rozpoznanie tekstu (wbudowany OCR Windows, bez internetu) → słowa ze współrzędnymi ekranu.
# Które słowa zasłonić, decyduje warstwa (themes/wordfilter.js – ten sam filtr co czat). Nic nie jest zapisywane.
$script:Censor = [hashtable]::Synchronized(@{ on = $false; exes = @(); until = [DateTime]::MinValue; result = $null; status = 'wyłączona'; fps = 0; lang = ''; err = '' })
$script:CensorPS = $null
function Stop-Censor {
    $script:Censor.quit = $true
    if ($script:CensorPS) { try { [void]$script:CensorPS.BeginStop($null, $null) } catch {} }
}

$MimeTypes = @{ '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'; '.webp' = 'image/webp'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.svg' = 'image/svg+xml'; '.ico' = 'image/x-icon' }
function Send-File($ctx, [string]$rel) {
    $res = $ctx.Response
    if (-not $rel) { $rel = 'panel.html' }
    $rel = [Uri]::UnescapeDataString($rel).Replace('/', '\')
    $full = [IO.Path]::GetFullPath((Join-Path $AppDir $rel))
    $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
    $okPath = $full.StartsWith($AppDir + '\', [StringComparison]::OrdinalIgnoreCase) -and $full -notlike '*\detector\*' -and [IO.Path]::GetFileName($full) -ne 'vm-key.js'
    if (-not $okPath -or -not $MimeTypes.ContainsKey($ext) -or -not (Test-Path $full -PathType Leaf)) {
        $res.StatusCode = 404; $res.OutputStream.Close(); return
    }
    $bytes = [IO.File]::ReadAllBytes($full)
    $res.ContentType = $MimeTypes[$ext]
    $res.Headers['Cache-Control'] = 'no-cache'
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.OutputStream.Close()
}

function Read-Body($req) {
    $r = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
    try { return $r.ReadToEnd() } finally { $r.Dispose() }
}

function Send-Json($ctx, $obj, [int]$code = 200) {
    $res = $ctx.Response
    $res.StatusCode = $code
    $res.ContentType = 'application/json; charset=utf-8'
    $res.Headers['Access-Control-Allow-Origin'] = $script:AllowOrigin
    $res.Headers['Access-Control-Allow-Private-Network'] = 'true'
    $res.Headers['Cache-Control'] = 'no-store'
    $bytes = $Utf8NoBom.GetBytes(($obj | ConvertTo-Json -Depth 6 -Compress))
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.OutputStream.Close()
}

function Send-Bytes($ctx, [byte[]]$bytes, [string]$type) {
    $res = $ctx.Response
    $res.ContentType = $type
    $res.Headers['Access-Control-Allow-Origin'] = $script:AllowOrigin; $res.Headers['Access-Control-Allow-Private-Network'] = 'true'; $res.Headers['Cache-Control'] = 'no-store'; $res.Headers['Access-Control-Expose-Headers'] = 'X-VM-Fallback'
    $res.ContentLength64 = $bytes.Length; $res.OutputStream.Write($bytes, 0, $bytes.Length); $res.OutputStream.Close()
}

function Send-Raw($ctx, [string]$text, [string]$type) {
    $res = $ctx.Response
    $res.ContentType = "$type; charset=utf-8"
    $res.Headers['Access-Control-Allow-Origin'] = $script:AllowOrigin; $res.Headers['Cache-Control'] = 'no-store'
    $b = $Utf8NoBom.GetBytes($text); $res.ContentLength64 = $b.Length; $res.OutputStream.Write($b, 0, $b.Length); $res.OutputStream.Close()
}

function Get-Query($req) {
    # własne dekodowanie jako UTF-8 (HttpListener psuje polskie znaki w QueryString)
    $q = @{}
    $raw = $req.RawUrl
    $i = $raw.IndexOf('?')
    if ($i -lt 0) { return $q }
    foreach ($pair in $raw.Substring($i + 1).Split('&')) {
        if (-not $pair) { continue }
        $kv = $pair.Split(@('='), 2, [StringSplitOptions]::None)
        $k = [Uri]::UnescapeDataString($kv[0].Replace('+', ' '))
        $val = ''; if ($kv.Length -gt 1) { $val = [Uri]::UnescapeDataString($kv[1].Replace('+', ' ')) }
        $q[$k] = $val
    }
    return $q
}
