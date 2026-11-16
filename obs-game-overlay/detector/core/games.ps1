#Requires -Version 5.1
# GameRadar · część «games»: baza gier, dopasowanie procesu, Steam i inne launchery, okno na pierwszym planie, skan, biblioteka
# Wczytywana przez detector.ps1 (dot-source) w ustalonej kolejności – korzysta z rzeczy z poprzednich części.
# Ścieżki: $Root = folder detector, $DataDir = detector\data, $AppDir = folder aplikacji (nie $PSScriptRoot – to byłby folder core).

# ---------------------------------------------------------------- baza gier
function Update-Index {
    $sources = @(
        'https://discord.com/api/v9/applications/detectable',
        'https://raw.githubusercontent.com/OpenAsar/arrpc/main/src/process/detectable.json'
    )
    Add-Type -AssemblyName System.Web.Extensions
    foreach ($url in $sources) {
        try {
            Log "Pobieram bazę gier: $url"
            $wc = New-Object Net.WebClient
            $wc.Headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) VincentMediaGameDetector/1.0'
            $wc.Encoding = [Text.Encoding]::UTF8
            $json = $wc.DownloadString($url)
            $ser = New-Object Web.Script.Serialization.JavaScriptSerializer
            $ser.MaxJsonLength = [int]::MaxValue
            $ser.RecursionLimit = 100
            $apps = $ser.DeserializeObject($json)
            $sb = New-Object Text.StringBuilder
            $count = 0
            foreach ($a in $apps) {
                $steam = ''
                foreach ($sku in @(Get-Val $a 'third_party_skus')) {
                    if ($sku -and (Get-Val $sku 'distributor') -eq 'steam') { $steam = Clean (Get-Val $sku 'id'); break }
                }
                $id = Clean (Get-Val $a 'id'); $name = Clean (Get-Val $a 'name'); $icon = Clean (Get-Val $a 'icon_hash')
                foreach ($e in @(Get-Val $a 'executables')) {
                    if (-not $e) { continue }
                    if ((Get-Val $e 'os') -ne 'win32' -or (Get-Val $e 'is_launcher')) { continue }
                    $exe = (Clean (Get-Val $e 'name')).ToLowerInvariant()
                    if (-not $exe) { continue }
                    $argz = Clean (Get-Val $e 'arguments')
                    [void]$sb.Append($exe).Append("`t").Append($id).Append("`t").Append($name).Append("`t").Append($icon).Append("`t").Append($steam).Append("`t").Append($argz).Append("`n")
                    $count++
                }
            }
            if ($count -lt 1000) { throw "podejrzanie mało wpisów ($count)" }
            [IO.File]::WriteAllText($IndexFile, $sb.ToString(), $Utf8NoBom)
            Log "Baza gier zapisana: $count plików .exe" 'Green'
            return
        } catch {
            Log "  nie udało się: $($_.Exception.Message)" 'Yellow'
        }
    }
}

$script:ByExe = @{}
$script:BySteam = @{}
function Import-Index {
    $script:ByExe = @{}; $script:BySteam = @{}
    if (-not (Test-Path $IndexFile)) { Log 'Brak bazy gier – działa tylko Steam i my-games.txt.' 'Yellow'; return }
    foreach ($line in [IO.File]::ReadAllLines($IndexFile, [Text.Encoding]::UTF8)) {
        $f = $line.Split("`t")
        if ($f.Length -lt 6) { continue }
        $entry = [pscustomobject]@{ Exe = $f[0]; Id = $f[1]; Name = $f[2]; Icon = $f[3]; Steam = $f[4]; Args = $f[5] }
        if (-not $script:ByExe.ContainsKey($f[0])) { $script:ByExe[$f[0]] = New-Object Collections.ArrayList }
        [void]$script:ByExe[$f[0]].Add($entry)
        if ($f[4] -and -not $script:BySteam.ContainsKey($f[4])) { $script:BySteam[$f[4]] = $entry }
    }
    Log ("Wczytano bazę: {0} gier/plików" -f $script:ByExe.Count)
}

