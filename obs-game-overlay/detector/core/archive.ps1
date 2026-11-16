#Requires -Version 5.1
# GameRadar · część «archive»: archiwum streamów, czat i statystyki
# Wczytywana przez detector.ps1 (dot-source) w ustalonej kolejności – korzysta z rzeczy z poprzednich części.
# Ścieżki: $Root = folder detector, $DataDir = detector\data, $AppDir = folder aplikacji (nie $PSScriptRoot – to byłby folder core).

# ---------------------------------------------------------------- archiwum: zapis czatu i zdarzeń, statystyki, flagowanie botów
# data\archive\chatters.json            – każdy czatownik: pierwsza/ostatnia wizyta, liczba wiadomości, wiek konta, zaufany
# data\archive\streams\<id>.jsonl       – wszystko z jednego streama (czat + alerty), linia = jedno zdarzenie
# data\archive\streams\<id>.json        – podsumowanie (zapisywane co 2 min i na końcu streama)
# Stream = od stream.online do stream.offline z Twitcha; czat poza streamem trafia do «poza-streamem-<data>».
$ArchiveDir = Join-Path $DataDir 'archive'
$StreamsDir = Join-Path $ArchiveDir 'streams'
$ChattersFile = Join-Path $ArchiveDir 'chatters.json'
New-Item -ItemType Directory -Force -Path $StreamsDir | Out-Null
$script:Chatters = @{}
if (Test-Path $ChattersFile) {
    try { $cj = (Get-Content $ChattersFile -Raw -Encoding UTF8) | ConvertFrom-Json; foreach ($pp in $cj.PSObject.Properties) { $script:Chatters[$pp.Name] = $pp.Value } } catch {}
}
$script:ChattersDirty = $false; $script:ChattersSaved = Get-Date
$script:Channel = [pscustomobject]@{ live = $false; category = ''; title = ''; viewers = 0; startedAt = $null; nextPoll = [DateTime]::MinValue }
$script:Cur = $null
$script:RecentTexts = New-Object Collections.ArrayList
$NonGameCategories = @('art', 'software and game development', 'makers & crafting', 'just chatting', 'music', 'science & technology', 'talk shows & podcasts', 'food & drink', 'special events', 'travel & outdoors', 'fitness & health', 'beauty & body art', 'animals, aquariums, and zoos', 'asmr', 'pools, hot tubs, and beaches')

