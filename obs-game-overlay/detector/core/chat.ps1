#Requires -Version 5.1
# GameRadar · część «chat»: zdarzenia (alerty), wykrywanie botów, sesja, wygląd czatu wybierany przez widzów, głosowanie
# Wczytywana przez detector.ps1 (dot-source) w ustalonej kolejności – korzysta z rzeczy z poprzednich części.
# Ścieżki: $Root = folder detector, $DataDir = detector\data, $AppDir = folder aplikacji (nie $PSScriptRoot – to byłby folder core).

# ---------------------------------------------------------------- zdarzenia (alerty)
$script:Events = New-Object Collections.ArrayList
$script:EventSeq = 0
# ---------------------------------------------------------------- boty: fale followów i zdrowie widowni (viewboty)
$script:Follows = New-Object Collections.ArrayList; $script:LastRaidAt = [DateTime]::MinValue; $script:WaveAt = [DateTime]::MinValue
$script:ChatTimes = New-Object Collections.ArrayList; $script:Audience = $null
function Watch-BotSignals($ev) {
    $now = Get-Date
    if ($ev.type -eq 'raid') { $script:LastRaidAt = $now }
    if ($ev.type -eq 'chat' -and -not $ev.command -and -not $ev.test) { [void]$script:ChatTimes.Add([pscustomobject]@{ login = [string]$ev.login; at = $now }) }
    while ($script:ChatTimes.Count -and ($now - $script:ChatTimes[0].at).TotalMinutes -gt 15) { $script:ChatTimes.RemoveAt(0) }
    if ($ev.type -ne 'follow' -or $ev.test) { return }
    [void]$script:Follows.Add([pscustomobject]@{ login = [string]$ev.login; user = [string]$ev.user; at = $now })
    while ($script:Follows.Count -and ($now - $script:Follows[0].at).TotalSeconds -gt 90) { $script:Follows.RemoveAt(0) }
    # fala: 8+ followów w 90 s, bez raidu w ostatnich 3 minutach, najwyżej raz na 5 minut
    if ($script:Follows.Count -ge 8 -and ($now - $script:LastRaidAt).TotalMinutes -gt 3 -and ($now - $script:WaveAt).TotalMinutes -gt 5) {
        $script:WaveAt = $now
        $logins = @($script:Follows | ForEach-Object { $_.login } | Where-Object { $_ } | Select-Object -Unique)
        $odd = @($logins | Where-Object { Test-BotName $_ }).Count; $fresh = 0; $noAv = 0
        try {
            if ($logins.Count -and $script:TW.status -eq 'online') {
                $u = Invoke-Helix 'GET' ('users?' + (($logins | Select-Object -First 100 | ForEach-Object { 'login=' + [Uri]::EscapeDataString($_) }) -join '&')) $null
                foreach ($d in @($u.data)) {
                    if (((Get-Date).ToUniversalTime() - [datetime]::Parse([string]$d.created_at).ToUniversalTime()).TotalDays -lt 7) { $fresh++ }
                    if ([string]$d.profile_image_url -match 'user-default-pictures') { $noAv++ }
                }
            }
        } catch {}
        $wave = [pscustomobject]@{ type = 'botwave'; count = $script:Follows.Count; odd = $odd; fresh = $fresh; noAvatar = $noAv; users = @($script:Follows | ForEach-Object { $_.user }) }
        Log ("Boty? Fala followów: {0} w 90 s bez raidu (nicki z generatora: {1}, nowe konta: {2}, bez awatara: {3})" -f $wave.count, $odd, $fresh, $noAv) 'Yellow'
        $script:LastWave = $wave
        Add-Event $wave
    }
}
# zdrowie widowni: stosunek widzów do piszących, płaski wykres, skoki bez raidu
function Get-Audience {
    $c = $script:Cur; $now = Get-Date
    $chatters = @($script:ChatTimes | ForEach-Object { $_.login } | Select-Object -Unique).Count
    $v = [int]$script:Channel.viewers
    $flags = New-Object Collections.ArrayList
    $ratio = if ($chatters) { [Math]::Round($v / $chatters, 1) } else { $null }
    if ($script:Channel.live -and $v -ge 30) {
        if (-not $chatters) { [void]$flags.Add("$v widzów i nikt nie pisze od 15 minut") }
        elseif ($ratio -gt 40) { [void]$flags.Add("$ratio widzów na jednego piszącego (zwykle 6–20)") }
    }
    $vs = if ($c) { @($c.viewers | Select-Object -Last 12 | ForEach-Object { [int]$_.v }) } else { @() }
    if ($vs.Count -ge 10 -and ($vs | Measure-Object -Minimum).Minimum -ge 30) {
        $mn = ($vs | Measure-Object -Minimum).Minimum; $mx = ($vs | Measure-Object -Maximum).Maximum
        if (($mx - $mn) -le [Math]::Max(1, $mx * 0.01)) { [void]$flags.Add("płaski wykres: $mn–$mx widzów przez 10+ minut") }
    }
    if ($vs.Count -ge 2) {
        $a = $vs[$vs.Count - 2]; $b = $vs[$vs.Count - 1]
        if ($b - $a -ge 30 -and $b -gt $a * 1.6 -and ($now - $script:LastRaidAt).TotalMinutes -gt 3) { [void]$flags.Add("skok z $a do $b widzów bez raidu") }
    }
    $w = $script:LastWave
    return [pscustomobject]@{ live = [bool]$script:Channel.live; viewers = $v; chatters15 = $chatters; ratio = $ratio; flags = @($flags)
        wave = $(if ($w -and ($now - $script:WaveAt).TotalMinutes -lt 30) { $w } else { $null }) }
}