# ---------------------------------------------------------------- my-games.txt
$script:Custom = @{}
$script:Ignore = @{}
$script:CustomStamp = $null
function Initialize-CustomFile {
    if (Test-Path $CustomFile) { return }
    $txt = @"
# Twoje gry, których nie wykrywa baza Discorda (albo chcesz zmienić im nazwę).
# Jedna gra w linii:
#   plik.exe = Nazwa gry
#   plik.exe = Nazwa gry | https://adres-okladki.jpg
# Ignorowanie programu, który nie jest grą:
#   !plik.exe
# Ignorowanie aplikacji Steama po numerze:
#   !steam:431960
#
# Plik możesz edytować w trakcie działania – zmiany wchodzą od razu.
# Panel w OBS też umie tu dopisywać gry (przycisk «Dodaj jako grę»).

"@
    [IO.File]::WriteAllText($CustomFile, $txt, (New-Object Text.UTF8Encoding $true))
}
function Import-Custom {
    $stamp = (Get-Item $CustomFile).LastWriteTimeUtc
    if ($stamp -eq $script:CustomStamp) { return }
    $script:CustomStamp = $stamp
    $script:Custom = @{}; $script:Ignore = @{}
    foreach ($raw in [IO.File]::ReadAllLines($CustomFile, [Text.Encoding]::UTF8)) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line.StartsWith('!')) { $script:Ignore[$line.Substring(1).Trim().ToLowerInvariant().Replace('\','/')] = $true; continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $exe = $line.Substring(0, $eq).Trim().ToLowerInvariant().Replace('\','/')
        $rest = $line.Substring($eq + 1)
        $img = ''
        $bar = $rest.IndexOf('|')
        if ($bar -ge 0) { $img = $rest.Substring($bar + 1).Trim(); $rest = $rest.Substring(0, $bar) }
        $script:Custom[$exe] = [pscustomobject]@{ Name = $rest.Trim(); Image = $img }
    }
    $script:MatchCache = @{}
    Log ("my-games.txt: {0} gier, {1} ignorowanych" -f $script:Custom.Count, $script:Ignore.Count)
}
function Add-CustomLine([string]$line) {
    $existing = [IO.File]::ReadAllText($CustomFile, [Text.Encoding]::UTF8)
    if ($existing.Length -and -not $existing.EndsWith("`n")) { $line = "`r`n" + $line }
    [IO.File]::AppendAllText($CustomFile, $line + "`r`n", $Utf8NoBom)
    Import-Custom
}

# ---------------------------------------------------------------- dopasowanie procesu
function Get-Variants([string]$path) {
    $p = $path.ToLowerInvariant().Replace('\', '/')
    $parts = $p.Split('/')
    $list = New-Object Collections.Generic.List[string]
    for ($i = 1; $i -lt $parts.Length; $i++) {
        $list.Add([string]::Join('/', $parts, $parts.Length - $i, $i))
    }
    foreach ($x in @($list)) {   # jak Discord: tolerancja na dopiski 64-bit
        foreach ($t in @('64', '.x64', 'x64', '_64')) {
            $y = $x.Replace($t, '')
            if ($y -ne $x -and -not $list.Contains($y)) { $list.Add($y) }
        }
    }
    return , $list
}

$script:MatchCache = @{}
function Find-Game([string]$path, [string]$cmd) {
    $key = $path + '|' + $cmd
    if ($script:MatchCache.ContainsKey($key)) { return $script:MatchCache[$key] }
    $result = $null
    $v = Get-Variants $path
    $base = $v[0]
    $ignored = $NeverGame -contains $base
    foreach ($k in $v) { if ($script:Ignore.ContainsKey($k)) { $ignored = $true; break } }
    if (-not $ignored) {
        foreach ($k in @($v | Sort-Object Length -Descending)) {
            if ($script:Custom.ContainsKey($k)) {
                $c = $script:Custom[$k]
                $result = [pscustomobject]@{ Exe = $base; Id = ''; Name = $c.Name; Icon = ''; Steam = ''; Args = ''; Image = $c.Image; Via = 'my-games' }
                break
            }
        }
        if (-not $result -and $MakeApps.ContainsKey($base)) {
            $result = [pscustomobject]@{ Exe = $base; Id = ''; Name = $MakeApps[$base]; Icon = ''; Steam = ''; Args = ''; Image = ''; Via = 'app'; Kind = 'make' }
        }
        if (-not $result) {
            # najpierw najdłuższe (najbardziej konkretne) ścieżki, np. garrysmod/hl2.exe przed hl2.exe
            $keys = @($v | Sort-Object Length -Descending) + @('>' + $base)
            foreach ($k in $keys) {
                if (-not $script:ByExe.ContainsKey($k)) { continue }
                foreach ($e in $script:ByExe[$k]) {
                    if ($e.Args -and ($null -eq $cmd -or $cmd.IndexOf($e.Args, [StringComparison]::OrdinalIgnoreCase) -lt 0)) { continue }
                    $result = [pscustomobject]@{ Exe = $base; Id = $e.Id; Name = $e.Name; Icon = $e.Icon; Steam = $e.Steam; Args = $e.Args; Image = ''; Via = 'discord-db' }
                    break
                }
                if ($result) { break }
            }
        }
    }
    if (-not $result -and -not $ignored -and $path) {
        $rp = $null; try { $rp = Get-RenPyName $path } catch {}
        if ($rp) { $result = [pscustomobject]@{ Exe = $base; Id = ''; Name = $rp; Icon = ''; Steam = ''; Args = ''; Image = ''; Via = 'renpy'; Kind = 'vn' } }
    }
    $script:MatchCache[$key] = $result
    return $result
}

# ---------------------------------------------------------------- Steam
$script:SteamNames = @{}
if (Test-Path $SteamCache) {
    foreach ($line in [IO.File]::ReadAllLines($SteamCache, [Text.Encoding]::UTF8)) {
        $f = $line.Split("`t"); if ($f.Length -ge 3) { $script:SteamNames[$f[0]] = [pscustomobject]@{ Name = $f[1]; Header = $f[2] } }
    }
}
function Get-SteamInfo([string]$id) {
    if ($script:SteamNames.ContainsKey($id)) { return $script:SteamNames[$id] }
    $name = ''; $header = ''
    try { $name = [string](Get-ItemProperty "HKCU:\Software\Valve\Steam\Apps\$id" -Name Name -ErrorAction Stop).Name } catch {}
    try {
        $r = Invoke-RestMethod -UseBasicParsing -TimeoutSec 5 -Uri "https://store.steampowered.com/api/appdetails?appids=$id&filters=basic"
        $d = $r.$id
        if ($d -and $d.success) {
            if ($d.data.type -and $d.data.type -ne 'game' -and $d.data.type -ne 'demo') { $name = '' ; $header = 'not-a-game' }
            else { if (-not $name) { $name = [string]$d.data.name }; $header = [string]$d.data.header_image }
        }
    } catch {}
    if (-not $name -and $header -ne 'not-a-game' -and $script:BySteam.ContainsKey($id)) { $name = $script:BySteam[$id].Name }
    $info = [pscustomobject]@{ Name = (Clean $name); Header = (Clean $header) }
    # zapamiętaj tylko pewny wynik; bez internetu spróbujemy znowu przy kolejnym uruchomieniu
    if ($info.Name -or $info.Header -eq 'not-a-game') {
        $script:SteamNames[$id] = $info
        [IO.File]::AppendAllText($SteamCache, "$id`t$($info.Name)`t$($info.Header)`n", $Utf8NoBom)
    }
    return $info
}
function Get-SteamRunning {
    try { $id = [string](Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name RunningAppID -ErrorAction Stop).RunningAppID } catch { return $null }
    if (-not $id -or $id -eq '0') { return $null }
    if ($SteamNotGames -contains $id -or $script:Ignore.ContainsKey("steam:$id")) { return $null }
    $info = Get-SteamInfo $id
    if (-not $info.Name -or $info.Header -eq 'not-a-game') { return $null }
    return [pscustomobject]@{ Steam = $id; Name = $info.Name; Header = $info.Header }
}

# ---------------------------------------------------------------- okno na pierwszym planie
if (-not ('VMGameDetector.Win' -as [type])) {
    Add-Type -Namespace VMGameDetector -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
'@
}
# okno gry dla OBS: «tytuł:klasa:plik.exe» (tak zapisuje je źródło przechwytywania okna / gry)
if (-not ('VMGameDetector.Win2' -as [type])) {
    Add-Type -Namespace VMGameDetector -Name Win2 -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder s, int n);
'@
}
function Get-WindowSpec([int]$procId) {
    if (-not $procId) { return $null }
    try {
        $pr = Get-Process -Id $procId -ErrorAction Stop
        $h = $pr.MainWindowHandle
        if ($h -eq [IntPtr]::Zero) { return $null }
        $sb = New-Object Text.StringBuilder 256
        [void][VMGameDetector.Win2]::GetClassName($h, $sb, 256)
        $exe = [IO.Path]::GetFileName($pr.Path)
        $enc = { param($t) ([string]$t).Replace('#', '#22').Replace(':', '#3A') }
        return [pscustomobject]@{ spec = (& $enc $pr.MainWindowTitle) + ':' + (& $enc $sb.ToString()) + ':' + (& $enc $exe); title = $pr.MainWindowTitle; exe = $exe }
    } catch { return $null }
}

# okno dowolnej pozycji z listy (gra albo program wybrany ręcznie) – do przechwytywania w OBS
function Find-ItemWindow([string]$id) {
    $e = $script:GameLib[$id]
    $path = if ($e -and $e.path) { [string]$e.path } else { '' }
    $dir = ''
    if (-not $path) { $o = @(Get-OtherGames | Where-Object { $_.id -eq $id }) | Select-Object -First 1; if ($o -and $o.exe) { $path = $o.exe } }
    if (-not $path -and $id -match '^steam:(\d+)$') { $g = @(Get-SteamInstalled | Where-Object { $_.id -eq $id }) | Select-Object -First 1; if ($g) { $dir = $g.dir } }
    $cands = @()
    if ($path) { $n = [IO.Path]::GetFileNameWithoutExtension($path); $cands = @(Get-Process -Name $n -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }) }
    elseif ($dir) { $cands = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.Path -and $_.Path.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase) }) }
    $pr = @($cands | Where-Object { $_.MainWindowTitle } | Sort-Object StartTime -Descending) | Select-Object -First 1
    if (-not $pr) { $pr = $cands | Select-Object -First 1 }
    if (-not $pr) { return $null }
    return Get-WindowSpec ([int]$pr.Id)
}

