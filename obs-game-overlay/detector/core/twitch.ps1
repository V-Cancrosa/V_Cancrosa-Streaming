#Requires -Version 5.1
# GameRadar · część «twitch»: Twitch: logowanie (device code), Helix, EventSub przez WebSocket
# Wczytywana przez detector.ps1 (dot-source) w ustalonej kolejności – korzysta z rzeczy z poprzednich części.
# Ścieżki: $Root = folder detector, $DataDir = detector\data, $AppDir = folder aplikacji (nie $PSScriptRoot – to byłby folder core).

# ---------------------------------------------------------------- Twitch (EventSub przez WebSocket)
# Logowanie: Device Code Flow (kod na twitch.tv/activate), aplikacja typu «Public» – bez sekretu.
# Token jest zaszyfrowany kontem Windows (DPAPI) w data\twitch-token.bin.
Add-Type -AssemblyName System.Security
$TwitchCfgFile = Join-Path $DataDir 'twitch.json'
$TwitchTokFile = Join-Path $DataDir 'twitch-token.bin'
$TwitchScopes  = 'moderator:read:followers channel:read:subscriptions bits:read channel:read:redemptions user:read:chat moderator:manage:chat_settings moderator:manage:chat_messages moderator:manage:banned_users channel:read:stream_key user:write:chat'
$script:TW = [pscustomobject]@{
    status = 'off'; clientId = ''; user = ''; userId = ''; error = ''
    code = ''; uri = ''; deviceCode = ''; deviceInterval = 5; deviceUntil = [DateTime]::MinValue; nextPoll = [DateTime]::MinValue
    token = $null; ws = $null; recv = $null; buf = $null; ms = $null; lastMsg = [DateTime]::MinValue; keepalive = 30
    reconnectAt = [DateTime]::MinValue; resubscribe = $true; nextRefresh = [DateTime]::MinValue
}