function Add-Event($ev) {
    if (-not $ev.replay) { try { Watch-BotSignals $ev } catch {} }
    $script:EventSeq++
    $ev | Add-Member -NotePropertyName id -NotePropertyValue $script:EventSeq -Force
    $ev | Add-Member -NotePropertyName at -NotePropertyValue ([DateTimeOffset]::Now.ToUnixTimeMilliseconds()) -Force
    [void]$script:Events.Add($ev)
    while ($script:Events.Count -gt 400) { $script:Events.RemoveAt(0) }
    Add-SessionEvent $ev
    try { Write-ArchiveEvent $ev } catch { Log "Archiwum: $($_.Exception.Message)" 'DarkYellow' }
    $who = ''; if ($ev.user) { $who = $ev.user }
    if ($ev.type -ne 'chat') { Log ("Alert: {0} {1}" -f $ev.type, $who) 'Magenta' }
}

# ---------------------------------------------------------------- sesja (do napisów końcowych)
$script:Session = @{ chatters = [ordered]@{}; follow = [ordered]@{}; sub = [ordered]@{}; gift = [ordered]@{}; cheer = [ordered]@{}; raid = [ordered]@{}; redeem = [ordered]@{}; started = (Get-Date) }
function Add-SessionEvent($ev) {
    if ($ev.test -or $ev.replay -or -not $ev.user) { return }
    $u = [string]$ev.user
    switch ($ev.type) {
        'chat'   { $script:Session.chatters[$u] = 1 + [int]$script:Session.chatters[$u] }
        'follow' { $script:Session.follow[$u] = 1 }
        'sub'    { $script:Session.sub[$u] = 1 }
        'resub'  { $script:Session.sub[$u] = [int]$ev.months }
        'gift'   { $script:Session.gift[$u] = [int]$script:Session.gift[$u] + [int]$ev.count }
        'cheer'  { $script:Session.cheer[$u] = [int]$script:Session.cheer[$u] + [int]$ev.amount }
        'raid'   { $script:Session.raid[$u] = [int]$ev.viewers }
        'redeem' { $script:Session.redeem[$u] = 1 + [int]$script:Session.redeem[$u] }
    }
}
function Get-Session {
    $o = [ordered]@{ started = $script:Session.started.ToString('o') }
    foreach ($k in @('chatters', 'follow', 'sub', 'gift', 'cheer', 'raid', 'redeem')) {
        $o[$k] = @($script:Session[$k].GetEnumerator() | ForEach-Object { [pscustomobject]@{ user = $_.Key; n = $_.Value } })
    }
    return [pscustomobject]$o
}

