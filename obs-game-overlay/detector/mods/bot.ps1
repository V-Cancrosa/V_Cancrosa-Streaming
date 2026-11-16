#Requires -Version 5.1
# Moduł GameRadara: bot czatu (pisze z Twojego konta, każda wiadomość ze znacznikiem, domyślnie «🤖»)
# Wczytywany przez detector.ps1 (dot-source). Gdy antywirus albo błąd go zablokuje, reszta GameRadara działa dalej.
#
#  • automoderacja – wykrywa kokpit (themes/automod.js: filtr słów, CAPS, linki, spam), tu tylko kary:
#      słowa nienawiści → usunięcie + timeout 10 min; reszta → 1. raz ostrzeżenie, 2. timeout, potem dłuższe;
#      jedna wiadomość = jedna kara (kokpit w OBS i w przeglądarce mogą zgłosić to samo)
#  • komendy – wbudowane (!komendy, !sociale, !gra, !postac) i Twoje własne (strona «Bot czatu»)
#  • timery – komunikat co N minut, tylko gdy czat żyje
# Ustawienia: obsGameOverlay.v1 → bot { on, prefix, automod{…}, commands[{name,reply}], timers[{text,every}] }

$script:Bot = @{ rev = -1; cfg = $null; handled = [ordered]@{}; strikes = @{}; cool = @{}; log = New-Object Collections.ArrayList; lastSend = [DateTime]::MinValue; msgs = 0; timerAt = @{} }
$BotDefaultSocials = 'telegram: @vincent_vince_cancrosa, bluesky: @vcancrosa.bsky.social, instagram: @vincent_cancrosa, x: @Vulpine_Regnum, reddit: u/Kilokero1, github: V-Cancrosa'

function Get-BotCfg {
    if ($script:Bot.rev -ne $script:SettingsRev) {
        $script:Bot.rev = $script:SettingsRev
        $b = $null; $s = $null
        try { $s = $script:Settings | ConvertFrom-Json; $b = $s.bot } catch {}
        $am = $(if ($b -and $b.automod) { $b.automod } else { $null })
        $script:Bot.cfg = [pscustomobject]@{
            on = [bool]($b -and $b.on); prefix = $(if ($b -and $b.prefix) { [string]$b.prefix } else { [string][char]::ConvertFromUtf32(0x1F916) })
            words = -not ($am -and $am.words -eq $false); caps = -not ($am -and $am.caps -eq $false); links = -not ($am -and $am.links -eq $false); spam = -not ($am -and $am.spam -eq $false)
            automod = -not ($am -and $am.on -eq $false); timeout = $(if ($am -and $am.timeout) { [int]$am.timeout } else { 60 })
            commands = @($(if ($b -and $b.commands) { $b.commands } else { @() })); timers = @($(if ($b -and $b.timers) { $b.timers } else { @() }))
            socials = $(if ($s -and $s.socials) { [string]$s.socials } else { $BotDefaultSocials }); theme = $(if ($s) { [string]$s.theme } else { '' })
        }
    }
    return $script:Bot.cfg
}
function Add-BotLog([string]$what) {
    [void]$script:Bot.log.Add([pscustomobject]@{ at = (Get-Date).ToString('HH:mm:ss'); t = $what })
    while ($script:Bot.log.Count -gt 60) { $script:Bot.log.RemoveAt(0) }
}
# wiadomość na czat z Twojego konta (ze znacznikiem); najwyżej jedna na sekundę
function Send-ChatMessage([string]$text) {
    $c = Get-BotCfg; $uid = $script:TW.userId
    if (-not $uid -or -not $text) { return $false }
    $wait = 1100 - ((Get-Date) - $script:Bot.lastSend).TotalMilliseconds; if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]$wait) }
    $msg = ($c.prefix + ' ' + $text).Trim(); if ($msg.Length -gt 480) { $msg = $msg.Substring(0, 480) }
    try {
        [void](Invoke-Helix 'POST' 'chat/messages' @{ broadcaster_id = $uid; sender_id = $uid; message = $msg })
        $script:Bot.lastSend = Get-Date; return $true
    } catch {
        $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        Add-BotLog ("nie wysłano ($code)" + $(if ($code -eq 401 -or $code -eq 403) { ' – zaloguj się ponownie do Twitcha (uprawnienie: pisanie na czacie)' } else { '' }))
        return $false
    }
}
function Test-BotMessage([string]$text) { $c = Get-BotCfg; return $c.prefix -and $text.StartsWith($c.prefix) }

