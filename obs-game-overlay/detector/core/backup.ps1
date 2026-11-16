#Requires -Version 5.1
# GameRadar · część «backup»: kopie zapasowe Twoich danych – raz dziennie, ostatnie 14 dni, przywracanie ze strony (Dziennik)
# Wczytywana przez detector.ps1 (dot-source) w ustalonej kolejności – korzysta z rzeczy z poprzednich części.
#
# W kopii: ustawienia (settings.json), strony Kreatora i uwagi (kv.json), biblioteka gier (library.json), widzowie
# (wybrane style czatu), uruchamianie OBS, przekaźnik pilota, zaufane strony, my-games.txt.
# BEZ sekretów: logowanie Twitcha (twitch-token.bin, twitch.json) i klucz tego komputera (local-key.txt) nie trafiają do kopii.

$BackupDir = Join-Path $DataDir 'backup'
$BackupFiles = @('settings.json', 'kv.json', 'library.json', 'viewers.json', 'launch.json', 'relay.json', 'trusted-origins.txt', 'update.json', 'obs-theme.json')
$script:BackupCheckAt = [DateTime]::MinValue

function New-Backup([string]$tag = '') {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $name = 'backup-' + (Get-Date).ToString('yyyy-MM-dd-HHmm') + $(if ($tag) { '-' + $tag } else { '' }) + '.zip'
    $tmp = Join-Path $env:TEMP ('vm-backup-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        foreach ($f in $BackupFiles) { $p = Join-Path $DataDir $f; if (Test-Path $p) { Copy-Item -LiteralPath $p -Destination $tmp } }
        if (Test-Path $CustomFile) { Copy-Item -LiteralPath $CustomFile -Destination $tmp }
        if (-not (Get-ChildItem $tmp)) { return '' }
        $zip = Join-Path $BackupDir $name
        Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip -Force
        # zostaje 14 najnowszych kopii dziennych (kopie «przed przywróceniem» liczą się osobno, zostają 5)
        @(Get-ChildItem $BackupDir -Filter 'backup-*.zip' | Where-Object { $_.Name -notlike '*-przed*' } | Sort-Object Name -Descending | Select-Object -Skip 14) | Remove-Item -Force -ErrorAction SilentlyContinue
        @(Get-ChildItem $BackupDir -Filter 'backup-*-przed*.zip' | Sort-Object Name -Descending | Select-Object -Skip 5) | Remove-Item -Force -ErrorAction SilentlyContinue
        return $name
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
# raz dziennie (sprawdzane co godzinę z głównej pętli)
function Update-Backup {
    if ((Get-Date) -lt $script:BackupCheckAt) { return }
    $script:BackupCheckAt = (Get-Date).AddHours(1)
    $today = 'backup-' + (Get-Date).ToString('yyyy-MM-dd')
    if (@(Get-ChildItem $BackupDir -Filter "$today*.zip" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*-przed*' }).Count) { return }
    try { $n = New-Backup; if ($n) { Log "Kopia zapasowa: $n" 'DarkGray' } } catch { Log "Kopia zapasowa nie wyszła: $($_.Exception.Message)" 'Yellow' }
}
function Get-Backups {
    return @(Get-ChildItem $BackupDir -Filter 'backup-*.zip' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {
        [pscustomobject]@{ name = $_.Name; kb = [int]($_.Length / 1024); at = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm'); before = ($_.Name -like '*-przed*') } })
}
# przywrócenie: najpierw kopia obecnego stanu, potem ustawienia, strony/uwagi, biblioteka i my-games.txt z wybranej kopii;
# wszystkie strony i OBS dostają je przez synchronizację (nowy numer zmiany)
function Restore-Backup([string]$name) {
    if ($name -notmatch '^backup-[\w-]+\.zip$') { throw 'zła nazwa kopii' }
    $zip = Join-Path $BackupDir $name; if (-not (Test-Path $zip)) { throw 'nie ma takiej kopii' }
    [void](New-Backup 'przed-przywroceniem')
    $tmp = Join-Path $env:TEMP ('vm-restore-' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    try {
        $done = New-Object Collections.ArrayList
        $sf = Join-Path $tmp 'settings.json'
        if (Test-Path $sf) {
            $j = (Get-Content $sf -Raw -Encoding UTF8) | ConvertFrom-Json
            if ($j.json) { $script:Settings = [string]$j.json; $script:SettingsRev++; $script:SettingsFrom = 'backup'
                [IO.File]::WriteAllText($SettingsFile, (@{ rev = $script:SettingsRev; json = $script:Settings } | ConvertTo-Json -Compress), $Utf8NoBom); [void]$done.Add('ustawienia') }
        }
        $kf = Join-Path $tmp 'kv.json'
        if (Test-Path $kf) {
            $kj = (Get-Content $kf -Raw -Encoding UTF8) | ConvertFrom-Json
            foreach ($pp in $kj.items.PSObject.Properties) { $script:KvRev++; $script:KV[$pp.Name] = @{ rev = $script:KvRev; from = 'backup'; val = [string]$pp.Value.val } }
            Save-Kv; [void]$done.Add('strony Kreatora i uwagi')
        }
        $lf = Join-Path $tmp 'library.json'
        if (Test-Path $lf) {
            Copy-Item -LiteralPath $lf -Destination $LibraryFile -Force
            try { $lj = (Get-Content $LibraryFile -Raw -Encoding UTF8) | ConvertFrom-Json; $script:GameLib = @{}; foreach ($pp in $lj.PSObject.Properties) { if ($pp.Value -and $pp.Value.PSObject.Properties['id']) { $script:GameLib[$pp.Name] = $pp.Value } } } catch {}
            [void]$done.Add('biblioteka gier')
        }
        $mf = Join-Path $tmp 'my-games.txt'
        if (Test-Path $mf) { Copy-Item -LiteralPath $mf -Destination $CustomFile -Force; [void]$done.Add('my-games.txt') }
        Log ("Przywrócono kopię $name" + ': ' + ($done -join ', ')) 'Cyan'
        return @($done)
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