# ---------------------------------------------------------------- czat: wygląd wybrany przez widzów i efekty
$ViewersFile = Join-Path $DataDir 'viewers.json'
$script:Viewers = @{}
if (Test-Path $ViewersFile) {
    try { $vj = (Get-Content $ViewersFile -Raw -Encoding UTF8) | ConvertFrom-Json; foreach ($pp in $vj.PSObject.Properties) { $script:Viewers[$pp.Name] = $pp.Value } } catch {}
}
$ChatStyles = @('neon', 'szklo', 'pixel', 'komiks', 'terminal', 'papier', 'holo', 'sakura', 'ogien', 'lod')
$ChatColors = @{ czerwony = '#ff4d5e'; pomaranczowy = '#ff9f43'; zolty = '#ffd43b'; zielony = '#4cd97b'; turkus = '#2ee6d6'; niebieski = '#4c9dff'; fiolet = '#a77bff'; rozowy = '#ff6fb5'; bialy = '#f4f4f8'; zloty = '#e8b84a' }
$ChatEffects = @('konfetti', 'serca', 'gwiazdy', 'fajerwerki', 'iskry', 'babelki')
$script:EffectCooldown = @{}; $script:EffectGlobal = [DateTime]::MinValue

function Remove-Diacritics([string]$t) {
    $n = $t.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($c in $n.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne 'NonSpacingMark') { [void]$sb.Append($c) } }
    return $sb.ToString().Replace('ł', 'l')
}
function Save-Viewers {
    [IO.File]::WriteAllText($ViewersFile, ([pscustomobject]$script:Viewers | ConvertTo-Json -Depth 4 -Compress), $Utf8NoBom)
}
# zwraca $true, jeśli wiadomość była komendą (wtedy pokazujemy potwierdzenie zamiast treści)
function Invoke-ChatCommand($login, $user, [string]$text) {
    $t = $text.Trim()
    if (-not $t.StartsWith('!')) { return $null }
    $parts = $t.Substring(1).Split(' ', 2, [StringSplitOptions]::RemoveEmptyEntries)
    if (-not $parts.Length) { return $null }
    $cmd = Remove-Diacritics $parts[0]
    $arg = if ($parts.Length -gt 1) { Remove-Diacritics $parts[1].Trim() } else { '' }
    $v = $script:Viewers[$login]; if (-not $v) { $v = [pscustomobject]@{ style = ''; color = '' } }
    switch ($cmd) {
        { $_ -in @('styl', 'style') } {
            if ($arg -eq 'szklo' -or $arg -eq 'glass') { $arg = 'szklo' }
            if ($ChatStyles -notcontains $arg) { return "style: $($ChatStyles -join ', ')" }
            $v.style = $arg; $script:Viewers[$login] = $v; Save-Viewers; return "styl: $arg ✓"
        }
        { $_ -in @('kolor', 'color') } {
            $hex = $null
            if ($arg -match '^#?[0-9a-f]{6}$') { $hex = '#' + $arg.TrimStart('#') } elseif ($ChatColors.ContainsKey($arg)) { $hex = $ChatColors[$arg] }
            if (-not $hex) { return "kolory: $(($ChatColors.Keys | Sort-Object) -join ', ') albo #rrggbb" }
            $v.color = $hex; $script:Viewers[$login] = $v; Save-Viewers; return "kolor: $arg ✓"
        }
        { $_ -in @('efekt', 'effect') } {
            if ($ChatEffects -notcontains $arg) { return "efekty: $($ChatEffects -join ', ')" }
            $now = Get-Date
            $last = $script:EffectCooldown[$login]
            if ($last -and ($now - $last).TotalSeconds -lt 60) { return "efekt za $([int](60 - ($now - $last).TotalSeconds)) s" }
            if (($now - $script:EffectGlobal).TotalSeconds -lt 15) { return 'chwila – efekt właśnie leci' }
            $script:EffectCooldown[$login] = $now; $script:EffectGlobal = $now
            Add-Event ([pscustomobject]@{ type = 'effect'; effect = $arg; user = $user })
            return "efekt: $arg ✓"
        }
        { $_ -in @('reset') } { $script:Viewers.Remove($login); Save-Viewers; return 'wygląd: domyślny ✓' }
    }
    return $null
}
# ---------------------------------------------------------------- głosowanie na czacie: postać kontra gra (scena «VM · Głosowanie»)
# Widzowie piszą 1 / 2 (albo nazwę). Jeden głos na osobę – można zmienić zdanie. Koniec: czas minął albo
# po minucie wszystkie głosy (min. 5) są po jednej stronie.
$script:Vote = [pscustomobject]@{ active = $false; a = ''; b = ''; votes = @{}; started = [DateTime]::MinValue; ends = [DateTime]::MinValue; winner = ''; id = 0 }
function Get-VoteStatus {
    $v = $script:Vote; $va = @($v.votes.Values | Where-Object { $_ -eq 'a' }).Count; $vb = @($v.votes.Values | Where-Object { $_ -eq 'b' }).Count
    if ($v.active) {
        $done = (Get-Date) -ge $v.ends
        if (-not $done -and ($va + $vb) -ge 5 -and ($va -eq 0 -or $vb -eq 0) -and ((Get-Date) - $v.started).TotalSeconds -ge 60) { $done = $true }
        if ($done) {
            $v.active = $false; $v.winner = if ($va -gt $vb) { 'a' } elseif ($vb -gt $va) { 'b' } else { 'a' }   # remis – zostaje postać
            Log "Głosowanie: wygrywa $(if ($v.winner -eq 'a') { $v.a } else { $v.b }) ($va : $vb)" 'Cyan'
            Add-Event ([pscustomobject]@{ type = 'vote'; state = 'end'; winner = $v.winner; a = $v.a; b = $v.b; va = $va; vb = $vb })
        }
    }
    return [pscustomobject]@{ id = $v.id; active = $v.active; a = $v.a; b = $v.b; va = $va; vb = $vb; winner = $v.winner
        endsIn = [int][Math]::Min([double]86400, [Math]::Max([double]0, ($v.ends - (Get-Date)).TotalSeconds)) }
}
function Add-Vote([string]$login, [string]$text) {
    $v = $script:Vote; if (-not $v.active) { return }
    $t = (Remove-Diacritics $text).ToLowerInvariant().Trim()
    $na = (Remove-Diacritics $v.a).ToLowerInvariant(); $nb = (Remove-Diacritics $v.b).ToLowerInvariant()
    $pick = ''
    if ($t -match '^\W*!?(vote\s*)?(1|a)\W*$' -or ($na -and $t -eq $na) -or $t -match '^!?(postac|persona)\W*$') { $pick = 'a' }
    elseif ($t -match '^\W*!?(vote\s*)?(2|b)\W*$' -or ($nb -and $t -eq $nb) -or $t -match '^!?(gra|program|game)\W*$') { $pick = 'b' }
    if ($pick) { $v.votes[$login] = $pick }
}

