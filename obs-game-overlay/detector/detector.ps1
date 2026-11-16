#Requires -Version 5.1
<#
  Vincent-Media – wykrywacz gier dla nakładki OBS.

  Działa jak wykrywanie gier w Discordzie:
    1. pobiera publiczną bazę gier Discorda (nazwy plików .exe -> nazwa gry),
    2. co kilka sekund sprawdza uruchomione programy,
    3. dodatkowo pyta Steama, jaka gra jest uruchomiona (pewna nazwa + okładka),
    4. wystawia wynik pod http://localhost:7777/game dla nakładki.

  Uruchamianie: program «Vincent-Media» (launcher\launcher.vbs) albo: powershell -ExecutionPolicy Bypass -File detector.ps1
#>
param(
    [int]$Port = 7777,
    [double]$Interval = 3,
    [int]$DbMaxAgeDays = 7,
    [switch]$Hidden,          # uruchomiony bez okna (kreator startu, autostart: launcher.vbs /tlo)
    [int]$WaitStart = 0,      # po aktualizacji: poczekaj, aż poprzednia wersja zwolni port
    [switch]$StartObs         # GameRadar, a zaraz po nim OBS
)
# OBS z rejestru albo z typowych folderów; uruchamiany z własnego folderu (inaczej OBS nie znajdzie swoich plików)
function Find-Obs {
    foreach ($k in 'HKLM:\SOFTWARE\OBS Studio', 'HKLM:\SOFTWARE\WOW6432Node\OBS Studio') {
        try { $d = (Get-ItemProperty $k -ErrorAction Stop).'(default)'; if ($d) { $e = Join-Path $d 'bin\64bit\obs64.exe'; if (Test-Path $e) { return $e } } } catch {}
    }
    foreach ($d in @("$env:ProgramFiles\obs-studio", "${env:ProgramFiles(x86)}\obs-studio")) { $e = Join-Path $d 'bin\64bit\obs64.exe'; if (Test-Path $e) { return $e } }
    return ''
}
function Start-Obs {
    if (Get-Process -Name obs64, obs32 -ErrorAction SilentlyContinue) { return 'OBS już działa' }
    $e = Find-Obs; if (-not $e) { return 'nie znalazłem OBS (zainstaluj OBS Studio)' }
    Start-Process -FilePath $e -WorkingDirectory (Split-Path $e); return 'uruchamiam OBS'
}
if ($WaitStart -gt 0) { Start-Sleep -Seconds $WaitStart }
# jedna kopia naraz: gdy wykrywacz już działa, kolejne uruchomienie (np. z panelu w OBS) od razu się kończy.
# Po aktualizacji nowa wersja czeka, aż stara się zamknie.
$script:Mutex = New-Object Threading.Mutex($false, 'Local\VincentMediaDetector')
$gotMutex = $false
try { $gotMutex = $script:Mutex.WaitOne([TimeSpan]::FromSeconds([Math]::Max(1, $WaitStart * 6))) } catch [Threading.AbandonedMutexException] { $gotMutex = $true }
# inna kopia trzyma blokadę: jeśli odpowiada – zostawiamy ją; jeśli nie (zawieszona po aktualizacji) – zamykamy ją i startujemy
function Stop-StaleDetector {
    $alive = $false
    # dwie próby po 6 s: zajęty (np. skanuje bibliotekę Steama) to nie to samo co zawieszony
    # każda odpowiedź HTTP (także 403 – odmowa bez klucza) znaczy, że kopia żyje; zawieszona nie odpowiada wcale
    foreach ($try in 1, 2) {
        try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 6 -Uri "http://localhost:$Port/update/status"; $alive = $true; break }
        catch { if ($_.Exception.Response) { $alive = $true; break } }
    }
    if ($alive) { return $false }
    $n = 0
    try {
        foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'detector\.ps1' })) {
            try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $n++ } catch {}
        }
    } catch {}
    if ($n) { Write-Host "Zamknięto zawieszony wykrywacz ($n)." -ForegroundColor Yellow; Start-Sleep -Milliseconds 800 }
    return $true
}
if (-not $gotMutex) {
    if (-not (Stop-StaleDetector)) { if ($StartObs) { [void](Start-Obs) }; exit 0 }      # działa już poprawna kopia (ze skrótu «Start streamu» – tylko OBS)
    try { $gotMutex = $script:Mutex.WaitOne([TimeSpan]::FromSeconds(5)) } catch [Threading.AbandonedMutexException] { $gotMutex = $true }
    if (-not $gotMutex) { exit 0 }
}