function New-StreamStats([string]$id, [datetime]$start, [bool]$live) {
    return [pscustomobject]@{
        id = $id; live = $live; start = $start.ToString('o'); end = ''; title = $script:Channel.title; category = $script:Channel.category
        games = @{}; msgs = 0; chatters = @{}; newChatters = 0; follows = 0; subs = 0; gifts = 0; bits = 0; raids = 0; raidViewers = 0; redeems = 0
        viewers = New-Object Collections.ArrayList; peak = 0; flagged = @{}; perSlot = @{}; saved = [DateTime]::MinValue
    }
}
function Get-StreamId([datetime]$start, [bool]$live) {
    if ($live) { return $start.ToString('yyyy-MM-dd_HHmm') }
    return 'poza-streamem-' + (Get-Date).ToString('yyyy-MM-dd')
}
function Open-StreamArchive([bool]$live, $start = $null) {
    if (-not $start) { $start = Get-Date }
    $id = Get-StreamId $start $live
    if ($script:Cur -and $script:Cur.id -eq $id) { return }
    if ($script:Cur) { Close-StreamArchive }
    $script:Cur = New-StreamStats $id $start $live
    # restart wykrywacza w trakcie streama: dopisz do istniejącego podsumowania
    $f = Join-Path $StreamsDir "$id.json"
    if (Test-Path $f) {
        try {
            $o = (Get-Content $f -Raw -Encoding UTF8) | ConvertFrom-Json
            foreach ($k in @('msgs', 'newChatters', 'follows', 'subs', 'gifts', 'bits', 'raids', 'raidViewers', 'redeems', 'peak')) { $script:Cur.$k = [int]$o.$k }
            foreach ($c in @($o.top)) { if ($c.login) { $script:Cur.chatters[[string]$c.login] = [int]$c.n } }
            foreach ($g in @($o.games)) { if ($g) { $script:Cur.games[[string]$g] = 1 } }
            foreach ($v in @($o.viewers)) { [void]$script:Cur.viewers.Add($v) }
            foreach ($fl in @($o.flagged)) { if ($fl.login) { $script:Cur.flagged[[string]$fl.login] = $fl } }
        } catch {}
    }
    if ($live) { Log "Archiwum: stream $id" 'DarkCyan' }
}
function Close-StreamArchive {
    if (-not $script:Cur) { return }
    $script:Cur.end = (Get-Date).ToString('o')
    Save-StreamSummary
    if ($script:Cur.live) { Log "Archiwum: koniec streama $($script:Cur.id) – wiadomości: $($script:Cur.msgs), czatowników: $($script:Cur.chatters.Count)" 'DarkCyan' }
    $script:Cur = $null
}
function Get-StreamSummary($c) {
    if (-not $c) { return $null }
    $top = @($c.chatters.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 30 | ForEach-Object {
            $rec = $script:Chatters[$_.Key]; [pscustomobject]@{ login = $_.Key; name = $(if ($rec) { [string]$rec.name } else { $_.Key }); n = $_.Value } })
    $vs = @($c.viewers | ForEach-Object { [int]$_.v })
    $avg = 0; if ($vs.Count) { $avg = [int](($vs | Measure-Object -Average).Average) }
    $slots = @($c.perSlot.GetEnumerator() | Sort-Object Name | ForEach-Object { [pscustomobject]@{ t = $_.Name; n = $_.Value } })
    $dur = 0; try { $endT = if ($c.end) { [datetime]::Parse($c.end) } else { Get-Date }; $dur = [int]($endT - [datetime]::Parse($c.start)).TotalMinutes } catch {}
    return [pscustomobject]@{
        id = $c.id; live = $c.live; start = $c.start; end = $c.end; minutes = $dur; title = $c.title; category = $c.category; games = @($c.games.Keys)
        msgs = $c.msgs; chatters = $c.chatters.Count; newChatters = $c.newChatters; follows = $c.follows; subs = $c.subs; gifts = $c.gifts
        bits = $c.bits; raids = $c.raids; raidViewers = $c.raidViewers; redeems = $c.redeems; peak = $c.peak; avgViewers = $avg
        viewers = @($c.viewers); top = $top; flagged = @($c.flagged.Values); perSlot = $slots
    }
}
function Save-StreamSummary {
    $c = $script:Cur; if (-not $c) { return }
    $c.saved = Get-Date
    try { [IO.File]::WriteAllText((Join-Path $StreamsDir "$($c.id).json"), ((Get-StreamSummary $c) | ConvertTo-Json -Depth 6 -Compress), $Utf8NoBom) } catch {}
}
function Save-Chatters([switch]$Force) {
    if (-not $script:ChattersDirty) { return }
    if (-not $Force -and ((Get-Date) - $script:ChattersSaved).TotalSeconds -lt 60) { return }
    $script:ChattersDirty = $false; $script:ChattersSaved = Get-Date
    try { [IO.File]::WriteAllText($ChattersFile, ([pscustomobject]$script:Chatters | ConvertTo-Json -Depth 5 -Compress), $Utf8NoBom) } catch {}
}

# wiek konta z Twitcha (raz na czatownika, zapamiętany)
function Get-AccountAgeDays($rec, [string]$userId) {
    if (-not $rec.created -and $userId -and $script:TW.token -and $script:TW.status -eq 'online') {
        try {
            $u = Invoke-Helix 'GET' "users?id=$userId" $null
            if ($u.data.Count) {
                $d = $u.data[0]; $rec.created = [string]$d.created_at
                # profil: domyślny awatar, puste bio (typowe dla kont-botów)
                $rec | Add-Member -NotePropertyName noAvatar -NotePropertyValue ([string]$d.profile_image_url -match 'user-default-pictures') -Force
                $rec | Add-Member -NotePropertyName noBio -NotePropertyValue (-not ([string]$d.description).Trim()) -Force
                $script:ChattersDirty = $true
            }
        } catch {}
    }
    if (-not $rec.created) { return -1 }
    try { return [Math]::Max([double]0, ((Get-Date).ToUniversalTime() - [datetime]::Parse($rec.created).ToUniversalTime()).TotalDays) } catch { return -1 }
}