function Save-TwitchToken($t) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($t | ConvertTo-Json -Compress))
    $enc = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes($TwitchTokFile, $enc)
}
function Read-TwitchToken {
    if (-not (Test-Path $TwitchTokFile)) { return $null }
    try {
        $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($TwitchTokFile), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        return ([Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json)
    } catch { return $null }
}
function Get-ErrBody($err) {
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) { return $err.ErrorDetails.Message }
    return $err.Exception.Message
}
function Set-TwitchToken($resp) {
    $t = [pscustomobject]@{
        access = [string]$resp.access_token; refresh = [string]$resp.refresh_token
        expires = (Get-Date).AddSeconds([int]$resp.expires_in).ToString('o')
    }
    $script:TW.token = $t
    Save-TwitchToken $t
    $script:TW.nextRefresh = (Get-Date).AddSeconds([Math]::Max(60, [int]$resp.expires_in - 600))
}
function Update-TwitchToken {
    $t = $script:TW.token
    if (-not $t -or -not $t.refresh) { return $false }
    try {
        $r = Invoke-RestMethod -UseBasicParsing -Method Post -Uri 'https://id.twitch.tv/oauth2/token' -TimeoutSec 15 `
            -Body @{ client_id = $script:TW.clientId; grant_type = 'refresh_token'; refresh_token = $t.refresh }
        Set-TwitchToken $r
        Log 'Twitch: token odświeżony' 'DarkGray'
        return $true
    } catch {
        Log "Twitch: nie udało się odświeżyć logowania ($(Get-ErrBody $_)) – zaloguj się ponownie w panelu." 'Yellow'
        $script:TW.token = $null; Remove-Item $TwitchTokFile -ErrorAction SilentlyContinue
        $script:TW.status = 'need-login'
        return $false
    }
}
function Invoke-Helix([string]$method, [string]$path, $body) {
    $h = @{ 'Client-Id' = $script:TW.clientId; Authorization = "Bearer $($script:TW.token.access)" }
    $args2 = @{ UseBasicParsing = $true; Method = $method; Uri = "https://api.twitch.tv/helix/$path"; Headers = $h; TimeoutSec = 15 }
    if ($null -ne $body) { $args2.ContentType = 'application/json'; $args2.Body = ($body | ConvertTo-Json -Depth 6 -Compress) }
    try { return Invoke-RestMethod @args2 }
    catch {
        $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        if ($code -eq 401 -and (Update-TwitchToken)) {
            $args2.Headers.Authorization = "Bearer $($script:TW.token.access)"
            return Invoke-RestMethod @args2
        }
        throw
    }
}

function Start-TwitchLogin([string]$clientId) {
    $clientId = $clientId.Trim()
    if ($clientId -notmatch '^[a-z0-9]{20,40}$') { throw 'To nie wygląda na Client ID z dev.twitch.tv' }
    $script:TW.clientId = $clientId
    [IO.File]::WriteAllText($TwitchCfgFile, (@{ clientId = $clientId } | ConvertTo-Json), $Utf8NoBom)
    Stop-TwitchSocket
    $r = Invoke-RestMethod -UseBasicParsing -Method Post -Uri 'https://id.twitch.tv/oauth2/device' -TimeoutSec 15 `
        -Body @{ client_id = $clientId; scopes = $TwitchScopes }
    $script:TW.deviceCode = [string]$r.device_code
    $script:TW.code = [string]$r.user_code
    $script:TW.uri = [string]$r.verification_uri
    $script:TW.deviceInterval = [Math]::Max(2, [int]$r.interval)
    $script:TW.deviceUntil = (Get-Date).AddSeconds([int]$r.expires_in)
    $script:TW.nextPoll = (Get-Date).AddSeconds($script:TW.deviceInterval)
    $script:TW.status = 'device'; $script:TW.error = ''
    Log "Twitch: wejdź na $($script:TW.uri) i wpisz kod $($script:TW.code)" 'Cyan'
}

function Test-TwitchDevice {
    if ((Get-Date) -lt $script:TW.nextPoll) { return }
    if ((Get-Date) -gt $script:TW.deviceUntil) { $script:TW.status = 'need-login'; $script:TW.error = 'Kod wygasł – kliknij «Połącz» jeszcze raz.'; return }
    $script:TW.nextPoll = (Get-Date).AddSeconds($script:TW.deviceInterval)
    try {
        $r = Invoke-RestMethod -UseBasicParsing -Method Post -Uri 'https://id.twitch.tv/oauth2/token' -TimeoutSec 15 -Body @{
            client_id = $script:TW.clientId; scopes = $TwitchScopes; device_code = $script:TW.deviceCode
            grant_type = 'urn:ietf:params:oauth:grant-type:device_code'
        }
        Set-TwitchToken $r
        $script:TW.code = ''; $script:TW.status = 'connecting'
        Log 'Twitch: zalogowano' 'Green'
        Connect-Twitch
    } catch {
        $msg = Get-ErrBody $_
        if ($msg -match 'authorization_pending') { return }
        if ($msg -match 'slow_down') { $script:TW.deviceInterval += 2; return }
        $script:TW.status = 'need-login'; $script:TW.error = "Logowanie nieudane: $msg"
        Log "Twitch: $($script:TW.error)" 'Yellow'
    }
}

function Stop-TwitchSocket {
    if ($script:TW.ws) { try { $script:TW.ws.Dispose() } catch {} }
    $script:TW.ws = $null; $script:TW.recv = $null
}

function Open-TwitchSocket([string]$url) {
    $ws = New-Object Net.WebSockets.ClientWebSocket
    $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
    if (-not $ws.ConnectAsync([Uri]$url, [Threading.CancellationToken]::None).Wait(15000)) { throw 'przekroczony czas połączenia' }
    $old = $script:TW.ws
    $script:TW.ws = $ws
    $script:TW.buf = New-Object byte[] 65536
    $script:TW.ms = New-Object IO.MemoryStream
    $script:TW.recv = $ws.ReceiveAsync([ArraySegment[byte]]::new($script:TW.buf), [Threading.CancellationToken]::None)
    $script:TW.lastMsg = Get-Date
    if ($old) { try { $old.Dispose() } catch {} }
}

function Connect-Twitch {
    try {
        if (-not $script:TW.token) { $script:TW.status = 'need-login'; return }
        $me = Invoke-Helix 'GET' 'users' $null
        $script:TW.userId = [string]$me.data[0].id
        $script:TW.user = [string]$me.data[0].display_name
        $script:TW.resubscribe = $true
        Open-TwitchSocket 'wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30'
        $script:TW.status = 'connecting'
    } catch {
        $script:TW.status = 'error'; $script:TW.error = Get-ErrBody $_
        $script:TW.reconnectAt = (Get-Date).AddSeconds(20)
        Log "Twitch: błąd połączenia ($($script:TW.error)), ponowię za 20 s" 'Yellow'
    }
}

function Register-TwitchEvents([string]$sessionId) {
    $uid = $script:TW.userId
    $subs = @(
        @{ type = 'channel.follow'; version = '2'; condition = @{ broadcaster_user_id = $uid; moderator_user_id = $uid } },
        @{ type = 'channel.subscribe'; version = '1'; condition = @{ broadcaster_user_id = $uid } },
        @{ type = 'channel.subscription.message'; version = '1'; condition = @{ broadcaster_user_id = $uid } },
        @{ type = 'channel.subscription.gift'; version = '1'; condition = @{ broadcaster_user_id = $uid } },
        @{ type = 'channel.cheer'; version = '1'; condition = @{ broadcaster_user_id = $uid } },
        @{ type = 'channel.raid'; version = '1'; condition = @{ to_broadcaster_user_id = $uid } },
        @{ type = 'channel.channel_points_custom_reward_redemption.add'; version = '1'; condition = @{ broadcaster_user_id = $uid } },
        @{ type = 'channel.chat.message'; version = '1'; condition = @{ broadcaster_user_id = $uid; user_id = $uid } },
        @{ type = 'stream.online'; version = '1'; condition = @{ broadcaster_user_id = $uid } },
        @{ type = 'stream.offline'; version = '1'; condition = @{ broadcaster_user_id = $uid } },
        @{ type = 'channel.update'; version = '2'; condition = @{ broadcaster_user_id = $uid } }
    )
    $ok = 0
    foreach ($s in $subs) {
        $s.transport = @{ method = 'websocket'; session_id = $sessionId }
        try { [void](Invoke-Helix 'POST' 'eventsub/subscriptions' $s); $ok++ }
        catch { Log "Twitch: nie mogę włączyć $($s.type) ($(Get-ErrBody $_))" 'DarkYellow' }
    }
    Log "Twitch: połączono jako $($script:TW.user) – aktywne zdarzenia: $ok/$($subs.Count)" 'Green'
}

function Convert-TwitchEvent([string]$type, $e) {
    $tier = { param($t) switch ([string]$t) { '2000' { 'Tier 2' } '3000' { 'Tier 3' } default { 'Tier 1' } } }
    switch ($type) {
        'channel.follow' { return [pscustomobject]@{ type = 'follow'; user = $e.user_name; login = [string]$e.user_login } }
        'channel.subscribe' {
            if ($e.is_gift) { return $null }   # pokazujemy jeden alert «gift» zamiast wielu
            return [pscustomobject]@{ type = 'sub'; user = $e.user_name; tier = (& $tier $e.tier) }
        }
        'channel.subscription.message' {
            return [pscustomobject]@{ type = 'resub'; user = $e.user_name; tier = (& $tier $e.tier); months = [int]$e.cumulative_months; message = [string]$e.message.text }
        }
        'channel.subscription.gift' {
            $u = if ($e.is_anonymous) { 'Anonim' } else { $e.user_name }
            return [pscustomobject]@{ type = 'gift'; user = $u; tier = (& $tier $e.tier); count = [int]$e.total }
        }
        'channel.cheer' {
            $u = if ($e.is_anonymous) { 'Anonim' } else { $e.user_name }
            return [pscustomobject]@{ type = 'cheer'; user = $u; amount = [int]$e.bits; message = [string]$e.message }
        }
        'channel.raid' { return [pscustomobject]@{ type = 'raid'; user = $e.from_broadcaster_user_name; viewers = [int]$e.viewers } }
        'channel.chat.message' {
            $frags = @()
            foreach ($f in @($e.message.fragments)) {
                if ($f.type -eq 'emote' -and $f.emote) { $frags += [pscustomobject]@{ t = 'emote'; id = [string]$f.emote.id; v = [string]$f.text } }
                else { $frags += [pscustomobject]@{ t = 'text'; v = [string]$f.text } }
            }
            $badges = @($e.badges | ForEach-Object { [string]$_.set_id })
            $ce = New-ChatEvent ([string]$e.chatter_user_login) ([string]$e.chatter_user_name) ([string]$e.color) ([string]$e.message.text) $frags $badges $false ([string]$e.chatter_user_id)
            # do moderacji z kokpitu: numer wiadomości i konta
            if ($ce) { $ce | Add-Member -NotePropertyName msgId -NotePropertyValue ([string]$e.message_id) -Force; $ce | Add-Member -NotePropertyName userId -NotePropertyValue ([string]$e.chatter_user_id) -Force }
            # bot czatu: wiadomości z jego znacznikiem są «botem» (plakietka, «ukryj boty»); komendy i licznik timerów
            if ($ce -and (Get-Command Invoke-Bot -ErrorAction SilentlyContinue)) {
                try { if (Test-BotMessage ([string]$ce.text)) { $ce | Add-Member -NotePropertyName bot -NotePropertyValue $true -Force } else { Invoke-Bot $ce } } catch {}
            }
            return $ce
        }
        'channel.channel_points_custom_reward_redemption.add' {
            # nagroda «Efekt: konfetti» (albo inny efekt) uruchamia efekt bez limitu czasu
            $title = Remove-Diacritics ([string]$e.reward.title)
            foreach ($fx in $ChatEffects) { if ($title -match "efekt\W*$fx") { Add-Event ([pscustomobject]@{ type = 'effect'; effect = $fx; user = $e.user_name }); break } }
            return [pscustomobject]@{ type = 'redeem'; user = $e.user_name; reward = [string]$e.reward.title; cost = [int]$e.reward.cost; message = [string]$e.user_input }
        }
    }
    return $null
}

function Read-TwitchMessage([string]$text) {
    $m = $text | ConvertFrom-Json
    $script:TW.lastMsg = Get-Date
    switch ([string]$m.metadata.message_type) {
        'session_welcome' {
            $script:TW.keepalive = [int]$m.payload.session.keepalive_timeout_seconds
            $script:TW.status = 'online'; $script:TW.error = ''
            if ($script:TW.resubscribe) { Register-TwitchEvents ([string]$m.payload.session.id) }
            $script:TW.resubscribe = $false
        }
        'session_reconnect' {
            Log 'Twitch: serwer prosi o przełączenie połączenia' 'DarkGray'
            $script:TW.resubscribe = $false   # subskrypcje przechodzą na nowe połączenie
            Open-TwitchSocket ([string]$m.payload.session.reconnect_url)
        }
        'notification' {
            $st = [string]$m.metadata.subscription_type; $pe = $m.payload.event
            # początek/koniec streama i zmiana kategorii – do archiwum i flagowania
            if ($st -eq 'stream.online') { $script:Channel.live = $true; Open-StreamArchive $true ([datetime]::Parse([string]$pe.started_at).ToLocalTime()); $script:Channel.nextPoll = (Get-Date).AddSeconds(5); return }
            if ($st -eq 'stream.offline') { Close-StreamArchive; $script:Channel.live = $false; return }
            if ($st -eq 'channel.update') { $script:Channel.category = [string]$pe.category_name; $script:Channel.title = [string]$pe.title; if ($script:Cur) { $script:Cur.category = $script:Channel.category; $script:Cur.title = $script:Channel.title }; return }
            $ev = Convert-TwitchEvent $st $pe
            if ($ev) { Add-Event $ev }
        }
        'revocation' { Log "Twitch: wyłączono zdarzenie $($m.payload.subscription.type) ($($m.payload.subscription.status))" 'Yellow' }
    }
}

function Update-Twitch {
    $tw = $script:TW
    switch ($tw.status) {
        'device' { Test-TwitchDevice; return }
        'off' { return }
        'need-login' { return }
    }
    if ($tw.token -and (Get-Date) -gt $tw.nextRefresh) { [void](Update-TwitchToken) }
    if (-not $tw.ws) {
        if ($tw.token -and (Get-Date) -gt $tw.reconnectAt) { Connect-Twitch }
        return
    }
    # odbiór wiadomości bez blokowania pętli
    while ($tw.recv -and $tw.recv.IsCompleted) {
        if ($tw.recv.IsFaulted -or $tw.recv.IsCanceled) { $tw.recv = $null; break }
        $cur = $tw.recv
        $res = $cur.Result
        if ($res.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { $tw.recv = $null; break }
        $tw.ms.Write($tw.buf, 0, $res.Count)
        if ($res.EndOfMessage) {
            $text = [Text.Encoding]::UTF8.GetString($tw.ms.ToArray())
            $tw.ms.SetLength(0)
            try { Read-TwitchMessage $text } catch { Log "Twitch: błąd wiadomości ($($_.Exception.Message))" 'DarkYellow' }
        }
        if (-not $tw.ws) { return }
        if ($tw.recv -ne $cur) { continue }   # po «session_reconnect» nowe połączenie już czeka na dane
        $tw.recv = $tw.ws.ReceiveAsync([ArraySegment[byte]]::new($tw.buf), [Threading.CancellationToken]::None)
    }
    $silent = ((Get-Date) - $tw.lastMsg).TotalSeconds -gt ($tw.keepalive + 10)
    if (-not $tw.recv -or $silent) {
        Log 'Twitch: połączenie zerwane, łączę ponownie…' 'Yellow'
        Stop-TwitchSocket
        $tw.status = 'connecting'; $tw.resubscribe = $true
        $tw.reconnectAt = (Get-Date).AddSeconds(3)
    }
}

function Initialize-Twitch {
    if (Test-Path $TwitchCfgFile) {
        try { $script:TW.clientId = [string]((Get-Content $TwitchCfgFile -Raw) | ConvertFrom-Json).clientId } catch {}
    }
    if (-not $script:TW.clientId) { $script:TW.status = 'off'; return }
    $script:TW.token = Read-TwitchToken
    if (-not $script:TW.token) { $script:TW.status = 'need-login'; return }
    $script:TW.nextRefresh = [DateTime]::Parse($script:TW.token.expires).AddMinutes(-10)
    $script:TW.status = 'connecting'
    Connect-Twitch
}

function Get-TwitchStatus {
    return [pscustomobject]@{
        status = $script:TW.status; user = $script:TW.user; hasClient = [bool]$script:TW.clientId
        code = $script:TW.code; uri = $script:TW.uri; error = $script:TW.error
    }
}

# zdarzenia testowe (przyciski w panelu)
function New-TestEvent([string]$type, [int]$tier = 0, [string]$msg = '') {
    $names = @('LunaFox', 'Kuba_Gra', 'PixelWilk', 'Nocny_Smok', 'herbatka99', 'MrówkaPancerna')
    $u = $names[(Get-Random -Maximum $names.Count)]
    # poziom 1–5: wartości jak w themes/tiers.js (SAMPLE), żeby sprawdzić każdą wielkość reakcji
    if ($tier -ge 1 -and $tier -le 5) {
        $i = $tier - 1
        switch ($type) {
            'cheer'  { return [pscustomobject]@{ type = 'cheer'; user = $u; amount = @(50, 300, 800, 2500, 10000)[$i]; message = 'Test poziomu'; test = $true } }
            'gift'   { return [pscustomobject]@{ type = 'gift'; user = $u; tier = 'Tier 1'; count = @(1, 3, 7, 20, 100)[$i]; test = $true } }
            'resub'  { return [pscustomobject]@{ type = 'resub'; user = $u; tier = 'Tier 1'; months = @(2, 4, 9, 18, 36)[$i]; message = 'Test poziomu'; test = $true } }
            'raid'   { return [pscustomobject]@{ type = 'raid'; user = $u; viewers = @(3, 12, 35, 120, 500)[$i]; test = $true } }
            'redeem' { return [pscustomobject]@{ type = 'redeem'; user = $u; reward = 'Nawodnij się'; cost = @(100, 1000, 5000, 20000, 100000)[$i]; message = ''; test = $true } }
            'sub'    { return [pscustomobject]@{ type = 'sub'; user = $u; tier = $(if ($tier -ge 4) { 'Tier 3' } elseif ($tier -eq 3) { 'Tier 2' } else { 'Tier 1' }); test = $true } }
        }
    }
    switch ($type) {
        'chatbot' {
            # podejrzana wiadomość: świeże konto, «fajnie grasz» i reklama widzów
            $m = 'fajnie grasz! best viewers on streamboo .com'
            return (New-ChatEvent 'nowe_konto_2077' 'nowe_konto_2077' '' $m @([pscustomobject]@{ t = 'text'; v = $m }) @() $true '' 0.3)
        }
        'chat' {
            $msgs = @('cześć wszystkim!', 'ale akcja', 'GG', 'jak długo już grasz?', '!styl pixel', 'to było mocne', 'pozdro z Krakowa', '!kolor turkus')
            $m = $msgs[(Get-Random -Maximum $msgs.Count)]
            return (New-ChatEvent ($u.ToLowerInvariant()) $u '' $m @([pscustomobject]@{ t = 'text'; v = $m }) @() $true)
        }
        'effect' { return [pscustomobject]@{ type = 'effect'; effect = $ChatEffects[(Get-Random -Maximum $ChatEffects.Count)]; user = $u; test = $true } }
        'follow' { return [pscustomobject]@{ type = 'follow'; user = $u; test = $true } }
        'sub'    { return [pscustomobject]@{ type = 'sub'; user = $u; tier = 'Tier 1'; test = $true } }
        'resub'  { return [pscustomobject]@{ type = 'resub'; user = $u; tier = 'Tier 1'; months = 7; message = 'Siódmy miesiąc, dalej najlepszy kanał!'; test = $true } }
        'gift'   { return [pscustomobject]@{ type = 'gift'; user = $u; tier = 'Tier 1'; count = 5; test = $true } }
        'cheer'  { return [pscustomobject]@{ type = 'cheer'; user = $u; amount = 500; message = 'Na nowe ciasteczka'; test = $true } }
        'raid'   { return [pscustomobject]@{ type = 'raid'; user = $u; viewers = 42; test = $true } }
        'redeem' { return [pscustomobject]@{ type = 'redeem'; user = $u; reward = 'Nawodnij się'; cost = 500; message = ''; test = $true } }
    }
    return $null
}