# «Zamknij OBS i GameRadar» (strona) zostawia znacznik data\stopped.flag. Uruchomienie w tle (strażnik co 5 min, autostart)
# kończy się od razu, jeśli znacznik jest z tej sesji Windows i OBS nie działa. Ręczne uruchomienie, «Start streamu»
# albo start razem z OBS (panel) zdejmuje znacznik. Dzięki temu strażnik nie wskrzesi GameRadara, a ten nie odpali
# na nowo OBS (opcja «uruchamiaj OBS razem z GameRadarem») – zamknięte zostaje zamknięte aż do Twojego ruchu.
$StoppedFlag = Join-Path (Join-Path $PSScriptRoot 'data') 'stopped.flag'
if (Test-Path $StoppedFlag) {
    $obsUp = [bool](Get-Process -Name obs64, obs32 -ErrorAction SilentlyContinue)
    $boot = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime } catch { [DateTime]::MinValue }
    if ($Hidden -and -not $StartObs -and -not $obsUp -and (Get-Item $StoppedFlag).LastWriteTime -gt $boot) { try { $script:Mutex.ReleaseMutex() } catch {}; exit 0 }
    Remove-Item $StoppedFlag -Force -ErrorAction SilentlyContinue
}
$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'Vincent-Media: wykrywacz gier'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Root       = $PSScriptRoot
$DataDir    = Join-Path $Root 'data'
$IndexFile  = Join-Path $DataDir 'games-index.tsv'
$SteamCache = Join-Path $DataDir 'steam-names.tsv'
$CustomFile = Join-Path $Root 'my-games.txt'
$Utf8NoBom  = New-Object Text.UTF8Encoding $false
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

# Programy, które nigdy nie są grą (np. okno OBS, gdy klikasz w panel).
$NeverGame = @('obs64.exe','obs32.exe','obs.exe','explorer.exe','powershell.exe','pwsh.exe','conhost.exe',
               'windowsterminal.exe','cmd.exe','discord.exe','steam.exe','steamwebhelper.exe','applicationframehost.exe',
               'shellexperiencehost.exe','searchhost.exe','startmenuexperiencehost.exe','lockapp.exe','textinputhost.exe')
# Aplikacje Steama, które nie są grami.
$SteamNotGames = @('228980','431960','250820','1070560','1391110','1628350')  # redist, Wallpaper Engine, SteamVR, Steam Linux Runtime...

# dziennik także do pliku (data\detector.log) – przydaje się, gdy wykrywacz działa w tle bez okna
$script:LogFile = Join-Path (Join-Path $PSScriptRoot 'data') 'detector.log'
# ostatnie linijki także w pamięci – panel pokazuje je w «terminalu» (Więcej → Wykrywacz), gdy okno jest schowane
$script:LogBuf = New-Object Collections.ArrayList; $script:LogSeq = 0
function Log([string]$msg, [string]$color = 'Gray') {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg
    Write-Host $line -ForegroundColor $color
    $script:LogSeq++; [void]$script:LogBuf.Add([pscustomobject]@{ n = $script:LogSeq; t = $line; c = $color })
    while ($script:LogBuf.Count -gt 300) { $script:LogBuf.RemoveAt(0) }
    try {
        if ((Test-Path $script:LogFile) -and (Get-Item $script:LogFile).Length -gt 1MB) { Move-Item $script:LogFile ($script:LogFile + '.old') -Force }
        [IO.File]::AppendAllText($script:LogFile, ("{0:yyyy-MM-dd} {1}`r`n" -f (Get-Date), $line), [Text.Encoding]::UTF8)
    } catch {}
}
function Get-Val($dict, [string]$key) {
    if ($null -ne $dict -and $dict.ContainsKey($key)) { return $dict[$key] }
    return $null
}
function Clean($s) {
    if ($null -eq $s) { return '' }
    return ([string]$s) -replace "[`t`r`n]", ' '
}

# ---------------------------------------------------------------- części GameRadara (detector\core\*.ps1)
# Kolejność ma znaczenie: każda część korzysta z poprzednich. Wszystkie są wymagane (moduły opcjonalne są w mods\).
$DetectorScript = $PSCommandPath        # restart (core\updates.ps1) uruchamia ten plik, nie część
foreach ($part in @('games', 'chat', 'archive', 'twitch', 'updates', 'http', 'backup', 'api')) { . (Join-Path $PSScriptRoot "core\$part.ps1") }

# ---------------------------------------------------------------- start
Write-Host ''
Write-Host "  Vincent-Media – wykrywacz gier  v$($script:AppVersion)" -ForegroundColor Magenta
Write-Host "  Nakładka czyta: http://localhost:$Port/game   (Ctrl+C = koniec)" -ForegroundColor DarkGray
Write-Host ''

$needDb = -not (Test-Path $IndexFile)
if (-not $needDb) { $needDb = ((Get-Date) - (Get-Item $IndexFile).LastWriteTime).TotalDays -gt $DbMaxAgeDays }
if ($needDb) { Update-Index }
Import-Index
Initialize-CustomFile
Import-Custom
Initialize-Twitch

