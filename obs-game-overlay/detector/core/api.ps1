#Requires -Version 5.1
# GameRadar · część «api»: wszystkie adresy GameRadara (Invoke-Request) – lista w README, sekcja «Dla programisty»
# Wczytywana przez detector.ps1 (dot-source) w ustalonej kolejności – korzysta z rzeczy z poprzednich części.
# Ścieżki: $Root = folder detector, $DataDir = detector\data, $AppDir = folder aplikacji (nie $PSScriptRoot – to byłby folder core).

function Invoke-Request($ctx) {
    $req = $ctx.Request
    try {
        $q = Get-Query $req
        $path = $req.Url.AbsolutePath
        $script:AllowOrigin = if ($req.Headers['Origin']) { [string]$req.Headers['Origin'] } else { '*' }
        if ($req.HttpMethod -eq 'OPTIONS') {
            # zapytanie wstępne przeglądarki (nagłówek X-VM-Key) – samo niczego nie robi
            $ctx.Response.Headers['Access-Control-Allow-Methods'] = 'GET, POST'
            $ctx.Response.Headers['Access-Control-Allow-Headers'] = 'X-VM-Key, Content-Type'
            Send-Json $ctx @{ ok = $true }; return
        }
        # tylko ten komputer (GameRadar nie słucha w sieci domowej – telefon steruje przez przekaźnik)
        if (-not $req.IsLocal) { Send-Json $ctx @{ ok = $false; error = 'tylko z tego komputera' } 403; return }
        if ($path -eq '/ui' -or $path.StartsWith('/ui/')) { Send-File $ctx ($path -replace '^/ui/?', ''); return }
        # obrazki (ikony, okładki) i stan aktualizacji są niegroźne; reszta tylko dla zaufanych stron
        if (@('/icon', '/art', '/update/status') -notcontains $path.TrimEnd('/') -and -not (Test-Trusted $req $q)) {
            $o = [string]$req.Headers['Origin']; if (-not $o) { $o = 'bez adresu (' + [string]$req.Headers['Referer'] + ')' }
            if (-not $script:BlockedLogged.ContainsKey($o)) { $script:BlockedLogged[$o] = 1; Log "Zablokowano stronę spoza zaufanych: $o → $path (dopisz ją do data\trusted-origins.txt, jeśli to Twoja)" 'Yellow' }
            $script:AllowOrigin = '*'
            Send-Json $ctx @{ ok = $false; error = 'untrusted'; msg = 'Ta strona nie jest na liście zaufanych wykrywacza.' } 403; return
        }
        switch ($path.TrimEnd('/')) {
            '/settings' {
                if ($req.HttpMethod -eq 'POST') {
                    $body = Read-Body $req
                    try { $data = $body | ConvertFrom-Json } catch { Send-Json $ctx @{ ok = $false; error = 'zły JSON' } 400; return }
                    $script:Settings = ($data.settings | ConvertTo-Json -Depth 10 -Compress)
                    $script:SettingsRev++; $script:SettingsFrom = [string]$data.client
                    [IO.File]::WriteAllText($SettingsFile, (@{ rev = $script:SettingsRev; json = $script:Settings } | ConvertTo-Json -Compress), $Utf8NoBom)
                    Send-Json $ctx ([pscustomobject]@{ ok = $true; rev = $script:SettingsRev })
                } else {
                    # ustawienia jako tekst JSON – bez przepuszczania przez obiekty PowerShella
                    $json = if ($script:Settings) { $script:Settings } else { 'null' }
                    $raw = '{"rev":' + $script:SettingsRev + ',"from":' + ($script:SettingsFrom | ConvertTo-Json) + ',"settings":' + $json + '}'
                    $res = $ctx.Response; $res.ContentType = 'application/json; charset=utf-8'
                    $res.Headers['Access-Control-Allow-Origin'] = $script:AllowOrigin; $res.Headers['Cache-Control'] = 'no-store'
                    $b = $Utf8NoBom.GetBytes($raw); $res.ContentLength64 = $b.Length; $res.OutputStream.Write($b, 0, $b.Length); $res.OutputStream.Close()
                }
            }
            '/relay' {
                if ($q['on'] -eq '1') { if (-not $script:Relay.topic) { New-RelayTopic }; $script:Relay.on = $true; Save-Relay; Log 'Pilot z telefonu (przekaźnik): włączony' 'Cyan' }
                if ($q['on'] -eq '0') { $script:Relay.on = $false; Save-Relay; Log 'Pilot z telefonu (przekaźnik): wyłączony' }
                if ($q['new'] -eq '1') { New-RelayTopic; Log 'Pilot z telefonu: nowy klucz – stary link przestał działać' 'Cyan' }
                $pollAgo = if ($script:RelayPollAt -eq [DateTime]::MinValue) { -1 } else { [int][Math]::Min([double]99999, ((Get-Date) - $script:RelayPollAt).TotalSeconds) }
                Send-Json $ctx ([pscustomobject]@{ ok = $true; on = $script:Relay.on; topic = $(if ($script:Relay.on) { $script:Relay.topic } else { '' }); last = $script:RelayLast; error = $script:RelayErr; pollAgo = $pollAgo })
            }
            '/kv' {
                if ($req.HttpMethod -eq 'POST') {
                    $body = Read-Body $req
                    if ($body.Length -gt 3MB) { Send-Json $ctx @{ ok = $false; error = 'za duże' } 413; return }
                    try { $d = $body | ConvertFrom-Json } catch { Send-Json $ctx @{ ok = $false; error = 'zły JSON' } 400; return }
                    $k = [string]$d.key
                    if ($KvKeys -notcontains $k) { Send-Json $ctx @{ ok = $false; error = 'nieznany klucz' } 400; return }
                    $script:KvRev++; $script:KV[$k] = @{ rev = $script:KvRev; from = [string]$d.client; val = [string]$d.val }
                    if ($k -ne 'obsGameOverlay.pageVis') { Save-Kv }
                    Send-Json $ctx ([pscustomobject]@{ ok = $true; rev = $script:KvRev })
                } else {
                    # tylko to, co zmieniło się po «since»; wartość idzie jako tekst JSON bez przepuszczania przez obiekty PowerShella
                    $since = 0; if ($q.ContainsKey('since')) { [void][int]::TryParse([string]$q['since'], [ref]$since) }
                    $parts = @(); foreach ($k in $script:KV.Keys) { $e = $script:KV[$k]; if ($e.rev -gt $since) { $parts += (($k | ConvertTo-Json) + ':{"rev":' + $e.rev + ',"from":' + ($e.from | ConvertTo-Json) + ',"val":' + ($e.val | ConvertTo-Json) + '}') } }
                    Send-Raw $ctx ('{"rev":' + $script:KvRev + ',"items":{' + ($parts -join ',') + '}}') 'application/json'
                }
            }
            '/session' { Send-Json $ctx (Get-Session) }
            '/obsws' {
                # hasło do OBS WebSocket zapisane przez instalator – nakładki łączą się z OBS bez wpisywania czegokolwiek
                $f = Join-Path $DataDir 'obs-ws.json'
                if (Test-Path $f) {
                    try { $o = (Get-Content $f -Raw -Encoding UTF8) | ConvertFrom-Json; Send-Json $ctx ([pscustomobject]@{ ok = $true; url = "ws://localhost:$($o.port)"; password = [string]$o.password }) }
                    catch { Send-Json $ctx @{ ok = $false } }
                } else { Send-Json $ctx @{ ok = $false } }
            }
            '/game' {
                Send-Json $ctx ([pscustomobject]@{ online = $true; version = 2; appVersion = $script:AppVersion; settingsRev = $script:SettingsRev; game = $script:State.game; recent = @($script:State.recent); twitch = (Get-TwitchStatus) })
            }
            '/update/status' { Send-Json $ctx (Get-UpdateStatus) }
            '/update/check' { Invoke-UpdateCheck; Send-Json $ctx (Get-UpdateStatus) }
            '/mod' {
                # moderacja z kokpitu: usuń wiadomość, wycisz (timeout), ban
                $act = [string]$q['do']; $uid = $script:TW.userId
                if (-not $uid) { Send-Json $ctx @{ ok = $false; error = 'Twitch niepołączony' } 409; return }
                try {
                    $who = [string]$q['user']
                    if ($act -eq 'delete') {
                        [void](Invoke-Helix 'DELETE' "moderation/chat?broadcaster_id=$uid&moderator_id=$uid&message_id=$([Uri]::EscapeDataString([string]$q['msg']))" $null)
                    } elseif ($act -eq 'timeout' -or $act -eq 'ban') {
                        if ($who -notmatch '^\d+$') { throw 'brak konta' }
                        $d = @{ user_id = $who; reason = 'Vincent-Media' }
                        if ($act -eq 'timeout') { $sec = 600; [void][int]::TryParse([string]$q['sec'], [ref]$sec); $d.duration = [Math]::Max(1, [Math]::Min(1209600, $sec)) }
                        [void](Invoke-Helix 'POST' "moderation/bans?broadcaster_id=$uid&moderator_id=$uid" @{ data = $d })
                    } else { throw 'nieznana akcja' }
                    Log "Moderacja z kokpitu: $act $([string]$q['name'])" 'Cyan'
                    Send-Json $ctx @{ ok = $true }
                } catch {
                    $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
                    Send-Json $ctx @{ ok = $false; error = $_.Exception.Message; relogin = ($code -eq 401 -or $code -eq 403) }
                }
            }
            '/chat/slow' {
                # tryb powolny czatu na Twitchu – nakładka prosi o niego, gdy w kolejce wisi za dużo wiadomości
                $on = ([string]$q['on']) -eq '1'; $sec = 10; [void][int]::TryParse([string]$q['sec'], [ref]$sec)
                if (-not $script:SlowMode) { $script:SlowMode = [pscustomobject]@{ on = $false; at = [DateTime]::MinValue; err = '' } }
                if ($script:SlowMode.on -eq $on -or ((Get-Date) - $script:SlowMode.at).TotalSeconds -lt 20) { Send-Json $ctx $script:SlowMode; return }
                try {
                    $uid = $script:TW.userId
                    [void](Invoke-Helix 'PATCH' "chat/settings?broadcaster_id=$uid&moderator_id=$uid" @{ slow_mode = $on; slow_mode_wait_time = $(if ($on) { [Math]::Max(3, [Math]::Min(120, $sec)) } else { $null }) })
                    $script:SlowMode.on = $on; $script:SlowMode.err = ''
                    Log ("Czat: tryb powolny " + $(if ($on) { "włączony ($sec s) – za dużo wiadomości naraz" } else { 'wyłączony' })) 'Cyan'
                } catch {
                    $script:SlowMode.err = 'potrzebne ponowne połączenie z Twitchem (Więcej → Twitch → Wyloguj i połącz) – nowe uprawnienie: ustawienia czatu'
                    Log "Czat: nie mogę włączyć trybu powolnego – $($script:SlowMode.err)" 'Yellow'
                }
                $script:SlowMode.at = Get-Date
                Send-Json $ctx $script:SlowMode
            }
            '/vote' { Send-Json $ctx (Get-VoteStatus) }
            '/vote/start' {
                $v = $script:Vote
                $v.a = ([string]$q['a']).Trim(); $v.b = ([string]$q['b']).Trim(); $v.votes = @{}; $v.winner = ''; $v.id++
                $sec = 300; [void][int]::TryParse([string]$q['sec'], [ref]$sec); $sec = [Math]::Max(30, [Math]::Min(1800, $sec))
                $v.started = Get-Date; $v.ends = $v.started.AddSeconds($sec); $v.active = $true
                Log "Głosowanie: $($v.a) kontra $($v.b) – $sec s" 'Cyan'
                Send-Json $ctx (Get-VoteStatus)
            }
            '/vote/stop' { $script:Vote.ends = Get-Date; Send-Json $ctx (Get-VoteStatus) }
            '/vote/test' {
                # testowe głosy (panel → przycisk testu): kilka losowych widzów
                $n = 0; foreach ($i in 1..[Math]::Max(1, [Math]::Min(30, [int]$q['n']))) { $script:Vote.votes["test$(Get-Random -Maximum 100000)"] = $(if ((Get-Random -Maximum 100) -lt [int]$q['pa']) { 'a' } else { 'b' }); $n++ }
                Send-Json $ctx (Get-VoteStatus)
            }
            '/live' {
                $script:Live.stream = ([string]$q['stream']) -eq '1'; $script:Live.rec = ([string]$q['rec']) -eq '1'
                $script:Live.until = (Get-Date).AddSeconds(30)
                Send-Json $ctx @{ ok = $true; live = (Test-Live) }
            }
            '/update/run' {
                if (Test-Live) { $script:UP.error = 'trwa transmisja albo nagrywanie – aktualizacja zaczeka do końca'; Send-Json $ctx ([pscustomobject]@{ ok = $false; restarting = $false; status = (Get-UpdateStatus) }); return }
                if ([string]$q['force'] -eq '1') { Invoke-UpdateCheck -Install -Force } else { Invoke-UpdateCheck -Install }
                $st = Get-UpdateStatus
                Send-Json $ctx ([pscustomobject]@{ ok = -not $st.error; restarting = $script:RestartPending; status = $st })
            }
            '/update/auto' {
                $script:UP.auto = ([string]$q['on']) -ne '0'
                [IO.File]::WriteAllText($UpdateCfg, (@{ auto = $script:UP.auto } | ConvertTo-Json), $Utf8NoBom)
                Log ("Automatyczne aktualizacje: " + $(if ($script:UP.auto) { 'włączone' } else { 'wyłączone' }))
                Send-Json $ctx (Get-UpdateStatus)
            }
            '/launch' {
                if ($q.ContainsKey('obs') -and (($q['obs'] -eq '1') -ne $script:LaunchObs)) { $script:LaunchObs = $q['obs'] -eq '1'; [IO.File]::WriteAllText($LaunchFile, (@{ obs = $script:LaunchObs } | ConvertTo-Json), $Utf8NoBom); Log ("OBS razem z GameRadarem: " + $(if ($script:LaunchObs) { 'tak' } else { 'nie' })) }
                $msg = ''; if ($q['start'] -eq '1') { $msg = Start-Obs; Log "Panel: $msg" }
                $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) $(if (Test-Path (Join-Path $AppDir 'nora\Nora.exe')) { 'Nora.lnk' } else { 'Vincent-Media.lnk' })
                Send-Json $ctx ([pscustomobject]@{ ok = $true; obs = $script:LaunchObs; obsPath = (Find-Obs); shortcut = (Test-Path $lnk); msg = $msg; version = $script:AppVersion })
            }
            '/shortcut' {
                # skrót «Vincent-Media» na pulpicie (tylko po kliknięciu): kreator startu – sprawdza wszystko, uruchamia GameRadar, OBS i kokpit
                try {
                    $nm = $(if (Test-Path (Join-Path $AppDir 'nora\Nora.exe')) { 'Nora' } else { 'Vincent-Media' })
                    New-VMShortcut $AppDir (Join-Path ([Environment]::GetFolderPath('Desktop')) "$nm.lnk")
                    Log "Utworzono skrót «$nm» na pulpicie" 'Green'
                    Send-Json $ctx @{ ok = $true }
                } catch { Send-Json $ctx @{ ok = $false; error = $_.Exception.Message } }
            }
            '/restart' {
                # ponowne uruchomienie (np. żeby wczytać nową wersję) – nigdy w trakcie transmisji i nagrywania
                if (Test-Live) { Send-Json $ctx @{ ok = $false; error = 'trwa transmisja albo nagrywanie – uruchomię się ponownie po zakończeniu' }; $script:RestartPending = $true; return }
                Send-Json $ctx @{ ok = $true }; Log 'Panel: uruchamiam GameRadar ponownie' 'Cyan'; $script:RestartPending = $true
            }
            '/shutdown' {
                # «zamykamy budę»: OBS zamyka się normalnie (jak krzyżykiem), potem GameRadar; transmisję kończy wcześniej strona
                Send-Json $ctx @{ ok = $true }
                Log 'Zamykam OBS i GameRadar (polecenie ze strony)…' 'Yellow'
                $script:ShutdownAt = Get-Date
            }
            '/folder/open' {
                # folder z instalacją Vincent-Media w Eksploratorze (tam są pliki nakładek, GameRadar i dziennik)
                try { Start-Process explorer.exe -ArgumentList ('"' + (Split-Path $AppDir -Parent) + '"'); Send-Json $ctx @{ ok = $true } } catch { Send-Json $ctx @{ ok = $false; error = $_.Exception.Message } }
            }
            '/log/open' {
                # pełny dziennik w Notatniku (folder i plik zakładamy, jeśli ich nie ma)
                try { New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile) | Out-Null; if (-not (Test-Path $script:LogFile)) { [IO.File]::WriteAllText($script:LogFile, '', $Utf8NoBom) }
                      Start-Process notepad.exe -ArgumentList ('"' + $script:LogFile + '"'); Send-Json $ctx @{ ok = $true } } catch { Send-Json $ctx @{ ok = $false; error = $_.Exception.Message } }
            }
            '/log/file' {
                $t = ''; try { $t = [IO.File]::ReadAllText($script:LogFile, [Text.Encoding]::UTF8) } catch {}
                $ctx.Response.Headers['Content-Disposition'] = 'attachment; filename="detector.log"'
                Send-Raw $ctx $t 'text/plain'
            }
            '/log' {
                $after = 0; if ($q.ContainsKey('after')) { [void][int]::TryParse([string]$q['after'], [ref]$after) }
                Send-Json $ctx ([pscustomobject]@{ last = $script:LogSeq; lines = @($script:LogBuf | Where-Object { $_.n -gt $after }) })
            }
            '/events' {
                # bez «after» zwracamy tylko numer ostatniego zdarzenia – nowa nakładka nie odtwarza starych alertów
                $after = -1
                if ($q.ContainsKey('after')) { [void][int]::TryParse([string]$q['after'], [ref]$after) }
                $list = @()
                if ($after -ge 0) { $list = @($script:Events | Where-Object { $_.id -gt $after }) }
                Send-Json $ctx ([pscustomobject]@{ last = $script:EventSeq; events = $list; appVersion = $script:AppVersion })
            }
            '/test' {
                $tl = 0; [void][int]::TryParse([string]$q['tier'], [ref]$tl)
                $ev = New-TestEvent ([string]$q['type']) $tl ([string]$q['msg'])
                # wiadomość widza z panelu: w stylu aktywnej postaci i gry
                if ($ev -and $q['msg'] -and ($ev.PSObject.Properties.Name -contains 'message')) { $ev.message = [string]$q['msg'] }
                if ($ev -and $q['msg'] -and $ev.type -eq 'chat') { $ev.text = [string]$q['msg']; $ev.fragments = @([pscustomobject]@{ t = 'text'; v = [string]$q['msg'] }) }
                if (-not $ev) { Send-Json $ctx @{ ok = $false; error = 'nieznany typ' } 400; return }
                Add-Event $ev
                Send-Json $ctx @{ ok = $true }
            }
            '/replay' {
                # kokpit: powtórz alert (kopia zdarzenia z nowym numerem)
                $rid = 0; [void][int]::TryParse([string]$q['id'], [ref]$rid)
                $old = @($script:Events | Where-Object { $_.id -eq $rid })[0]
                if (-not $old) { Send-Json $ctx @{ ok = $false; error = 'nie ma już tego alertu' } 404; return }
                $copy = $old.PSObject.Copy(); $copy | Add-Member -NotePropertyName replay -NotePropertyValue $true -Force
                Add-Event $copy
                Send-Json $ctx @{ ok = $true }
            }
            '/transition' {
                # przejście między ekranami z pilota w telefonie (w OBS panel wysyła je bezpośrednio)
                Add-Event ([pscustomobject]@{ type = 'transition'; scene = [string]$q['scene']; style = [string]$q['style']; tid = [guid]::NewGuid().ToString('N') })
                Send-Json $ctx @{ ok = $true }
            }
            '/library' {
              try {
                $all = ([string]$q['all']) -eq '1'
                $list = @($script:GameLib.Values | Where-Object { $all -or -not $_.hidden } | Sort-Object { [string]$_.last } -Descending)
                # zainstalowane gry Steam, których jeszcze nie uruchamiałeś (do wyboru z listy)
                $inst = @()
                $steamIds = @{}
                try { foreach ($g in @(Get-SteamInstalled)) { $steamIds[$g.id] = 1 } } catch {}
                try { $inst = @(Get-SteamInstalled | Where-Object { -not $script:GameLib.ContainsKey($_.id) } | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name; steam = $_.steam; kind = 'game'; source = 'Steam'; installed = $true } }) } catch {}
                try { $inst += @(Get-OtherGames | Where-Object { -not $script:GameLib.ContainsKey($_.id) } | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name; steam = ''; kind = 'game'; source = $_.source; installed = $true; exe = $_.exe } }) } catch {}
                # zapisane pozycje: czy nadal są zainstalowane (gra Steam z listy Steama, program – plik istnieje)
                $list = @($list | ForEach-Object {
                    $x = $_.PSObject.Copy()
                    $ok = if ($x.steam) { $steamIds.ContainsKey('steam:' + $x.steam) } elseif ($x.path) { Test-Path -LiteralPath $x.path } else { $true }
                    $x | Add-Member -NotePropertyName installed -NotePropertyValue ([bool]$ok) -Force; $x })
                Send-Json $ctx ([pscustomobject]@{ items = $list; installed = $inst; current = $script:LibCurrent; error = $script:LibErr })
              } catch { Send-Json $ctx ([pscustomobject]@{ items = @(); installed = @(); current = ''; error = $_.Exception.Message }) }
            }
            '/censor/config' {
                $script:Censor.on = ([string]$q['on']) -eq '1'
                if ($q.ContainsKey('target')) { $script:Censor.target = ([string]$q['target']).Trim() }   # bez parametru (np. autotest) cel zostaje
                if ($q.ContainsKey('exes')) { $script:Censor.exes = @(([string]$q['exes']).ToLowerInvariant().Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
                if ($script:Censor.on) { $script:Censor.until = (Get-Date).AddSeconds(15); if (Get-Command Start-Censor -ErrorAction SilentlyContinue) { Start-Censor } else { $script:Censor.status = 'moduł zablokowany'; $script:Censor.err = 'moduł cenzury nie wczytał się (antywirus?) – zobacz log GameRadara' } }
                Send-Json $ctx @{ ok = $true; status = $script:Censor.status; fps = $script:Censor.fps; lang = $script:Censor.lang; error = $script:Censor.err }
            }
            '/censor' {
                $r = $script:Censor.result
                if (-not $r) { Send-Json $ctx @{ at = 0; status = $script:Censor.status; error = $script:Censor.err }; return }
                if (([string]$q['since']) -eq [string]$r.at) { Send-Json $ctx @{ at = $r.at; same = $true }; return }
                Send-Raw $ctx ([string]$script:Censor.json) 'application/json'
            }
            '/tts/voices' {
                # głosy Piper (domyślne, neuronowe) + głosy Windows (zapasowe)
                $hasWin = [bool](Get-Command Initialize-Tts -ErrorAction SilentlyContinue); $hasPiper = [bool](Get-Command Get-PiperVoiceList -ErrorAction SilentlyContinue)
                if ($hasWin) { Initialize-Tts }
                $list = @(); if ($hasPiper) { $list += @(Get-PiperVoiceList) }; if ($hasWin -and $script:Tts.ready) { $list += @($script:Tts.voices) }
                Send-Json $ctx ([pscustomobject]@{ ok = ($list.Count -gt 0); mode = $(if ($hasWin) { $script:Tts.mode } else { '' }); error = $(if ($hasWin) { $script:Tts.err } else { 'moduł głosu Windows nie działa' }); voices = $list
                    piper = $(if ($hasPiper) { Get-PiperStatus } else { $null }) })
            }
            '/tts/piper' {
                if (-not (Get-Command Get-PiperStatus -ErrorAction SilentlyContinue)) { Send-Json $ctx @{ ok = $false; error = 'moduł Piper nie działa (antywirus?) – zobacz dziennik' } 503; return }
                if ($q['install'] -eq '1') { Start-PiperInstall @(([string]$q['voices']).Split(',') | Where-Object { $_ }) }
                Send-Json $ctx (Get-PiperStatus)
            }
            '/tts' {
                $rate = 1.0; [void][double]::TryParse([string]$q['rate'], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$rate)
                $pitch = 0; [void][int]::TryParse([string]$q['pitch'], [ref]$pitch)
                $voice = [string]$q['voice']; $text = ([string]$q['text'] -replace '\s+', ' ').Trim(); if ($text.Length -gt 400) { $text = $text.Substring(0, 400) }
                $wav = $null
                if ($voice.StartsWith('piper:')) {
                    # Piper: tempo tutaj, wysokość w przeglądarce (szybsze odtwarzanie podnosi głos, więc mowę wydłużamy o tyle samo)
                    if (-not (Get-Command Get-PiperWav -ErrorAction SilentlyContinue)) { Send-Json $ctx @{ ok = $false; error = 'moduł Piper nie działa' } 503; return }
                    $f = [Math]::Max(0.6, [Math]::Min(1.6, 1 + $pitch / 100.0)); $ls = [Math]::Max(0.5, [Math]::Min(2.0, $f / [Math]::Max(0.5, $rate)))
                    $key = "$voice|$ls|$text"
                    if (-not $script:PiperCache) { $script:PiperCache = [ordered]@{} }
                    if ($script:PiperCache.Contains($key)) { $wav = $script:PiperCache[$key] }
                    else {
                        try { $wav = Get-PiperWav $voice.Substring(6) $text $ls; $script:PiperCache[$key] = $wav; while ($script:PiperCache.Count -gt 30) { $script:PiperCache.RemoveAt(0) } } catch { Log "Głos (Piper, $($voice.Substring(6))): $($_.Exception.Message)" 'Yellow' }
                    }
                    # Piper zawiódł – głos Windows w tym samym języku (i płci, jeśli jest), żeby alert nie był niemy
                    if (-not $wav -and (Get-Command Initialize-Tts -ErrorAction SilentlyContinue)) {
                        Initialize-Tts
                        if ($script:Tts.ready) {
                            $pv = $PiperVoices[$voice.Substring(6)]; $lang = $(if ($pv) { $pv.lang } else { 'pl-PL' }); $gen = $(if ($pv) { $pv.gender } else { '' })
                            $wv = @($script:Tts.voices | Where-Object { $_.lang -like ($lang.Substring(0, 2) + '*') })
                            $pick = @($wv | Where-Object { $_.gender -eq $gen })[0]; if (-not $pick) { $pick = $wv[0] }; if (-not $pick) { $pick = @($script:Tts.voices)[0] }
                            try { $wav = Get-TtsWav $text ([string]$pick.id) $rate $pitch; $ctx.Response.Headers['X-VM-Fallback'] = 'windows' } catch {}
                        }
                    }
                } else {
                    if (-not (Get-Command Initialize-Tts -ErrorAction SilentlyContinue)) { Send-Json $ctx @{ ok = $false; error = 'moduł głosu nie działa' } 503; return }
                    Initialize-Tts
                    if (-not $script:Tts.ready) { Send-Json $ctx @{ ok = $false; error = "głos niedostępny: $($script:Tts.err)" } 503; return }
                    try { $wav = Get-TtsWav $text $voice $rate $pitch } catch { Log "Głos (TTS): $($_.Exception.Message)" 'Yellow' }
                }
                if (-not $wav) { Send-Json $ctx @{ ok = $false; error = 'nie udało się' } 500; return }
                Send-Bytes $ctx $wav 'audio/wav'
            }
            '/window' {
                $ws = $null; try { $ws = Find-ItemWindow ([string]$q['id']) } catch {}
                Send-Json $ctx ([pscustomobject]@{ window = $(if ($ws) { $ws.spec } else { '' }); title = $(if ($ws) { $ws.title } else { '' }) })
            }
            '/icon' {
                $id = [string]$q['id']; $res = $ctx.Response
                $e = $script:GameLib[$id]
                $path = if ($e -and $e.path) { [string]$e.path } else { '' }
                if (-not $path) { $o = @(Get-OtherGames | Where-Object { $_.id -eq $id }) | Select-Object -First 1; if ($o) { $path = $o.exe } }
                $sid = if ($e -and $e.steam) { [string]$e.steam } elseif ($id -match '^steam:(\d+)$') { $Matches[1] } else { '' }
                if ($sid) { $res.StatusCode = 302; $res.RedirectLocation = "/art?id=$sid&k=cover"; $res.OutputStream.Close(); return }
                $png = Get-ExeIconPng $path
                if (-not $png) { $res.StatusCode = 404; $res.OutputStream.Close(); return }
                $res.ContentType = 'image/png'; $res.Headers['Cache-Control'] = 'max-age=86400'; $res.Headers['Access-Control-Allow-Origin'] = '*'
                $res.ContentLength64 = $png.Length; $res.OutputStream.Write($png, 0, $png.Length); $res.OutputStream.Close()
            }
            '/art' {
                $f = Get-SteamArtFile ([string]$q['id']) ([string]$q['k'])
                $res = $ctx.Response
                if (-not $f) {
                    $cdn = @{ logo = 'logo.png'; hero = 'library_hero.jpg'; header = 'header.jpg'; cover = 'library_600x900.jpg' }[[string]$q['k']]
                    if ($cdn -and ([string]$q['id']) -match '^\d+$') { $res.StatusCode = 302; $res.RedirectLocation = "https://cdn.cloudflare.steamstatic.com/steam/apps/$($q['id'])/$cdn" } else { $res.StatusCode = 404 }
                    $res.OutputStream.Close(); return
                }
                $bytes = [IO.File]::ReadAllBytes($f)
                $res.ContentType = if ($f -like '*.png') { 'image/png' } else { 'image/jpeg' }
                $res.Headers['Cache-Control'] = 'max-age=86400'; $res.Headers['Access-Control-Allow-Origin'] = '*'
                $res.ContentLength64 = $bytes.Length; $res.OutputStream.Write($bytes, 0, $bytes.Length); $res.OutputStream.Close()
            }
            '/processes' {
                # kokpit → «Dodaj grę»: programy z otwartym oknem (bez systemowych i bez OBS)
                if (-not (Get-Command Get-OpenWindows -ErrorAction SilentlyContinue)) { Send-Json $ctx @{ ok = $false; error = 'moduł okien nie działa (antywirus?) – zobacz log' } 503; return }
                $list = @(Get-OpenWindows)
                Send-Json $ctx ([pscustomobject]@{ items = $list })
            }
            '/library/launch' {
                $err = Start-LibraryItem ([string]$q['id'])
                Send-Json $ctx @{ ok = -not $err; error = $err }
            }
            '/library/edit' {
                $e = $script:GameLib[[string]$q['id']]
                if (-not $e) { Send-Json $ctx @{ ok = $false } 404; return }
                if ($q.ContainsKey('name') -and ([string]$q['name']).Trim()) { $e.name = ([string]$q['name']).Trim() }
                if ($q.ContainsKey('hidden')) { $e.hidden = ([string]$q['hidden']) -eq '1' }
                $script:LibDirty = $true; Save-Library -Force
                Send-Json $ctx @{ ok = $true }
            }
            '/archive' { Send-Json $ctx (Get-ArchiveList) }
            '/audience' { Send-Json $ctx (Get-Audience) }
            '/archive/stream' {
                $id = [string]$q['id']
                if ($id -notmatch '^[\w-]+$') { Send-Json $ctx @{ ok = $false } 400; return }
                if ($script:Cur -and $script:Cur.id -eq $id) { Send-Json $ctx (Get-StreamSummary $script:Cur); return }
                $f = Join-Path $StreamsDir "$id.json"
                if (Test-Path $f) { Send-Raw $ctx ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)) 'application/json' } else { Send-Json $ctx @{ ok = $false } 404 }
            }
            '/archive/trust' {
                $login = ([string]$q['login']).ToLowerInvariant()
                $rec = $script:Chatters[$login]
                if ($rec) { $rec.trust = ([string]$q['on']) -ne '0'; $script:ChattersDirty = $true; Save-Chatters -Force }
                if ($script:Cur -and $rec -and $rec.trust) { $script:Cur.flagged.Remove($login) }
                Send-Json $ctx @{ ok = [bool]$rec }
            }
            '/archive/export' {
                $id = [string]$q['id']; $fmt = [string]$q['fmt']; if (@('txt', 'srt', 'json') -notcontains $fmt) { $fmt = 'txt' }
                $off = 0; [void][int]::TryParse([string]$q['offset'], [ref]$off)
                if ($id -notmatch '^[\w-]+$') { Send-Json $ctx @{ ok = $false } 400; return }
                $txt = Export-Stream $id $fmt $off
                if ($null -eq $txt) { Send-Json $ctx @{ ok = $false; error = 'brak zapisu' } 404; return }
                $ctx.Response.Headers['Content-Disposition'] = "attachment; filename=czat-$id.$fmt"
                Send-Raw $ctx $txt $(if ($fmt -eq 'json') { 'application/json' } else { 'text/plain' })
            }
            '/twitch/status' { Send-Json $ctx (Get-TwitchStatus) }
            '/bot/act' {
                # automoderacja: kokpit wykrył naruszenie → kara (jedna na wiadomość)
                if (-not (Get-Command Invoke-BotAct -ErrorAction SilentlyContinue)) { Send-Json $ctx @{ ok = $false; error = 'moduł bota nie działa' } 503; return }
                Send-Json $ctx (Invoke-BotAct ([string]$q['msg']) ([string]$q['user']) ([string]$q['name']) ([string]$q['kind']))
            }
            '/bot/log' {
                if (-not (Get-Command Get-BotCfg -ErrorAction SilentlyContinue)) { Send-Json $ctx @{ ok = $false; error = 'moduł bota nie działa' }; return }
                $c = Get-BotCfg
                Send-Json $ctx ([pscustomobject]@{ ok = $true; on = $c.on; prefix = $c.prefix; log = @($script:Bot.log | Select-Object -Last 30) })
            }
            '/bot/test' {
                if (-not (Get-Command Send-ChatMessage -ErrorAction SilentlyContinue)) { Send-Json $ctx @{ ok = $false; error = 'moduł bota nie działa' }; return }
                $okk = Send-ChatMessage ([string]$q['text']); if ($okk) { Add-BotLog ('test: ' + [string]$q['text']) }
                Send-Json $ctx @{ ok = $okk; error = $(if ($okk) { '' } else { (@($script:Bot.log)[-1]).t }) }
            }
            '/ping' {
                # otwarty kokpit melduje się co kilkanaście sekund – kreator nie otwiera wtedy drugiego
                if ([string]$q['who'] -eq 'cockpit') { $script:CockpitSeen = Get-Date }
                Send-Json $ctx @{ ok = $true }
            }
            '/twitch/streamkey' {
                # klucz transmisji do ustawień OBS (kokpit → «Ustaw OBS»); nie trafia do dziennika
                $uid = $script:TW.userId
                if (-not $uid) { Send-Json $ctx @{ ok = $false; error = 'Twitch niepołączony' }; return }
                try {
                    $r = Invoke-Helix 'GET' "streams/key?broadcaster_id=$uid" $null
                    Send-Json $ctx @{ ok = $true; key = [string]@($r.data)[0].stream_key }
                } catch {
                    $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
                    Send-Json $ctx @{ ok = $false; error = "Twitch odmówił ($code)"; relogin = ($code -eq 401 -or $code -eq 403) }
                }
            }
            '/twitch/setup' {
                $cid = [string]$q['clientId']
                if ($cid -eq 'keep') { $cid = $script:TW.clientId }   # «Połącz» bez wpisywania ID ponownie
                try { Start-TwitchLogin $cid; Send-Json $ctx (Get-TwitchStatus) }
                catch { Send-Json $ctx @{ ok = $false; error = (Get-ErrBody $_) } 400 }
            }
            '/twitch/logout' {
                Stop-TwitchSocket
                Remove-Item $TwitchTokFile -ErrorAction SilentlyContinue
                $script:TW.token = $null; $script:TW.user = ''; $script:TW.status = $(if ($script:TW.clientId) { 'need-login' } else { 'off' })
                Log 'Twitch: wylogowano' 'Yellow'
                Send-Json $ctx (Get-TwitchStatus)
            }
            '/add' {
                $exe = ([string]$q['exe']).Trim().ToLowerInvariant(); $name = ([string]$q['name']).Trim()
                if (-not $exe -or -not $name -or $exe -match '[=|\r\n]' -or $name -match '[\r\n]') { Send-Json $ctx @{ ok = $false; error = 'exe i name są wymagane' } 400; return }
                Add-CustomLine "$exe = $name"
                Log "Dodano do my-games.txt: $exe = $name" 'Green'
                Update-State
                Send-Json $ctx @{ ok = $true }
            }
            '/ignore' {
                $exe = ([string]$q['exe']).Trim().ToLowerInvariant()
                if (-not $exe -or $exe -match '[=|\r\n]') { Send-Json $ctx @{ ok = $false; error = 'exe jest wymagane' } 400; return }
                Add-CustomLine "!$exe"
                Log "Ignorowane od teraz: $exe" 'Yellow'
                Update-State
                Send-Json $ctx @{ ok = $true }
            }
            '' { Send-Json $ctx @{ ok = $true; app = 'Vincent-Media game detector'; endpoints = @('/game', '/add?exe=&name=', '/ignore?exe=') } }
            default { Send-Json $ctx @{ ok = $false; error = 'not found' } 404 }
        }
    } catch {
        # przeglądarka zamknęła połączenie, zanim przyszła odpowiedź (odświeżenie, zamknięta karta) – nic złego, nie śmiecimy w dzienniku
        $m = $_.Exception.Message
        if ($m -notmatch 'ContentLength64|po przesłaniu odpowiedzi|after the response|nazwa sieciowa|network name|zamknięte przez zdalnego|forcibly closed|aborted|przerwan') {
            Log "Błąd zapytania: $m" 'Red'
            try { Send-Json $ctx @{ ok = $false; error = $m } 500 } catch {}
        }
    }
}