# ocena wiadomości: świeże konto, link w pierwszej wiadomości, typowe teksty botów i «fajnie grasz», gdy nikt nie gra
# legalne boty kanału (moderacja, komendy) – nigdy nie są oznaczane jako podejrzane
$KnownGoodBots = @('nightbot', 'streamelements', 'streamlabs', 'fossabot', 'moobot', 'wizebot', 'sery_bot', 'soundalerts', 'botrixoficial', 'commanderroot', 'pretzelrocks', 'kofistreambot', 'blerp', 'streamstickers', 'tangiabot', 'own3d', 'creatisbot', 'frostytoolsdotcom', 'lumiastream', 'restreambot', 'botisimo', 'deepbot', 'phantombot', 'coebot', 'ankhbot', 'vivbot', 'super_timer_bot')
# nick jak z generatora: losowe litery i cyfry, schemat słowo_12345, mało samogłosek
function Test-BotName([string]$login) {
    $l = $login.ToLowerInvariant()
    if ($l -match '^[a-z]+_?\d{4,}$' -or $l -match '\d{6,}') { return $true }
    $letters = ($l -replace '[^a-z]', ''); $digits = ($l -replace '[^0-9]', '').Length
    if ($l.Length -ge 10 -and $digits -ge 3 -and $letters.Length -ge 5 -and ($letters -replace '[^aeiouy]', '').Length / [double]$letters.Length -lt 0.2) { return $true }
    if ($letters.Length -ge 8 -and $letters -match '[bcdfghjklmnpqrstvwxz]{6,}') { return $true }
    return $false
}
function Get-ChatFlag($rec, [string]$text, $badges, [string]$userId, [double]$fakeAge = -2) {
    if ($rec.trust -or ($KnownGoodBots -contains ([string]$rec.login).ToLowerInvariant())) { return $null }
    foreach ($b in @($badges)) { if (@('broadcaster', 'moderator', 'vip', 'subscriber', 'founder') -contains [string]$b) { return $null } }
    $t = Remove-Diacritics $text
    $first = [int]$rec.msgs -lt 1
    $early = [int]$rec.msgs -lt 3
    $score = 0; $why = New-Object Collections.ArrayList
    $age = if ($fakeAge -gt -2) { $fakeAge } elseif ($early) { Get-AccountAgeDays $rec $userId } else { -1 }
    if ($age -ge 0) {
        if ($age -lt 2) { $score += 3; [void]$why.Add(('konto ma {0} h' -f [int]($age * 24))) }
        elseif ($age -lt 14) { $score += 2; [void]$why.Add(('konto ma {0} dni' -f [int]$age)) }
        elseif ($age -lt 60 -and $first) { $score += 1; [void]$why.Add(('konto ma {0} dni' -f [int]$age)) }
    }
    if ($early) {
        if (Test-BotName ([string]$rec.login)) { $score += 1; [void]$why.Add('nick jak z generatora') }
        if ($rec.noAvatar -and $rec.noBio) { $score += 1; [void]$why.Add('domyślny awatar i puste bio') }
    }
    # ta sama osoba powtarza ten sam szablon (bez względu na to, co się dzieje na streamie)
    $own = ($t -replace '\W+', ' ').Trim().ToLowerInvariant()
    if ($own.Length -ge 6) {
        if (-not $script:UserTexts) { $script:UserTexts = @{} }
        $hist = @($script:UserTexts[$rec.login]) | Where-Object { $_ -and ((Get-Date) - $_.at).TotalMinutes -lt 10 }
        $rep = @($hist | Where-Object { $_.text -eq $own }).Count
        $script:UserTexts[$rec.login] = @($hist) + [pscustomobject]@{ text = $own; at = Get-Date } | Select-Object -Last 8
        if ($rep -ge 2) { $score += 2; [void]$why.Add('powtarza ten sam tekst') }
    }
    $hasLink = $t -match '(https?://|www\.|\b[a-z0-9-]+\s?\.\s?(com|net|org|ru|xyz|io|gg|ly|shop|site|online|top)\b|discord\.gg)'
    if ($hasLink) { if ($early) { $score += 3; [void]$why.Add('link na początku znajomości') } else { $score += 1; [void]$why.Add('link') } }
    if ($t -match '(viewers|followers|follows|promot|cheap|best .{0,12}(viewers|followers)|streamboo|dogehype|bigfollows|grow your (channel|stream)|kup (widzow|followow)|rozkrec\w* kanal|remove the space|only ?fans|crypto|nft|forex)') {
        $score += 4; [void]$why.Add('tekst jak z reklamy widzów/followów')
    }
    if ($first -and $t -match '^\W*(hi|hello|hey|yo|siema|czesc|hej|witam)?\W*(streamer|bro|friend)?\W*(fajnie|super|swietnie|dobrze|niezle|ladnie|nice|great|good|cool|awesome|amazing|love)\W+(grasz|gra|stream\w*|content|gameplay|game|play\w*|channel|kanal|vibe|video)\b') {
        $score += 2; [void]$why.Add('ogólnikowe «fajny stream» na dzień dobry')
    }
    # pisze o graniu, a nikt nie gra (np. Blender, rozmowa)
    $gaming = [bool]$script:State.game -and $script:State.game.kind -ne 'make'
    $cat = ([string]$script:Channel.category).ToLowerInvariant()
    if (-not $gaming -and $cat -and $NonGameCategories -contains $cat -and $t -match '\b(grasz|grac|gra\b|gierk|gameplay|game|play(ing)?|gg|level|boss)') {
        $score += 3; [void]$why.Add("pisze o graniu, a kategoria to «$($script:Channel.category)»")
    } elseif (-not $gaming -and -not $cat -and $first -and $t -match '\b(grasz|gameplay|playing)\b') {
        $score += 2; [void]$why.Add('pisze o graniu, a nic nie jest uruchomione')
    }
    if ($first -and $text -match '\p{IsCyrillic}|\p{IsArabic}|\p{IsDevanagari}|\p{IsThai}' -and $text -notmatch '[a-zA-Z]{3}') { $score += 1; [void]$why.Add('inny alfabet') }
    # ten sam tekst od kilku osób w ciągu minuty
    $norm = ($t -replace '\W+', ' ').Trim()
    if ($norm.Length -ge 12) {
        $now = Get-Date
        while ($script:RecentTexts.Count -and ($now - $script:RecentTexts[0].at).TotalSeconds -gt 60) { $script:RecentTexts.RemoveAt(0) }
        $same = @($script:RecentTexts | Where-Object { $_.text -eq $norm -and $_.login -ne $rec.login }).Count
        [void]$script:RecentTexts.Add([pscustomobject]@{ text = $norm; login = $rec.login; at = $now })
        if ($same -ge 1) { $score += 2; [void]$why.Add('ten sam tekst od kilku kont') }
    }
    if ($score -lt 2) { return $null }
    return [pscustomobject]@{ level = $(if ($score -ge 4) { 'suspect' } else { 'watch' }); score = $score; reasons = @($why); ageDays = $(if ($age -ge 0) { [Math]::Round($age, 1) } else { $null }); first = $first }
}