# moduły: każdy w osobnym pliku – zablokowany (antywirus, błąd) wyłącza tylko swoją funkcję
$script:Mods = [ordered]@{}
foreach ($m in @('censor', 'tts', 'windows', 'piper', 'bot')) {
    $mf = Join-Path $PSScriptRoot "mods\$m.ps1"
    try { . $mf; $script:Mods[$m] = 'ok' }
    catch {
        $script:Mods[$m] = $(if ($_.FullyQualifiedErrorId -match 'Malicious') { 'antywirus' } else { 'błąd' })
        Log ("Moduł «{0}» nie wczytany ({1}): {2}" -f $m, $script:Mods[$m], $_.Exception.Message) 'Yellow'
    }
}
Log ('Moduły: ' + (($script:Mods.Keys | ForEach-Object { "$_ $($script:Mods[$_])" }) -join ', ')) 'DarkGray'

# tylko na tym komputerze: najpierw «localhost»; gdy Windows odmawia (np. stara rezerwacja portu po dawnym pilocie
# przez Wi-Fi), przez tę starą rezerwację – zapytania spoza tego komputera i tak dostają 403
function Open-Listener {
    $errs = @()
    foreach ($pre in @("http://localhost:$Port/", "http://+:$Port/")) {
        $l = New-Object Net.HttpListener; $l.Prefixes.Add($pre)
        try { $l.Start(); if ($pre -ne "http://localhost:$Port/") { Log "Port ${Port}: «localhost» niedostępny, słucham przez $pre" 'DarkYellow' }; return @{ l = $l; err = '' } }
        catch { $errs += $_.Exception.Message; try { $l.Close() } catch {} }
    }
    return @{ l = $null; err = ($errs | Select-Object -First 1) }
}
$open = Open-Listener
if (-not $open.l -and (Stop-StaleDetector)) { Start-Sleep -Milliseconds 500; $open = Open-Listener }
if (-not $open.l) {
    Log "Nie mogę otworzyć portu $Port – może GameRadar już działa w innym oknie? ($($open.err))" 'Red'
    [Environment]::Exit(1)
}
$listener = $open.l
Log "Nasłuchuję na http://localhost:$Port/" 'Green'
# OBS razem z GameRadarem: ze skrótu «Start streamu» albo gdy włączone w panelu (GameRadar → «Uruchamiaj OBS»)
$LaunchFile = Join-Path $DataDir 'launch.json'
$script:LaunchObs = $false; try { $script:LaunchObs = [bool]((Get-Content $LaunchFile -Raw -Encoding UTF8) | ConvertFrom-Json).obs } catch {}
if ($StartObs -or $script:LaunchObs) { try { Log ('Start streamu: ' + (Start-Obs)) 'Green' } catch { Log "Nie udało się uruchomić OBS: $($_.Exception.Message)" 'Yellow' } }

try {
    $next = [DateTime]::MinValue
    $task = $listener.GetContextAsync()
    while ($listener.IsListening) {
        if ([DateTime]::Now -ge $next) {
            try { Update-State } catch { Log "Błąd skanu: $($_.Exception.Message)" 'Red' }
            $next = [DateTime]::Now.AddSeconds($Interval)
        }
        try { Update-Updater } catch { Log "Aktualizacja: $($_.Exception.Message)" 'DarkYellow' }
        try { if (Get-Command Update-BotTimers -ErrorAction SilentlyContinue) { Update-BotTimers } } catch {}
        try { Update-Backup } catch {}
        if ($script:ShutdownAt) { Stop-Everything }
        if ($script:RestartPending -and -not (Test-Live)) { Restart-Detector }   # restart (nowa wersja) nigdy w trakcie transmisji/nagrywania
        try { Update-Archive } catch {}
        try { Update-Relay } catch { $script:RelayTask = $null; $script:RelayNext = (Get-Date).AddSeconds(30) }
        try { Update-Twitch } catch { Log "Twitch: $($_.Exception.Message)" 'Red'; Stop-TwitchSocket; $script:TW.reconnectAt = (Get-Date).AddSeconds(20) }
        if ($task.Wait(200)) {
            Invoke-Request $task.Result
            if ($script:RestartPending -and -not (Test-Live)) { Restart-Detector }
            $task = $listener.GetContextAsync()
        }
    }
} catch {
    Log "Wykrywacz zatrzymał się przez błąd: $($_.Exception.Message)" 'Red'
} finally {
    try { Save-Chatters -Force; Save-StreamSummary; Save-Library -Force } catch {}
    try { $listener.Stop(); $listener.Close() } catch {}
    Stop-Censor
}
[Environment]::Exit(0)