# czat → komendy i licznik dla timerów
function Invoke-Bot($ev) {
    $c = Get-BotCfg
    if (-not $c.on -or -not $ev -or $ev.test -or (Test-BotMessage ([string]$ev.text))) { return }
    $script:Bot.msgs++
    $t = ([string]$ev.text).Trim()
    if (-not $t.StartsWith('!')) { return }
    $cmd = (Remove-Diacritics ($t.Substring(1).Split(' ')[0])).ToLowerInvariant(); if (-not $cmd -or $cmd -eq 'vm') { return }
    $now = Get-Date; $last = $script:Bot.cool[$cmd]
    if ($last -and ($now - $last).TotalSeconds -lt 20) { return }        # ta sama komenda najwyżej co 20 s
    $reply = $null
    foreach ($x in $c.commands) { if ((Remove-Diacritics ([string]$x.name)).TrimStart('!').ToLowerInvariant() -eq $cmd) { $reply = ([string]$x.reply).Replace('{user}', '@' + [string]$ev.user); break } }
    if (-not $reply) {
        switch ($cmd) {
            { $_ -in 'komendy' } { $reply = 'komendy: ' + ((@('!sociale', '!gra', '!postac') + @($c.commands | ForEach-Object { '!' + ([string]$_.name).TrimStart('!') })) -join ' ') }
            { $_ -in 'sociale', 'socials' } { $reply = (($c.socials -split '[,|\n]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' · ') }
            { $_ -in 'gra', 'game' } { $g = $(if ($script:State -and $script:State.game) { [string]$script:State.game.name } else { '' }); $reply = $(if ($g) { "teraz: $g" } else { 'teraz bez gry – rozmowa' }) }
            { $_ -in 'postac', 'character' } { $p = $c.theme -replace '^g-', ''; $names = @{ vince = 'Vince'; chip = 'Chip'; ragnar = 'Ragnar'; toro = 'Toro'; myr = 'Myr-35'; zarin = 'Zarin' }; $reply = $(if ($names[$p]) { "prowadzi: $($names[$p])" } else { $null }) }
        }
    }
    if ($reply) { $script:Bot.cool[$cmd] = $now; if (Send-ChatMessage $reply) { Add-BotLog "!$cmd → $reply" } }
}

# timery: komunikat co «every» minut, gdy od poprzedniego ktoś pisał (co najmniej 5 wiadomości)
function Update-BotTimers {
    $c = Get-BotCfg
    if (-not $c.on -or -not $c.timers.Count -or -not $script:TW.userId) { return }
    $now = Get-Date
    for ($k = 0; $k -lt $c.timers.Count; $k++) {
        $tm = $c.timers[$k]; $every = [Math]::Max(5, [int]$tm.every); $key = "t$k|" + [string]$tm.text
        if (-not $script:Bot.timerAt.ContainsKey($key)) { $script:Bot.timerAt[$key] = @{ at = $now; msgs = $script:Bot.msgs }; continue }
        $st = $script:Bot.timerAt[$key]
        if (($now - $st.at).TotalMinutes -ge $every -and ($script:Bot.msgs - $st.msgs) -ge 5) {
            if (Send-ChatMessage ([string]$tm.text)) { Add-BotLog "timer: $([string]$tm.text)" }
            $script:Bot.timerAt[$key] = @{ at = $now; msgs = $script:Bot.msgs }
        }
    }
}

# kara za wiadomość (zgłasza kokpit); kind: hate | words | caps | links | spam
function Invoke-BotAct([string]$msgId, [string]$userId, [string]$name, [string]$kind) {
    $c = Get-BotCfg
    if (-not $c.on -or -not $c.automod) { return @{ ok = $false; error = 'bot wyłączony' } }
    if (-not $msgId -or $userId -notmatch '^\d+$') { return @{ ok = $false; error = 'brak danych' } }
    if ($script:Bot.handled.Contains($msgId)) { return @{ ok = $true; dup = $true } }
    $script:Bot.handled[$msgId] = 1; while ($script:Bot.handled.Count -gt 500) { $script:Bot.handled.RemoveAt(0) }
    $uid = $script:TW.userId
    $why = @{ hate = 'zakazane słowo'; words = 'bez wyzwisk'; caps = 'bez CAPSa'; links = 'linki tylko po zgodzie moderatora'; spam = 'bez spamu' }[$kind]; if (-not $why) { $why = 'regulamin czatu' }
    try { [void](Invoke-Helix 'DELETE' "moderation/chat?broadcaster_id=$uid&moderator_id=$uid&message_id=$([Uri]::EscapeDataString($msgId))" $null) } catch {}
    $now = Get-Date; $st = $script:Bot.strikes[$userId]
    if (-not $st -or ($now - $st.at).TotalMinutes -gt 30) { $st = @{ n = 0; at = $now } }
    $st.n++; $st.at = $now; $script:Bot.strikes[$userId] = $st
    $sec = 0
    if ($kind -eq 'hate') { $sec = 600 }
    elseif ($st.n -ge 2) { $sec = [int][Math]::Min(3600, $c.timeout * [Math]::Pow(2, $st.n - 2)) }
    if ($sec -gt 0) {
        try { [void](Invoke-Helix 'POST' "moderation/bans?broadcaster_id=$uid&moderator_id=$uid" @{ data = @{ user_id = $userId; duration = $sec; reason = "Nora: $why" } }) } catch {}
        [void](Send-ChatMessage "@$name – $why. Przerwa: $([Math]::Round($sec / 60, 1)) min.")
        Add-BotLog "${name}: $why → usunięte + timeout $sec s"
    } else {
        [void](Send-ChatMessage "@$name – $why, proszę (ostrzeżenie).")
        Add-BotLog "${name}: $why → usunięte + ostrzeżenie"
    }
    return @{ ok = $true; timeout = $sec; strikes = $st.n }
}