function Get-ChatterRecord([string]$login, [string]$name) {
    $rec = $script:Chatters[$login]
    if (-not $rec) {
        $rec = [pscustomobject]@{ login = $login; name = $name; first = (Get-Date).ToString('o'); last = ''; msgs = 0; streams = 0; lastStream = ''; created = ''; trust = $false; flags = 0 }
        $script:Chatters[$login] = $rec; $script:ChattersDirty = $true
    }
    return $rec
}

# wywoływane dla każdego zdarzenia (Add-Event)
function Write-ArchiveEvent($ev) {
    if ($ev.test -or $ev.replay -or @('transition', 'effect') -contains [string]$ev.type) { return }
    if (-not $script:Cur) { Open-StreamArchive $false }
    $c = $script:Cur
    $u = [string]$ev.user
    switch ([string]$ev.type) {
        'chat' {
            if ($ev.command) { break }
            $c.msgs++
            $login = [string]$ev.login; if (-not $login) { $login = $u.ToLowerInvariant() }
            $c.chatters[$login] = 1 + [int]$c.chatters[$login]
            $rec = Get-ChatterRecord $login $u
            if ($rec.lastStream -ne $c.id) { $rec.streams = [int]$rec.streams + 1; $rec.lastStream = $c.id; if ([int]$rec.streams -eq 1) { $c.newChatters++ } }
            $rec.msgs = [int]$rec.msgs + 1; $rec.last = (Get-Date).ToString('o'); $rec.name = $u; $script:ChattersDirty = $true
            if ($ev.flag) {
                $rec.flags = [int]$rec.flags + 1
                $c.flagged[$login] = [pscustomobject]@{ login = $login; name = $u; level = $ev.flag.level; reasons = @($ev.flag.reasons); text = [string]$ev.text; at = (Get-Date).ToString('o') }
            }
        }
        'follow' { $c.follows++ }
        'sub' { $c.subs++ }
        'resub' { $c.subs++ }
        'gift' { $c.gifts += [int]$ev.count }
        'cheer' { $c.bits += [int]$ev.amount }
        'raid' { $c.raids++; $c.raidViewers += [int]$ev.viewers }
        'redeem' { $c.redeems++ }
    }
    $slot = (Get-Date).ToString('HH:') + ('{0:00}' -f ([Math]::Floor((Get-Date).Minute / 5) * 5))
    $c.perSlot[$slot] = 1 + [int]$c.perSlot[$slot]
    if ($script:State.game -and $script:State.game.name) { $c.games[[string]$script:State.game.name] = 1 }
    try {
        $line = [ordered]@{ t = [DateTimeOffset]::Now.ToUnixTimeMilliseconds() }
        foreach ($p in $ev.PSObject.Properties) { if (@('id', 'at', 'fragments', 'reply', 'test', 'style', 'color') -notcontains $p.Name) { $line[$p.Name] = $p.Value } }
        [IO.File]::AppendAllText((Join-Path $StreamsDir "$($c.id).jsonl"), (([pscustomobject]$line) | ConvertTo-Json -Depth 5 -Compress) + "`n", $Utf8NoBom)
    } catch {}
}