function New-ChatEvent($login, $user, [string]$color, [string]$text, $fragments, $badges, [bool]$test = $false, [string]$userId = '', [double]$fakeAge = -2) {
    try { Add-Vote $login $text } catch {}
    # pilot przez czat Twitcha: «!vm przerwa», «!vm scena Moja scena», «!vm gra Townscaper» – tylko z konta streamera
    # (działa z aplikacji Twitch na telefonie przez internet, bez Wi-Fi i bez otwierania portów); panel w OBS wykonuje polecenie
    if ($text -match '^\s*!vm\s+(.+)$' -and (@($badges) -contains 'broadcaster')) {
        $c = $Matches[1].Trim()
        Add-Event ([pscustomobject]@{ type = 'control'; cmd = $c; user = $user })
        Log "Pilot z czatu: $c" 'Cyan'
        return [pscustomobject]@{ type = 'chat'; user = $user; login = $login; text = $text; fragments = @(); badges = @($badges); color = ''; style = ''; command = $true; reply = ''; test = $test; flag = $null; hidden = $true }
    }
    $reply = Invoke-ChatCommand $login $user $text
    $v = $script:Viewers[$login]
    # flaga: nowe konto, link, tekst bota, «fajnie grasz» gdy nikt nie gra (panel → Czat i statystyki)
    $flag = $null
    if (-not $reply) {
        $rec = if ($test) { [pscustomobject]@{ login = $login; msgs = 0; trust = $false; created = '' } } else { Get-ChatterRecord $login $user }
        try { $flag = Get-ChatFlag $rec $text $badges $userId $fakeAge } catch {}
    }
    return [pscustomobject]@{
        bot = [bool]($KnownGoodBots -contains ([string]$login).ToLowerInvariant())
        type = 'chat'; user = $user; login = $login; text = $text; fragments = @($fragments); badges = @($badges)
        color = $(if ($v -and $v.color) { $v.color } elseif ($color) { $color } else { '' })
        style = $(if ($v -and $v.style) { $v.style } else { '' })
        command = [bool]$reply; reply = $(if ($reply) { [string]$reply } else { '' }); test = $test; flag = $flag
    }
}
