#Requires -Version 5.1
<#
  Vincent-Media – aktualizacja plików nakładki z GitHuba.

  Uruchomiony sam (np. ze skrótu «Aktualizuj»): sprawdza wersję i podmienia zmienione pliki.
  Z parametrem -Library tylko definiuje funkcje (używa go wykrywacz).

  Twoje dane zostają: detector\data\ (logowanie Twitcha, baza gier) i detector\my-games.txt.
#>
param([switch]$Library, [switch]$Quiet, [switch]$Force)

$VMRepo = 'V-Cancrosa/Vincent-Media'
$VMBranch = 'main'

function Enable-VMTls {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
}

function Get-VMLocalVersion([string]$dir) {
    try { return [string]((Get-Content (Join-Path $dir 'version.json') -Raw -Encoding UTF8) | ConvertFrom-Json).version }
    catch { return '0.0.0' }
}

function Get-VMRemoteInfo([int]$Timeout = 20) {
    Enable-VMTls
    $u = "https://raw.githubusercontent.com/$VMRepo/$VMBranch/obs-game-overlay/version.json?nocache=$(Get-Random)"
    return Invoke-RestMethod -UseBasicParsing -TimeoutSec $Timeout -Uri $u -Headers @{ 'Cache-Control' = 'no-cache' }
}