# co minutę: czy stream trwa, ilu widzów, jaka kategoria; zapis podsumowania i bazy czatowników
function Update-Archive {
    Save-Chatters
    if ($script:Cur -and ((Get-Date) - $script:Cur.saved).TotalSeconds -gt 120) { Save-StreamSummary }
    if ($script:TW.status -ne 'online' -or (Get-Date) -lt $script:Channel.nextPoll) { return }
    $script:Channel.nextPoll = (Get-Date).AddSeconds(60)
    try {
        $r = Invoke-Helix 'GET' "streams?user_id=$($script:TW.userId)" $null
        if ($r.data.Count) {
            $st = $r.data[0]
            $script:Channel.live = $true; $script:Channel.viewers = [int]$st.viewer_count
            $script:Channel.category = [string]$st.game_name; $script:Channel.title = [string]$st.title
            $start = [datetime]::Parse([string]$st.started_at).ToLocalTime()
            Open-StreamArchive $true $start
            $c = $script:Cur
            $c.title = $script:Channel.title; $c.category = $script:Channel.category
            [void]$c.viewers.Add([pscustomobject]@{ t = (Get-Date).ToString('HH:mm'); v = $script:Channel.viewers })
            if ($script:Channel.viewers -gt $c.peak) { $c.peak = $script:Channel.viewers }
        } else {
            if ($script:Cur -and $script:Cur.live) { Close-StreamArchive }
            $script:Channel.live = $false; $script:Channel.viewers = 0
            $ch = Invoke-Helix 'GET' "channels?broadcaster_id=$($script:TW.userId)" $null
            if ($ch.data.Count) { $script:Channel.category = [string]$ch.data[0].game_name; $script:Channel.title = [string]$ch.data[0].title }
            $script:Channel.nextPoll = (Get-Date).AddSeconds(180)
        }
    } catch {}
}