function Get-ForegroundPid {
    $h = [VMGameDetector.Win]::GetForegroundWindow()
    $fgPid = [uint32]0
    [void][VMGameDetector.Win]::GetWindowThreadProcessId($h, [ref]$fgPid)
    return [int]$fgPid
}

# ---------------------------------------------------------------- skan
$script:State = [pscustomobject]@{ game = $null; recent = @() }
$script:Current = $null          # klucz bieżącej gry
$script:FirstSeen = @{}
$script:Recent = New-Object Collections.ArrayList

function Get-Images($m) {
    $list = New-Object Collections.ArrayList
    if ($m.Image) { [void]$list.Add($m.Image) }
    if ($m.Header) { [void]$list.Add($m.Header) }
    if ($m.Steam) {
        [void]$list.Add("https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/$($m.Steam)/header.jpg")
        [void]$list.Add("https://cdn.cloudflare.steamstatic.com/steam/apps/$($m.Steam)/header.jpg")
    }
    if ($m.Id -and $m.Icon) { [void]$list.Add("https://cdn.discordapp.com/app-icons/$($m.Id)/$($m.Icon).png?size=256") }
    return , @($list | Select-Object -Unique)
}

# gry, które startują launcherem, a potem uruchamiają osobny program dla każdej części (Steam wciąż zgłasza launcher)
# Re – nazwa pliku procesu, Name – nazwa części, Family – do jakiej wykrytej gry (launchera) pasuje
$GameParts = @(
    @{ Re = '^masseffect1?\.exe$'; Name = 'Mass Effect 1'; Family = 'mass effect' }
    @{ Re = '^masseffect2\.exe$'; Name = 'Mass Effect 2'; Family = 'mass effect' }
    @{ Re = '^masseffect3\.exe$'; Name = 'Mass Effect 3'; Family = 'mass effect' }
    @{ Re = '^masseffectandromeda\.exe$'; Name = 'Mass Effect: Andromeda'; Family = 'mass effect' }
    @{ Re = '^gamemd\.exe$'; Name = "Command & Conquer: Red Alert 2 – Yuri's Revenge"; Family = 'red alert|command|c&c' }
    @{ Re = '^ra3ep1.*\.game$'; Name = 'Command & Conquer: Red Alert 3 – Uprising'; Family = 'red alert|command|c&c' }
    @{ Re = '^ra3_.*\.game$'; Name = 'Command & Conquer: Red Alert 3'; Family = 'red alert|command|c&c' }
    @{ Re = '^cnc3ep1.*\.(dat|exe)$'; Name = "Command & Conquer 3: Kane's Wrath"; Family = 'command|c&c|tiberium' }
    @{ Re = '^cnc3game\.dat$'; Name = 'Command & Conquer 3: Tiberium Wars'; Family = 'command|c&c|tiberium' }
)
# programy do tworzenia (nie gry): karta mówi «Teraz tworzę», a flagowanie botów nie traktuje tego jak grania
$MakeApps = @{
    'blender.exe' = 'Blender'; 'blender-launcher.exe' = 'Blender'; 'zbrush.exe' = 'ZBrush'; 'substance painter.exe' = 'Substance 3D Painter'
    'adobe substance 3d painter.exe' = 'Substance 3D Painter'; 'houdini.exe' = 'Houdini'; 'houdinifx.exe' = 'Houdini'; 'maya.exe' = 'Maya'
    '3dsmax.exe' = '3ds Max'; 'cinema 4d.exe' = 'Cinema 4D'; 'krita.exe' = 'Krita'; 'aseprite.exe' = 'Aseprite'; 'clipstudiopaint.exe' = 'Clip Studio Paint'
    'photoshop.exe' = 'Photoshop'; 'procreate.exe' = 'Procreate'; 'unity.exe' = 'Unity'; 'unrealeditor.exe' = 'Unreal Editor'; 'godot.exe' = 'Godot'
}
# gra na silniku Ren'Py (visual novel): nazwa z folderu gry, np. «Soulcreek-0.10-pc» → «Soulcreek»
function Get-RenPyName([string]$path) {
    $dir = Split-Path $path
    $root = $null
    if ($path -match '\\lib\\(py\d-)?windows-(x86_64|i686)\\[^\\]+$') { $root = Split-Path (Split-Path $dir) }
    elseif ((Test-Path (Join-Path $dir 'renpy')) -and (Test-Path (Join-Path $dir 'game'))) { $root = $dir }
    if (-not $root) { return $null }
    $leaf = Split-Path $root -Leaf
    $n = ($leaf -replace '[-_ ]v?\d+([._]\d+)*.*$', '') -replace '[-_]+', ' '
    if (-not $n.Trim()) { $n = $leaf }
    return $n.Trim()
}
# ---------------------------------------------------------------- biblioteka: każda wykryta gra / program, do uruchamiania z panelu
$LibraryFile = Join-Path $DataDir 'library.json'
# uwaga: nie «$Library» – wczytanie update.ps1 -Library (dot-source) nadpisałoby tę zmienną przełącznikiem
$script:GameLib = @{}
if (Test-Path $LibraryFile) { try { $lj = (Get-Content $LibraryFile -Raw -Encoding UTF8) | ConvertFrom-Json; foreach ($pp in $lj.PSObject.Properties) { if ($pp.Value -and $pp.Value.PSObject.Properties['id']) { $script:GameLib[$pp.Name] = $pp.Value } } } catch {} }
$script:LibDirty = $false; $script:LibSaved = Get-Date; $script:LibCurrent = ''; $script:LibTick = Get-Date
function Save-Library([switch]$Force) {
    if (-not $script:LibDirty) { return }
    if (-not $Force -and ((Get-Date) - $script:LibSaved).TotalSeconds -lt 30) { return }
    $script:LibDirty = $false; $script:LibSaved = Get-Date
    try { [IO.File]::WriteAllText($LibraryFile, ([pscustomobject]$script:GameLib | ConvertTo-Json -Depth 4 -Compress), $Utf8NoBom) } catch {}
}
# ---------------------------------------------------------------- Steam: zainstalowane gry i grafiki z pamięci Steama
# Grafiki (logo, tło, nagłówek) bierzemy z folderu, który Steam sam pobrał na ten komputer (appcache\librarycache),
# a gdy ich tam nie ma – z publicznego CDN Steama. Niczego nie kopiujemy do repozytorium; prawa do grafik
# mają ich właściciele (patrz CREDITS.md → «Grafiki gier»).
function Get-SteamRoot {
    try { $p = [string](Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath; if ($p) { return $p.Replace('/', '\') } } catch {}
    return ''
}
function Get-SteamLibraries {
    $root = Get-SteamRoot; if (-not $root) { return @() }
    $libs = New-Object Collections.ArrayList; [void]$libs.Add((Join-Path $root 'steamapps'))
    $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
            $sa = Join-Path ($mm.Groups[1].Value.Replace('\\', '\')) 'steamapps'
            if ((Test-Path $sa) -and -not ($libs -contains $sa)) { [void]$libs.Add($sa) }
        }
    }
    return @($libs)
}
# dodatki, które nie są samodzielną grą: muzyka, artbooki, «Bonus Content», DLC, serwery, narzędzia, biblioteki
$NotStandalone = '(?i)soundtrack|\bOST\b|art ?book|digital (deluxe )?(extras|content)|bonus content|wallpapers?\b|\bDLC\b|season pass|expansion pass|dedicated server|\bSDK\b|mod tools|creation kit|redistributable|steamworks|proton|runtime|benchmark tool|\bplaytest\b'
$script:SteamInstalled = $null; $script:SteamInstalledAt = [DateTime]::MinValue
function Get-SteamInstalled {
    if ($script:SteamInstalled -and ((Get-Date) - $script:SteamInstalledAt).TotalMinutes -lt 10) { return $script:SteamInstalled }
    $list = New-Object Collections.ArrayList
    foreach ($lib in Get-SteamLibraries) {
        foreach ($f in @(Get-ChildItem -LiteralPath $lib -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue)) {
            try {
                $t = [IO.File]::ReadAllText($f.FullName)
                $id = ([regex]::Match($t, '"appid"\s+"(\d+)"')).Groups[1].Value
                $nm = ([regex]::Match($t, '"name"\s+"([^"]+)"')).Groups[1].Value
                $dir = ([regex]::Match($t, '"installdir"\s+"([^"]+)"')).Groups[1].Value
                if (-not $id -or $SteamNotGames -contains $id -or $nm -match $NotStandalone) { continue }
                $full = Join-Path $lib "common\$dir"
                # bez żadnego .exe w folderze (np. soundtrack w steamapps\music, artbook) – to nie jest gra do uruchomienia
                if (-not (Test-Path -LiteralPath $full)) { continue }
                $hasExe = @(Get-ChildItem -LiteralPath $full -Filter '*.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1)
                if (-not $hasExe.Count) { continue }
                [void]$list.Add([pscustomobject]@{ id = "steam:$id"; name = (Clean $nm); steam = $id; dir = $full })
            } catch {}
        }
    }
    $script:SteamInstalled = @($list); $script:SteamInstalledAt = Get-Date
    return $script:SteamInstalled
}
# numer gry Steam z ścieżki programu (…\steamapps\common\<folder>\…)
function Get-SteamIdFromPath([string]$path) {
    if (-not $path) { return '' }
    $mm = [regex]::Match($path, '\\steamapps\\common\\([^\\]+)', 'IgnoreCase'); if (-not $mm.Success) { return '' }
    $dir = $mm.Groups[1].Value
    $hit = @(Get-SteamInstalled | Where-Object { (Split-Path $_.dir -Leaf) -eq $dir }) | Select-Object -First 1
    if ($hit) { return $hit.steam } else { return '' }
}
$ArtNames = @{ logo = @('logo.png'); hero = @('library_hero.jpg', 'library_hero.png'); header = @('header.jpg'); cover = @('library_600x900.jpg', 'library_capsule.jpg') }
function Get-SteamArtFile([string]$id, [string]$kind) {
    if ($id -notmatch '^\d+$' -or -not $ArtNames.ContainsKey($kind)) { return '' }
    $root = Get-SteamRoot; if (-not $root) { return '' }
    $lc = Join-Path $root 'appcache\librarycache'
    foreach ($n in $ArtNames[$kind]) { $f = Join-Path $lc "${id}_$n"; if (Test-Path -LiteralPath $f) { return $f } }
    $d = Join-Path $lc $id
    if (Test-Path -LiteralPath $d) {
        foreach ($n in $ArtNames[$kind]) { $f = @(Get-ChildItem -LiteralPath $d -Recurse -Filter $n -ErrorAction SilentlyContinue) | Select-Object -First 1; if ($f) { return $f.FullName } }
    }
    return ''
}
function Get-GameArt([string]$id) {
    if ($id -notmatch '^\d+$') { return $null }
    # /art podaje plik z pamięci Steama, a gdy go nie ma – przekierowuje na CDN Steama
    return [pscustomobject]@{ logo = "/art?id=$id&k=logo"; hero = "/art?id=$id&k=hero"; header = "/art?id=$id&k=header"; cover = "/art?id=$id&k=cover" }
}

# ---------------------------------------------------------------- gry z innych launcherów (Epic, GOG, Ubisoft, EA, Battle.net, Riot, Xbox…)
# Każdy launcher trzyma listę gier gdzie indziej: manifesty Epic, rejestr GOG/Ubisoft, wpisy «Odinstaluj» wydawców, foldery XboxGames.
$script:OtherGames = $null; $script:OtherGamesAt = [DateTime]::MinValue
$GamePublishers = '(?i)electronic arts|blizzard|riot games|paradox interactive|amazon game|rockstar games|bethesda|cd projekt|square enix|bandai namco|sega|capcom|konami|2k games|take-two|activision|focus (home|entertainment)|devolver|xbox game studios|warner bros|deep silver|thq|team17|frontier developments|annapurna|hooded horse|raw fury|humble games|505 games|nacon|kalypso|daedalic|ubisoft'
$NotAGame = '(?i)launcher|redistributable|anti-?cheat|easyanticheat|battleye|vanguard|^ea app|^origin$|ubisoft connect|uplay|battle\.net|update|helper|runtime|directx|visual c\+\+|\bsdk\b|overlay|installer|service|companion|toolkit|driver'
function Get-OtherGames {
    if ($script:OtherGames -and ((Get-Date) - $script:OtherGamesAt).TotalMinutes -lt 10) { return $script:OtherGames }
    $list = New-Object Collections.ArrayList; $seen = @{}
    $add = { param($id, $name, $src, $launch, $exe)
        $n = ([string](Clean $name)).Trim(); if (-not $n -or $n -match $NotAGame -or $n -match $NotStandalone -or $seen.ContainsKey($n.ToLowerInvariant())) { return }
        $seen[$n.ToLowerInvariant()] = 1
        [void]$list.Add([pscustomobject]@{ id = $id; name = $n; source = $src; launch = [string]$launch; exe = [string]$exe; kind = 'game' }) }
    # Epic Games
    try {
        foreach ($f in @(Get-ChildItem (Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests') -Filter '*.item' -ErrorAction Stop)) {
            try {
                $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
                $exe = if ($j.InstallLocation -and $j.LaunchExecutable) { Join-Path $j.InstallLocation $j.LaunchExecutable } else { '' }
                & $add ('epic:' + $j.AppName) $j.DisplayName 'Epic' ("com.epicgames.launcher://apps/$($j.AppName)?action=launch&silent=true") $exe
            } catch {}
        }
    } catch {}
    # GOG Galaxy
    foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games' -ErrorAction SilentlyContinue)) {
        try { $p = Get-ItemProperty $k.PSPath -ErrorAction Stop; & $add ('gog:' + $p.gameID) $p.gameName 'GOG' '' ([string]$p.exe) } catch {}
    }
    # Ubisoft Connect
    foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs' -ErrorAction SilentlyContinue)) {
        try { $p = Get-ItemProperty $k.PSPath -ErrorAction Stop; $dir = ([string]$p.InstallDir).TrimEnd('/', '\'); if ($dir -and (Test-Path $dir)) { & $add ('ubi:' + $k.PSChildName) (Split-Path $dir -Leaf) 'Ubisoft' ("uplay://launch/$($k.PSChildName)/0") '' } } catch {}
    }
    # EA, Battle.net, Riot, Paradox, Rockstar… – wpisy «Odinstaluj» wydawców gier
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($k in @(Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            try {
                $p = Get-ItemProperty $k.PSPath -ErrorAction Stop
                if (-not $p.DisplayName -or [int]$p.SystemComponent -eq 1 -or [string]$p.Publisher -notmatch $GamePublishers) { continue }
                if ([string]$p.UninstallString -match '(?i)steam\.exe|steamapps') { continue }    # Steam liczymy osobno
                $exe = ([string]$p.DisplayIcon -replace ',\s*-?\d+$', '').Trim('"')
                if ($exe -notmatch '(?i)\.exe$' -or -not (Test-Path -LiteralPath $exe)) { $exe = '' }
                $src = switch -Regex ([string]$p.Publisher) { 'Electronic Arts' { 'EA' } 'Blizzard' { 'Battle.net' } 'Riot' { 'Riot' } 'Paradox' { 'Paradox' } 'Rockstar' { 'Rockstar' } 'Ubisoft' { 'Ubisoft' } default { [string]$p.Publisher } }
                & $add ('reg:' + $k.PSChildName) $p.DisplayName $src '' $exe
            } catch {}
        }
    }
    # Xbox / Microsoft Store (foldery XboxGames na każdym dysku)
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $xb = Join-Path $d.Root 'XboxGames'
        foreach ($g in @(Get-ChildItem $xb -Directory -ErrorAction SilentlyContinue)) { if ($g.Name -ne 'GameSave') { & $add ('xbox:' + $g.Name) $g.Name 'Xbox' '' '' } }
    }
    $script:OtherGames = @($list); $script:OtherGamesAt = Get-Date
    return $script:OtherGames
}
# ikona programu (PNG) – z pliku .exe; gry Steam dostają okładkę przez /art
$script:IconCache = @{}
function Get-ExeIconPng([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
    if ($script:IconCache.ContainsKey($path)) { return $script:IconCache[$path] }
    $bytes = $null
    try {
        Add-Type -AssemblyName System.Drawing
        $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
        $bmp = $ic.ToBitmap(); $ms = New-Object IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bytes = $ms.ToArray(); $bmp.Dispose(); $ic.Dispose(); $ms.Dispose()
    } catch {}
    $script:IconCache[$path] = $bytes
    return $bytes
}

function Update-Library($m, [string]$path) {
    if (-not $m.Steam -and $path) { $sid = Get-SteamIdFromPath $path; if ($sid) { $m = $m.PSObject.Copy(); $m.Steam = $sid } }
    $id = if ($m.Steam) { 'steam:' + $m.Steam } elseif ($path) { 'exe:' + $path.ToLowerInvariant() } else { '' }
    if (-not $id) { return }
    $now = Get-Date
    $e = $script:GameLib[$id]
    if (-not $e) {
        $e = [pscustomobject]@{ id = $id; name = $m.Name; path = $path; exe = $m.Exe; steam = [string]$m.Steam; kind = [string]$m.Kind; first = $now.ToString('o'); last = ''; plays = 0; minutes = 0; hidden = $false }
        $script:GameLib[$id] = $e
        Log "Biblioteka: zapisano $($m.Name)" 'DarkCyan'
    }
    if (-not $e.path -and $path) { $e.path = $path }
    if ($script:LibCurrent -ne $id) { $e.plays = [int]$e.plays + 1; $script:LibCurrent = $id; $script:LibTick = $now }
    $e.minutes = [Math]::Round([double]$e.minutes + ($now - $script:LibTick).TotalMinutes, 1); $script:LibTick = $now
    $e.last = $now.ToString('o'); $script:LibDirty = $true
    Save-Library
}
$script:AppSeen = @{}; $script:AppTick = Get-Date; $script:LibErr = ''
function Update-AppSeen([string]$path) {
    $now = Get-Date; $dt = [Math]::Min(10.0, ($now - $script:AppTick).TotalSeconds); $script:AppTick = $now
    if (-not $path -or $path -match '\\steamapps\\common\\') { return }    # gry ze Steama zapisuje Update-Library
    $id = 'exe:' + $path.ToLowerInvariant()
    if ($script:LibCurrent -eq $id) { return }                                # to jest właśnie wykryta gra
    $e = $script:GameLib[$id]
    if (-not $e) {
        $script:AppSeen[$id] = [double]$script:AppSeen[$id] + $dt
        if ($script:AppSeen[$id] -lt 20) { return }
        $name = ''
        try { $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($path); if ($vi.FileDescription) { $name = $vi.FileDescription } elseif ($vi.ProductName) { $name = $vi.ProductName } } catch {}
        $name = ([string](Clean $name)).Trim()
        if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($path) }
        # bez «.exe» i oczywistości («Opera GX Internet Browser» → «Opera GX», «SnippingTool» → «Snipping Tool»)
        $wasFile = $name -match '(?i)\.exe$' -or $name -notmatch ' '
        $name = $name -replace '(?i)\.exe$', '' -replace '(?i)\s+(internet\s+|web\s+)?browser$', '' -replace '(?i)\s*\((x64|x86|64-bit|32-bit)\)$', '' -replace '(?i)\s+(for windows|application|desktop app|desktop)$', ''
        if ($wasFile -and $name -cmatch '^[A-Z][a-z]+[A-Z]') { $name = $name -creplace '([a-z])([A-Z])', '$1 $2' }   # nazwa z pliku: SnippingTool → Snipping Tool
        $name = $name.Trim()
        $e = [pscustomobject]@{ id = $id; name = $name; path = $path; exe = [IO.Path]::GetFileName($path).ToLowerInvariant(); steam = ''; kind = 'app'; first = $now.ToString('o'); last = ''; plays = 1; minutes = 0; hidden = $false }
        $script:GameLib[$id] = $e
        Log "Biblioteka: zapisano program $name" 'DarkCyan'
    }
    $e.minutes = [Math]::Round([double]$e.minutes + $dt / 60, 1)
    $e.last = $now.ToString('o'); $script:LibDirty = $true
    Save-Library
}
function Start-LibraryItem([string]$id) {
    $e = $script:GameLib[$id]
    if (-not $e -and $id -match '^steam:(\d+)$') { Start-Process ("steam://rungameid/" + $Matches[1]); Log "Uruchamiam: $id (Steam)" 'Cyan'; return '' }
    if (-not $e) {
        $o = @(Get-OtherGames | Where-Object { $_.id -eq $id }) | Select-Object -First 1
        if ($o) {
            if ($o.launch) { Start-Process $o.launch; Log "Uruchamiam: $($o.name) ($($o.source))" 'Cyan'; return '' }
            if ($o.exe -and (Test-Path -LiteralPath $o.exe)) { Start-Process -FilePath $o.exe -WorkingDirectory (Split-Path $o.exe); Log "Uruchamiam: $($o.name)" 'Cyan'; return '' }
            return "tę grę uruchom z aplikacji $($o.source)"
        }
    }
    if (-not $e) { return 'nie ma takiej pozycji w bibliotece' }
    if ($e.steam) { Start-Process ("steam://rungameid/" + $e.steam); Log "Uruchamiam: $($e.name) (Steam)" 'Cyan'; return '' }
    if ($e.path -and (Test-Path -LiteralPath $e.path)) { Start-Process -FilePath $e.path -WorkingDirectory (Split-Path $e.path); Log "Uruchamiam: $($e.name)" 'Cyan'; return '' }
    return 'nie znaleziono pliku programu'
}

function Update-State {
    Import-Custom
    $fgPid = Get-ForegroundPid
    $procs = Get-CimInstance -ClassName Win32_Process -Property ProcessId, ExecutablePath, CommandLine, CreationDate -ErrorAction SilentlyContinue
    $found = New-Object Collections.ArrayList
    $fgPath = $null
    $part = $null
    foreach ($p in $procs) {
        $path = $p.ExecutablePath
        if (-not $path) { continue }
        if ($p.ProcessId -eq $fgPid) { $fgPath = $path }
        $pexe = [IO.Path]::GetFileName($path).ToLowerInvariant()
        foreach ($gp in $GameParts) {
            if ($pexe -notmatch $gp.Re) { continue }
            $pn = $gp.Name; if ($path -match 'legendary' -and $pn -match '^Mass Effect \d') { $pn += ' (Legendary Edition)' }
            $part = [pscustomobject]@{ Name = $pn; Exe = $pexe; Start = $p.CreationDate; Family = $gp.Family; Pid = $p.ProcessId; Path = $path }
            break
        }
        $m = Find-Game $path $p.CommandLine
        if ($m) { [void]$found.Add([pscustomobject]@{ M = $m; Pid = $p.ProcessId; Start = $p.CreationDate; Path = $path }) }
    }

    # ostatnie okna na pierwszym planie (do «Dodaj jako grę» w panelu)
    if ($fgPath) {
        $exe = [IO.Path]::GetFileName($fgPath).ToLowerInvariant()
        if ($NeverGame -notcontains $exe -and $exe -ne 'msedgewebview2.exe') {
            $title = ''
            try { $title = (Get-Process -Id $fgPid -ErrorAction Stop).MainWindowTitle } catch {}
            $old = @($script:Recent | Where-Object { $_.exe -eq $exe })
            foreach ($o in $old) { $script:Recent.Remove($o) }
            $script:Recent.Insert(0, [pscustomobject]@{ exe = $exe; title = $title })
            while ($script:Recent.Count -gt 6) { $script:Recent.RemoveAt($script:Recent.Count - 1) }
            # każdy program, który był na wierzchu dłużej niż 20 s (Notatnik, Chrome, Opera…), trafia do «Co dziś?»
            try { Update-AppSeen $fgPath } catch { if ($script:LibErr -ne $_.Exception.Message) { $script:LibErr = $_.Exception.Message; Log "Biblioteka: $($script:LibErr)" 'Yellow' } }
        }
    }

    # wybór gry: Steam > gra na pierwszym planie > dotychczasowa > najnowsza
    $pick = $null
    $steam = Get-SteamRunning
    if ($steam) {
        $same = @($found | Where-Object { $_.M.Steam -eq $steam.Steam }) | Select-Object -First 1
        $m = [pscustomobject]@{ Exe = ''; Id = ''; Name = $steam.Name; Icon = ''; Steam = $steam.Steam; Image = ''; Header = $steam.Header; Via = 'steam' }
        if ($same) { $m.Exe = $same.M.Exe; $m.Id = $same.M.Id; $m.Icon = $same.M.Icon; if ($same.M.Via -eq 'my-games') { $m.Name = $same.M.Name; $m.Image = $same.M.Image } }
        # okno gry ze Steama: proces z listy albo – gdy go nie znamy – okno na pierwszym planie z folderu steamapps
        $spid = 0; $spath = ''
        if ($same) { $spid = $same.Pid; $spath = $same.Path } elseif ($fgPath -and $fgPath -match '\\steamapps\\common\\') { $spid = $fgPid; $spath = $fgPath }
        $pick = [pscustomobject]@{ M = $m; Start = $(if ($same) { $same.Start } else { $null }); Pid = $spid; Path = $spath }
    }
    if (-not $pick -and $found.Count) {
        $pick = @($found | Where-Object { $_.Pid -eq $fgPid }) | Select-Object -First 1
        if (-not $pick) { $pick = @($found | Where-Object { $_.M.Name -eq $script:Current }) | Select-Object -First 1 }
        if (-not $pick) { $pick = @($found | Sort-Object Start -Descending) | Select-Object -First 1 }
    }

    # launcher → konkretna część (np. Mass Effect Legendary Edition → Mass Effect 2 (Legendary Edition))
    if ($part) {
        if ($pick -and $pick.M.Name -match $part.Family) {
            $m2 = $pick.M.PSObject.Copy(); $m2.Name = $part.Name; $m2.Exe = $part.Exe
            $pick = [pscustomobject]@{ M = $m2; Start = $part.Start; Pid = $part.Pid; Path = $part.Path }
        } elseif (-not $pick) {
            $pick = [pscustomobject]@{ M = [pscustomobject]@{ Exe = $part.Exe; Id = ''; Name = $part.Name; Icon = ''; Steam = ''; Args = ''; Image = ''; Header = ''; Via = 'part' }; Start = $part.Start; Pid = $part.Pid; Path = $part.Path }
        }
    }

    $game = $null
    if ($pick) {
        $m = $pick.M
        if (-not $script:FirstSeen.ContainsKey($m.Name)) { $script:FirstSeen[$m.Name] = Get-Date }
        $start = $pick.Start
        if (-not $start) { $start = $script:FirstSeen[$m.Name] }
        $game = [pscustomobject]@{
            name   = $m.Name
            exe    = $m.Exe
            via    = $m.Via
            steam  = $m.Steam
            start  = [long]([DateTimeOffset]$start).ToUnixTimeMilliseconds()
            images = (Get-Images $m)
            kind   = [string]$m.Kind
            window = ''
            path   = [string]$pick.Path
            art    = $null
        }
        try { if (-not $game.steam -and $game.path) { $game.steam = Get-SteamIdFromPath $game.path }; $game.art = Get-GameArt ([string]$game.steam) } catch {}
        $ws = Get-WindowSpec ([int]$pick.Pid)
        if ($ws) { $game.window = $ws.spec }
        try { Update-Library $m ([string]$pick.Path) } catch { if ($script:LibErr -ne $_.Exception.Message) { $script:LibErr = $_.Exception.Message; Log "Biblioteka: nie udało się zapisać $($m.Name) – $($script:LibErr)" 'Yellow' } }
        if ($script:Current -ne $m.Name) {
            $from = $m.Via; if ($m.Exe) { $from += ", $($m.Exe)" }
            Log "Gra: $($m.Name)   ($from)" 'Cyan'
        }
        $script:Current = $m.Name
    } elseif ($script:Current) {
        Log "Koniec gry: $script:Current" 'DarkGray'
        $script:FirstSeen.Remove($script:Current)
        $script:Current = $null
    }
    if (-not $game) { $script:LibCurrent = '' }
    $script:State = [pscustomobject]@{ game = $game; recent = @($script:Recent) }
}