# ---------------------------------------------------------------- spis plików (manifest.json) i porządek w folderze
# Skrót pliku do porównań: pliki tekstowe bez znaków CR i BOM (paczka z GitHuba ma w .ps1 końce linii Windows,
# repozytorium – Linuksa), binarne bez zmian. Ten sam sposób liczy tools/make-manifest.py.
$VMTextExt = @('.ps1', '.bat', '.vbs', '.html', '.js', '.css', '.json', '.md', '.txt', '.svg', '.tsv', '.xml')
function Get-VMHash([string]$path) {
    $b = [IO.File]::ReadAllBytes($path)
    if ($VMTextExt -contains [IO.Path]::GetExtension($path).ToLowerInvariant()) {
        $t = (New-Object Text.UTF8Encoding($false)).GetString($b).TrimStart([char]0xFEFF).Replace("`r", '')
        $b = (New-Object Text.UTF8Encoding($false)).GetBytes($t)
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($b)) -replace '-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
# pliki tworzone na Twoim komputerze – nigdy nie kasowane ani nie sprawdzane
function Test-VMOwnFile([string]$rel) {
    $r = $rel.Replace('/', '\').ToLowerInvariant()
    return $r.StartsWith('detector\data\') -or $r -eq 'detector\my-games.txt' -or $r -eq 'vm-key.js' -or $r -eq 'detector\start-detector-silent.vbs'
}
# porównanie z manifest.json: czego brakuje, co się różni
function Test-VMFiles([string]$dir) {
    $mf = Join-Path $dir 'manifest.json'
    if (-not (Test-Path $mf)) { return [pscustomobject]@{ ok = $false; nomanifest = $true; missing = @(); changed = @(); total = 0 } }
    $m = (Get-Content $mf -Raw -Encoding UTF8) | ConvertFrom-Json
    $missing = New-Object Collections.ArrayList; $changed = New-Object Collections.ArrayList; $n = 0
    foreach ($p in $m.files.PSObject.Properties) {
        $n++
        $f = Join-Path $dir ($p.Name.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { [void]$missing.Add($p.Name); continue }
        if ((Get-VMHash $f) -ne [string]$p.Value) { [void]$changed.Add($p.Name) }
    }
    return [pscustomobject]@{ ok = (-not $missing.Count -and -not $changed.Count); nomanifest = $false; missing = @($missing); changed = @($changed); total = $n }
}
# skrót do programu (kreator startu) z ikoną Vincent-Media
function New-VMShortcut([string]$dir, [string]$path, [string]$extra = '') {
    $vbs = Join-Path $dir 'launcher\launcher.vbs'; $ico = Join-Path $dir 'launcher\vincent-media.ico'
    $sh = New-Object -ComObject WScript.Shell; $l = $sh.CreateShortcut($path)
    $l.TargetPath = "$env:WINDIR\System32\wscript.exe"; $l.Arguments = ('"' + $vbs + '"' + $extra); $l.WorkingDirectory = (Split-Path $vbs)
    if (Test-Path $ico) { $l.IconLocation = "$ico,0" }
    $l.Description = $(if ($extra) { 'Vincent-Media: GameRadar w tle' } else { 'Vincent-Media: sprawdza wszystko i uruchamia stream' })
    $l.Save()
}
# motyw wyglądu OBS «Vincent-Media» (wariant Yami, OBS 30.2+): plik do %APPDATA%\obs-studio\themes (zawsze aktualny)
# i raz – przy wyłączonym OBS – wybór w ustawieniach OBS. Gdy potem wybierzesz inny motyw, zostaje Twój.
function Install-VMObsTheme([string]$dir) {
    $src = Join-Path $dir 'obs-theme\Yami_VincentMedia.ovt'
    $obsDir = Join-Path $env:APPDATA 'obs-studio'
    if (-not (Test-Path $src)) { return 'brak pliku motywu' }
    if (-not (Test-Path $obsDir)) { return 'OBS jeszcze nie był uruchomiony' }
    $themes = Join-Path $obsDir 'themes'
    New-Item -ItemType Directory -Force -Path $themes | Out-Null
    Copy-Item -LiteralPath $src -Destination (Join-Path $themes 'Yami_VincentMedia.ovt') -Force
    $flag = Join-Path $dir 'detector\data\obs-theme.json'
    if (Test-Path $flag) { return 'motyw Vincent-Media zainstalowany' }
    if (Get-Process -Name obs64, obs32 -ErrorAction SilentlyContinue) { return 'motyw zainstalowany – wybiorę go przy następnym uruchomieniu OBS przez Vincent-Media' }
    # OBS 31+ trzyma wygląd w user.ini, starsze w global.ini – sekcja [Appearance], klucz Theme
    $ini = Join-Path $obsDir 'user.ini'; if (-not (Test-Path $ini)) { $ini = Join-Path $obsDir 'global.ini' }
    if (-not (Test-Path $ini)) { return 'motyw zainstalowany – wybierz go w OBS: Ustawienia → Wygląd' }
    $bytes = [IO.File]::ReadAllBytes($ini); $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $lines = New-Object Collections.ArrayList; $lines.AddRange([string[]](((New-Object Text.UTF8Encoding($false)).GetString($bytes).TrimStart([char]0xFEFF)) -split "`r?`n"))
    $sec = -1; for ($k = 0; $k -lt $lines.Count; $k++) { if ($lines[$k].Trim() -eq '[Appearance]') { $sec = $k; break } }
    $id = 'com.obsproject.Yami.VincentMedia'
    if ($sec -lt 0) { if ($lines.Count -and $lines[$lines.Count - 1] -ne '') { [void]$lines.Add('') }; [void]$lines.Add('[Appearance]'); [void]$lines.Add("Theme=$id") }
    else {
        $done = $false
        for ($k = $sec + 1; $k -lt $lines.Count -and -not $lines[$k].StartsWith('['); $k++) { if ($lines[$k] -match '^Theme=') { $lines[$k] = "Theme=$id"; $done = $true; break } }
        if (-not $done) { $lines.Insert($sec + 1, "Theme=$id") }
    }
    [IO.File]::WriteAllText($ini, ($lines -join "`r`n"), (New-Object Text.UTF8Encoding($bom)))
    New-Item -ItemType Directory -Force -Path (Split-Path $flag) | Out-Null
    [IO.File]::WriteAllText($flag, '{"set":true}', (New-Object Text.UTF8Encoding($false)))
    return 'motyw Vincent-Media wybrany w OBS'
}

# porządek: w folderze Vincent-Media widać tylko program, menu Start i pulpit – jeden skrót zamiast kilku
function Update-VMLayout([string]$dir) {
    if (-not (Test-Path (Join-Path $dir 'launcher\launcher.vbs'))) { return }
    $root = Split-Path $dir -Parent
    try { New-VMShortcut $dir (Join-Path $root 'Vincent-Media.lnk') } catch {}
    try { $di = Get-Item -LiteralPath $dir -Force; if (-not ($di.Attributes -band [IO.FileAttributes]::Hidden)) { $di.Attributes = $di.Attributes -bor [IO.FileAttributes]::Hidden } } catch {}
    $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $oldMenu = Join-Path $programs 'Vincent-Media'
    if (Test-Path $oldMenu) {
        foreach ($n in @('Start streamu.lnk', 'GameRadar.lnk', 'Aktualizuj Vincent-Media.lnk', 'Folder Vincent-Media.lnk', 'Wykrywacz gier.lnk', ('W' + [char]0x0142 + 'cz pilota z telefonu.lnk'))) { Remove-Item (Join-Path $oldMenu $n) -Force -ErrorAction SilentlyContinue }
        if (-not (Get-ChildItem $oldMenu -Force -ErrorAction SilentlyContinue)) { Remove-Item $oldMenu -Force -ErrorAction SilentlyContinue }
    }
    try { New-VMShortcut $dir (Join-Path $programs 'Vincent-Media.lnk') } catch {}
    $desk = [Environment]::GetFolderPath('Desktop'); $oldDesk = Join-Path $desk 'Start streamu.lnk'
    if (Test-Path $oldDesk) { Remove-Item $oldDesk -Force -ErrorAction SilentlyContinue; try { New-VMShortcut $dir (Join-Path $desk 'Vincent-Media.lnk') } catch {} }
    # autostart (gdy był włączony): GameRadar w tle przez ten sam program
    $st = Join-Path ([Environment]::GetFolderPath('Startup')) 'Vincent-Media wykrywacz.lnk'
    if (Test-Path $st) { try { New-VMShortcut $dir $st ' /tlo' } catch {} }
    # stare pliki startowe (zastąpione programem Vincent-Media) – dopiero gdy skróty już wskazują nowe miejsce
    foreach ($old in 'detector\start-stream.vbs', 'detector\start-detector.bat', 'detector\start-detector-hidden.bat', 'update.bat') { Remove-Item (Join-Path $dir $old) -Force -ErrorAction SilentlyContinue }
}

function Test-VMNewer([string]$remote, [string]$local) {
    try { return ([version]$remote) -gt ([version]$local) } catch { return $remote -ne $local }
}

# Pobiera paczkę z GitHuba i kopiuje do $target tylko zmienione pliki. Zwraca liczbę podmienionych plików.
# Windows PowerShell 5.1 czyta skrypt bez znacznika BOM jako ANSI – polskie litery i półpauzy psują wtedy składnię.
# Każdy .ps1 z polskimi znakami dostaje BOM (UTF-8), nawet gdyby przyszedł bez niego.
function Repair-VMEncoding([string]$dir) {
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    foreach ($f in Get-ChildItem -Path $dir -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue) {
        try {
            $b = [IO.File]::ReadAllBytes($f.FullName)
            if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { continue }
            if (-not ($b | Where-Object { $_ -gt 127 } | Select-Object -First 1)) { continue }
            $text = $utf8.GetString($b)
            [IO.File]::WriteAllText($f.FullName, $text, (New-Object Text.UTF8Encoding($true)))
        } catch {}
    }
}
function Install-VMFiles([string]$target) {
    Enable-VMTls
    $tmp = Join-Path $env:TEMP ('vm-update-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'vm.zip'
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'   # pasek postępu bardzo spowalnia pobieranie w PS 5.1
        try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 180 -Uri "https://codeload.github.com/$VMRepo/zip/refs/heads/$VMBranch" -OutFile $zip }
        finally { $ProgressPreference = $old }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $root = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
        $src = Join-Path $root.FullName 'obs-game-overlay'
        if (-not (Test-Path (Join-Path $src 'version.json'))) { throw 'pobrana paczka nie zawiera obs-game-overlay\version.json' }
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        $changed = 0
        foreach ($f in Get-ChildItem -Path $src -Recurse -File) {
            $rel = $f.FullName.Substring($src.Length).TrimStart('\')
            if ($rel -like 'detector\data\*' -or $rel -eq 'detector\my-games.txt') { continue }
            $dst = Join-Path $target $rel
            if ((Test-Path $dst) -and ((Get-FileHash -Path $dst).Hash -eq (Get-FileHash -Path $f.FullName).Hash)) { continue }
            New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
            Copy-Item -Path $f.FullName -Destination $dst -Force
            $changed++
        }
        Repair-VMEncoding $target
        # najpierw skróty na nowe miejsca, potem sprzątanie plików, których nie ma już w paczce (dane zostają)
        try { Update-VMLayout $target } catch {}
        $keep = @{}
        foreach ($f in Get-ChildItem -Path $src -Recurse -File) { $keep[$f.FullName.Substring($src.Length).TrimStart('\').ToLowerInvariant()] = $true }
        foreach ($f in @(Get-ChildItem -Path $target -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $rel = $f.FullName.Substring($target.TrimEnd('\').Length).TrimStart('\')
            if ((Test-VMOwnFile $rel) -or $keep.ContainsKey($rel.ToLowerInvariant())) { continue }
            try { Remove-Item -LiteralPath $f.FullName -Force; $changed++ } catch {}
        }
        foreach ($d in @(Get-ChildItem -Path $target -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
            if ($d.FullName -like '*\detector\data*') { continue }
            if (-not (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue }
        }
        return $changed
    } finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($Library) { return }

# ---------------------------------------------------------------- uruchomienie ręczne
$Host.UI.RawUI.WindowTitle = 'Vincent-Media: aktualizacja'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$dir = $PSScriptRoot
$local = Get-VMLocalVersion $dir
Write-Host ''
Write-Host '  Vincent-Media – aktualizacja' -ForegroundColor Magenta
Write-Host "  Folder: $dir" -ForegroundColor DarkGray
try {
    $remote = Get-VMRemoteInfo
    Write-Host "  Zainstalowana wersja: $local, najnowsza: $($remote.version)"
    if (-not $Force -and -not (Test-VMNewer ([string]$remote.version) $local)) {
        Write-Host '  Masz najnowszą wersję.' -ForegroundColor Green
    } else {
        # trwa transmisja albo nagrywanie? (wie o tym wykrywacz od panelu w OBS) – wtedy tylko za wyraźną zgodą
        $live = $null
        try { $live = Invoke-RestMethod -UseBasicParsing -TimeoutSec 3 -Uri 'http://localhost:7777/update/status' } catch {}
        if ($live -and $live.paused) {
            Write-Host "  Uwaga: trwa $($live.pausedWhy). Wykrywacz sam zaktualizuje wszystko zaraz po zakończeniu." -ForegroundColor Yellow
            if ($Quiet -or (Read-Host '  Zaktualizować mimo to teraz? [t/N]') -notmatch '^[tTyY]') { Write-Host '  Pominięto.'; if (-not $Quiet) { Read-Host '  Enter = zamknij' }; exit 0 }
        }
        $n = Install-VMFiles $dir
        Write-Host "  Zaktualizowano do $($remote.version) – podmienione pliki: $n." -ForegroundColor Green
        if ($remote.notes) { Write-Host "  Co nowego: $($remote.notes)" }
        Write-Host '  Wykrywacz sam uruchomi się w nowej wersji, a nakładki w OBS same się odświeżą.' -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  Nie udało się: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $Quiet) { Read-Host '  Enter = zamknij' }
    exit 1
}
if (-not $Quiet) { Read-Host '  Enter = zamknij' }