function Get-ArchiveList {
    $list = @(Get-ChildItem -Path $StreamsDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 60 | ForEach-Object {
            try { $o = (Get-Content $_.FullName -Raw -Encoding UTF8) | ConvertFrom-Json; $o.PSObject.Properties.Remove('viewers'); $o.PSObject.Properties.Remove('top'); $o.PSObject.Properties.Remove('perSlot'); $o } catch { $null }
        } | Where-Object { $_ })
    $cur = $null; if ($script:Cur) { $cur = Get-StreamSummary $script:Cur }
    $flaggedNow = @()
    foreach ($rec in $script:Chatters.Values) { if ([int]$rec.flags -gt 0 -and -not $rec.trust) { $flaggedNow += $rec } }
    $totals = [pscustomobject]@{ chatters = $script:Chatters.Count; returning = @($script:Chatters.Values | Where-Object { [int]$_.streams -ge 2 }).Count; flagged = $flaggedNow.Count }
    return [pscustomobject]@{ current = $cur; streams = $list; totals = $totals; channel = $script:Channel }
}

# eksport czatu: txt (czas od początku), srt (napisy do nagrania), json
function Export-Stream([string]$id, [string]$fmt, [int]$offsetSec = 0) {
    $f = Join-Path $StreamsDir "$id.jsonl"
    if (-not (Test-Path $f)) { return $null }
    $sumF = Join-Path $StreamsDir "$id.json"
    $start = $null
    if (Test-Path $sumF) { try { $start = [DateTimeOffset]::Parse([string]((Get-Content $sumF -Raw -Encoding UTF8) | ConvertFrom-Json).start).ToUnixTimeMilliseconds() } catch {} }
    $lines = [IO.File]::ReadAllLines($f, [Text.Encoding]::UTF8)
    if ($fmt -eq 'json') { return '[' + ($lines -join ',') + ']' }
    $sb = New-Object Text.StringBuilder
    $n = 0
    foreach ($l in $lines) {
        try { $e = $l | ConvertFrom-Json } catch { continue }
        if (-not $start) { $start = [long]$e.t }
        $ms = [long]$e.t - $start + $offsetSec * 1000
        if ($ms -lt 0) { continue }
        $ts = [TimeSpan]::FromMilliseconds($ms)
        $who = [string]$e.user
        $what = switch ([string]$e.type) {
            'chat' { [string]$e.text } 'follow' { '★ obserwuje' } 'sub' { '★ sub' } 'resub' { "★ resub ($($e.months) mies.)" }
            'gift' { "★ gift ×$($e.count)" } 'cheer' { "★ $($e.amount) bitsów" } 'raid' { "★ raid ($($e.viewers) os.)" } 'redeem' { "★ nagroda: $($e.reward)" }
            default { [string]$e.type }
        }
        $flag = ''; if ($e.flag) { $flag = ' [' + $(if ($e.flag.level -eq 'suspect') { 'PODEJRZANE' } else { 'do sprawdzenia' }) + ']' }
        if ($fmt -eq 'srt') {
            $n++
            $end = $ts.Add([TimeSpan]::FromSeconds(4))
            [void]$sb.AppendLine($n).AppendLine(('{0:hh\:mm\:ss\,fff} --> {1:hh\:mm\:ss\,fff}' -f $ts, $end)).AppendLine("${who}: $what").AppendLine()
        } else {
            [void]$sb.AppendLine(('[{0:hh\:mm\:ss}] {1}: {2}{3}' -f $ts, $who, $what, $flag))
        }
    }
    return $sb.ToString()
}
