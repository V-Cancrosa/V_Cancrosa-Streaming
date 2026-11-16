#Requires -Version 5.1
# GameRadar · część «updates»: aktualizacje z GitHuba i restart GameRadara
# Wczytywana przez detector.ps1 (dot-source) w ustalonej kolejności – korzysta z rzeczy z poprzednich części.
# Ścieżki: $Root = folder detector, $DataDir = detector\data, $AppDir = folder aplikacji (nie $PSScriptRoot – to byłby folder core).

# ---------------------------------------------------------------- aktualizacje
$AppDir = Split-Path $Root
$UpdateScript = Join-Path $AppDir 'update.ps1'
$UpdateCfg = Join-Path $DataDir 'update.json'
$script:CanUpdate = Test-Path $UpdateScript
if ($script:CanUpdate) { . $UpdateScript -Library }
# porządek w folderze i skrótach (program «Vincent-Media» z ikoną zamiast kilku skrótów) – za każdym startem, nic nie psuje
if ($script:CanUpdate) { try { Update-VMLayout $AppDir } catch {} }
function Get-AppVersion {
    try { return [string]((Get-Content (Join-Path $AppDir 'version.json') -Raw -Encoding UTF8) | ConvertFrom-Json).version } catch { return '0.0.0' }
}
$script:AppVersion = Get-AppVersion
$script:UP = [pscustomobject]@{
    auto = $true; latest = ''; notes = ''; error = ''; lastCheck = $null; busy = $false
    nextCheck = (Get-Date).AddSeconds(60); nextLocal = (Get-Date).AddSeconds(30)
}
if (Test-Path $UpdateCfg) { try { $script:UP.auto = [bool]((Get-Content $UpdateCfg -Raw) | ConvertFrom-Json).auto } catch {} }
$script:RestartPending = $false

# transmisja albo nagrywanie (panel w OBS melduje co kilka sekund): wtedy żadnej instalacji ani restartu – dopiero po zakończeniu
$script:Live = [pscustomobject]@{ stream = $false; rec = $false; until = [DateTime]::MinValue }
function Test-Live { return ((Get-Date) -lt $script:Live.until) -and ($script:Live.stream -or $script:Live.rec) }
function Get-UpdateStatus {
    $live = Test-Live
    return [pscustomobject]@{
        nextIn = [int][Math]::Min([double]86400, [Math]::Max([double]0, ($script:UP.nextCheck - (Get-Date)).TotalSeconds)); everyMin = 10
        paused = [bool]$live; pausedWhy = $(if (-not $live) { '' } elseif ($script:Live.stream -and $script:Live.rec) { 'transmisja i nagrywanie' } elseif ($script:Live.stream) { 'transmisja' } else { 'nagrywanie' })
        pending = [bool]$script:RestartPending
        cockpitAgo = $(if ($script:CockpitSeen) { [int]((Get-Date) - $script:CockpitSeen).TotalSeconds } else { -1 })
        installed = $script:AppVersion; latest = $script:UP.latest; notes = $script:UP.notes; auto = $script:UP.auto
        error = $script:UP.error; canUpdate = $script:CanUpdate
        lastCheck = $(if ($script:UP.lastCheck) { $script:UP.lastCheck.ToString('HH:mm') } else { '' })
        newer = [bool]($script:UP.latest -and (Test-VMNewerSafe $script:UP.latest $script:AppVersion))
    }
}
function Test-VMNewerSafe([string]$a, [string]$b) { try { return ([version]$a) -gt ([version]$b) } catch { return $false } }

function Invoke-UpdateCheck([switch]$Install, [switch]$Force) {
    if (-not $script:CanUpdate) { $script:UP.error = 'brak update.ps1 obok wykrywacza'; return }
    $script:UP.lastCheck = Get-Date; $script:UP.error = ''
    try {
        $r = Get-VMRemoteInfo
        $script:UP.latest = [string]$r.version; $script:UP.notes = [string]$r.notes
        # -Force: naprawa plików (Nora → «Wszystkie pliki na miejscu»), nawet gdy wersja jest ta sama
        if ($Install -and ($Force -or (Test-VMNewerSafe $script:UP.latest $script:AppVersion))) {
            Log "Aktualizacja: pobieram wersję $($script:UP.latest)…" 'Cyan'
            $n = Install-VMFiles $AppDir
            Log "Aktualizacja: podmienione pliki: $n" 'Green'
            $script:RestartPending = $true
        }
    } catch {
        $script:UP.error = $_.Exception.Message
        Log "Aktualizacja: nie udało się ($($script:UP.error))" 'DarkYellow'
    }
}

function Update-Updater {
    $now = Get-Date
    # ktoś uruchomił update.bat ręcznie – nowa wersja na dysku, uruchom ją
    if ($now -ge $script:UP.nextLocal) {
        $script:UP.nextLocal = $now.AddSeconds(30)
        if ((Get-AppVersion) -ne $script:AppVersion) { $script:RestartPending = $true }
        # ktoś poprosił o restart (plik restart.flag w data)
        if (Test-Path $RestartFlag) { Remove-Item $RestartFlag -Force -ErrorAction SilentlyContinue; $script:RestartPending = $true }
    }
    if ($script:UP.auto -and $now -ge $script:UP.nextCheck) {
        if (Test-Live) { $script:UP.nextCheck = $now.AddSeconds(30); return }   # na żywo: czekamy, sprawdzimy zaraz po zakończeniu
        $script:UP.nextCheck = $now.AddMinutes(10)      # automatyczna aktualizacja: sprawdzenie co 10 minut
        Invoke-UpdateCheck -Install
    }
}

$script:ShutdownAt = $null
function Stop-Everything {
    foreach ($p in @(Get-Process -Name obs64, obs32 -ErrorAction SilentlyContinue)) { try { [void]$p.CloseMainWindow() } catch {} }
    # do 20 s na zamknięcie OBS (zapisuje sceny i ustawienia); potem twardo, żeby nie wisiał
    for ($i = 0; $i -lt 40 -and (Get-Process -Name obs64, obs32 -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
    foreach ($p in @(Get-Process -Name obs64, obs32 -ErrorAction SilentlyContinue)) { try { $p.Kill(); Log 'OBS nie zamknął się sam – zamknięty na siłę' 'Yellow' } catch {} }
    try { [IO.File]::WriteAllText($StoppedFlag, (Get-Date).ToString('o'), $Utf8NoBom) } catch {}
    Log 'OBS zamknięty. GameRadar kończy pracę. Do zobaczenia!' 'Green'
    try { Save-Chatters -Force; Save-StreamSummary; Save-Library -Force } catch {}
    try { $listener.Stop(); $listener.Close() } catch {}
    Stop-Censor
    try { $script:Mutex.ReleaseMutex() } catch {}
    [Environment]::Exit(0)
}
function Restart-Detector {
    Log "Uruchamiam wykrywacz w nowej wersji ($(Get-AppVersion))…" 'Cyan'
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $DetectorScript + '"'), '-WaitStart', '2')
    if ($Hidden) { Start-Process powershell.exe -ArgumentList ($a + '-Hidden') -WindowStyle Hidden }
    else { Start-Process powershell.exe -ArgumentList $a }
    try { $listener.Stop(); $listener.Close() } catch {}
    Stop-Censor
    try { Save-Library -Force } catch {}
    try { $script:Mutex.ReleaseMutex() } catch {}
    # twarde wyjście: wątek cenzury ekranu nie może trzymać starego procesu (i portu) przy życiu
    [Environment]::Exit(0)
}
