#Requires -Version 5.1
<#
  Vincent-Media – kreator startu (skrót «Vincent-Media» z ikoną).
  Krok po kroku, z animacją: najnowsza wersja → wszystkie pliki → nic nie blokuje → GameRadar → OBS → kokpit.
  Coś nie gra → przy kroku jest przycisk, który to naprawia albo pokazuje, gdzie kliknąć.
  Sprawdzanie idzie w osobnym wątku, okno cały czas reaguje.
#>
param([switch]$NoCockpit)

$ErrorActionPreference = 'Stop'
$App = Split-Path $PSScriptRoot -Parent
$Cockpit = 'https://v-cancrosa.github.io/Vincent-Media/obs-game-overlay/site/live.html'

# jedna kopia naraz
$mutex = New-Object Threading.Mutex($false, 'Local\VincentMediaLauncher')
if (-not $mutex.WaitOne(0)) { exit 0 }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$STEPS = @(
    @{ id = 'update'; title = 'Najnowsza wersja' },
    @{ id = 'files'; title = 'Wszystkie pliki na miejscu' },
    @{ id = 'blocks'; title = 'Nic nie blokuje' },
    @{ id = 'radar'; title = 'GameRadar' },
    @{ id = 'obs'; title = 'OBS Studio' },
    @{ id = 'cockpit'; title = 'Kokpit' },
    @{ id = 'voices'; title = 'Głosy postaci (Piper)' }
)
$sync = [hashtable]::Synchronized(@{ steps = @(); finished = $false; relaunch = $false; cockpit = (-not $NoCockpit); url = $Cockpit; version = '' })
function Reset-Steps { $sync.steps = @($STEPS | ForEach-Object { [hashtable]::Synchronized(@{ id = $_.id; title = $_.title; state = 'wait'; detail = ''; action = ''; rev = 0 }) }); $sync.finished = $false }
Reset-Steps

# ---------------------------------------------------------------- praca w tle
$Work = {
    param($sync, $App)
    $ErrorActionPreference = 'Stop'
    $Det = Join-Path $App 'detector'; $Data = Join-Path $Det 'data'; $Port = 7777
    function Set-Step([int]$i, [string]$state, [string]$detail, [string]$action = '') { $s = $sync.steps[$i]; $s.state = $state; $s.detail = $detail; $s.action = $action; $s.rev++ }
    # GameRadar: zapytanie z pominięciem proxy (ustawienia proxy Windows potrafią przechwycić «localhost»), po kolei kilka adresów
    $script:RadarErr = ''
    function Get-Radar {
        foreach ($h in 'localhost', '127.0.0.1', '[::1]') {
            try {
                $rq = [Net.HttpWebRequest]::Create("http://${h}:$Port/update/status"); $rq.Proxy = $null; $rq.Timeout = 4000; $rq.ReadWriteTimeout = 4000
                $rs = $rq.GetResponse(); try { $txt = (New-Object IO.StreamReader($rs.GetResponseStream(), [Text.Encoding]::UTF8)).ReadToEnd() } finally { $rs.Close() }
                return ($txt | ConvertFrom-Json)
            } catch { $script:RadarErr = $_.Exception.Message -replace '^Exception calling "\w+" with "\d+" argument\(s\): ', '' }
        }
        return $null
    }
    # zapytanie z kluczem tego komputera (adresy GameRadara dla zaufanych)
    function Get-RadarJson([string]$path) {
        $key = ''; try { $key = ([IO.File]::ReadAllText((Join-Path $Data 'local-key.txt'))).Trim() } catch {}
        try {
            $rq = [Net.HttpWebRequest]::Create("http://localhost:$Port$path"); $rq.Proxy = $null; $rq.Timeout = 6000; $rq.Headers.Add('X-VM-Key', $key)
            $rs = $rq.GetResponse(); try { return ((New-Object IO.StreamReader($rs.GetResponseStream(), [Text.Encoding]::UTF8)).ReadToEnd() | ConvertFrom-Json) } finally { $rs.Close() }
        } catch { return $null }
    }
    # GameRadar działa? – po jego blokadzie «jedna kopia naraz» (niezależnie od sieci)
    function Test-RadarRunning {
        $m = $null
        try { $m = [Threading.Mutex]::OpenExisting('Local\VincentMediaDetector'); return $true } catch { return $false } finally { if ($m) { $m.Dispose() } }
    }
    function Find-Obs {
        foreach ($k in 'HKLM:\SOFTWARE\OBS Studio', 'HKLM:\SOFTWARE\WOW6432Node\OBS Studio') {
            try { $d = (Get-ItemProperty $k -ErrorAction Stop).'(default)'; if ($d) { $e = Join-Path $d 'bin\64bit\obs64.exe'; if (Test-Path $e) { return $e } } } catch {}
        }
        foreach ($d in @("$env:ProgramFiles\obs-studio", "${env:ProgramFiles(x86)}\obs-studio")) { $e = Join-Path $d 'bin\64bit\obs64.exe'; if (Test-Path $e) { return $e } }
        return ''
    }
    $i = 0
    try {
        . (Join-Path $App 'update.ps1') -Library
        $sync.version = Get-VMLocalVersion $App

        # 1. najnowsza wersja
        $i = 0; Set-Step 0 'run' 'Sprawdzam na GitHubie…'
        $local = Get-VMLocalVersion $App; $remote = $null
        try { $remote = Get-VMRemoteInfo 8 } catch {}
        $st = Get-Radar
        if (-not $remote) { Set-Step 0 'warn' "Brak połączenia z GitHubem – zostaje wersja $local" }
        elseif (-not (Test-VMNewer ([string]$remote.version) $local)) { Set-Step 0 'ok' "Wersja $local – najnowsza" }
        elseif ($st -and $st.paused) { Set-Step 0 'warn' "Jest $($remote.version), ale trwa $($st.pausedWhy) – zaktualizuję po zakończeniu" }
        else {
            Set-Step 0 'run' "Pobieram wersję $($remote.version)…"
            $before = Get-VMHash (Join-Path $App 'launcher\launcher.ps1')
            $n = Install-VMFiles $App
            $sync.version = Get-VMLocalVersion $App
            Set-Step 0 'ok' "Zaktualizowano do $($remote.version) ($n plików)"
            if ((Get-VMHash (Join-Path $App 'launcher\launcher.ps1')) -ne $before) { $sync.relaunch = $true; return }
        }

        # 2. pliki
        $i = 1; Set-Step 1 'run' 'Porównuję ze spisem plików…'
        $t = Test-VMFiles $App
        if ($t.nomanifest) { Set-Step 1 'warn' 'Brak spisu plików – sprawdzę przy następnej aktualizacji' }
        elseif ($t.ok) { Set-Step 1 'ok' "$($t.total) plików – wszystkie na miejscu" }
        else {
            $bad = $t.missing.Count + $t.changed.Count
            Set-Step 1 'run' "Naprawiam $bad plików…"
            try { [void](Install-VMFiles $App) } catch {}
            $t = Test-VMFiles $App
            if ($t.ok) { Set-Step 1 'ok' "Naprawione – $($t.total) plików na miejscu" }
            else { Set-Step 1 'err' ("Brakuje albo uszkodzone: " + ((@($t.missing) + @($t.changed) | Select-Object -First 3) -join ', ') + ' – potrzebny internet') 'retry' }
        }
        try { Update-VMLayout $App } catch {}

        # 3. blokady
        $i = 2; Set-Step 2 'run' 'Sprawdzam blokady Windows…'
        $notes = New-Object Collections.ArrayList
        $unb = 0
        foreach ($f in Get-ChildItem -Path $App -Recurse -File -Include '*.ps1', '*.vbs', '*.bat', '*.html', '*.js' -ErrorAction SilentlyContinue) {
            if (Get-Item -LiteralPath $f.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue) { try { Unblock-File -LiteralPath $f.FullName; $unb++ } catch {} }
        }
        if ($unb) { [void]$notes.Add("odblokowano $unb plików z internetu") }
        # znacznik «zamknięte przyciskiem w serwisie» – start z tego programu to Twoja decyzja, więc go zdejmujemy
        Remove-Item (Join-Path $Data 'stopped.flag') -Force -ErrorAction SilentlyContinue
        # błąd składni w skryptach (np. uszkodzony plik)
        $syntax = ''
        foreach ($ps in @(Get-ChildItem -Path $Det -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
            $tk = $null; $er = $null; [void][Management.Automation.Language.Parser]::ParseFile($ps.FullName, [ref]$tk, [ref]$er)
            if ($er -and $er.Count) { $syntax = "$($ps.Name): wiersz $($er[0].Extent.StartLineNumber) – $($er[0].Message)"; break }
        }
        $port = ''
        if (-not (Get-Radar)) {
            $c = New-Object Net.Sockets.TcpClient
            try { if ($c.ConnectAsync('127.0.0.1', $Port).Wait(400) -and $c.Connected) { $port = "port $Port zajmuje inny program" } } catch {} finally { $c.Close() }
        }
        if ($syntax) { Set-Step 2 'err' "Błąd w pliku $syntax" 'retry' }
        elseif ($port) { Set-Step 2 'warn' ($port + ' – GameRadar może nie ruszyć') }
        else { Set-Step 2 'ok' $(if ($notes.Count) { 'Czysto (' + ($notes -join ', ') + ')' } else { 'Czysto' }) }

        # 4. GameRadar
        $i = 3; Set-Step 3 'run' 'Sprawdzam, czy działa…'
        $st = Get-Radar
        if (-not $st -and (Test-RadarRunning)) {
            # działa, ale nie odpowiada: najczęściej właśnie przechodzi na nową wersję albo się uruchamia – chwilę czekamy
            for ($k = 0; $k -lt 25 -and -not $st; $k++) { Set-Step 3 'run' 'Uruchamia się – czekam…'; Start-Sleep -Seconds 1; $st = Get-Radar }
        }
        if (-not $st -and (Test-RadarRunning)) {
            # działa, ale kreator nie może się z nim połączyć – nie uruchamiamy drugiej kopii
            Set-Step 3 'warn' ("Działa, ale kreator nie może się z nim połączyć: $($script:RadarErr)") 'log'
            $st = 'running'
        }
        if ($st -and $st -isnot [string] -and (Test-VMNewer (Get-VMLocalVersion $App) ([string]$st.installed))) {
            Set-Step 3 'run' 'Działa stara wersja – uruchamiam ponownie…'
            $key = ''; try { $key = ([IO.File]::ReadAllText((Join-Path $Data 'local-key.txt'))).Trim() } catch {}
            try { [void](Invoke-RestMethod -UseBasicParsing -TimeoutSec 3 -Uri "http://localhost:$Port/restart" -Headers @{ 'X-VM-Key' = $key }) } catch {}
            Start-Sleep -Seconds 3; $st = $null
        }
        if (-not $st) {
            Set-Step 3 'run' 'Uruchamiam w tle…'
            $errFile = Join-Path $Data 'start-error.txt'
            New-Item -ItemType Directory -Force -Path $Data | Out-Null
            Remove-Item $errFile -Force -ErrorAction SilentlyContinue
            $dp = (Join-Path $Det 'detector.ps1').Replace("'", "''"); $ep = $errFile.Replace("'", "''")
            $cmd = "try { & '$dp' -Hidden; [IO.File]::WriteAllText('$ep', ('exit | GameRadar zakończył się sam, kod ' + `$LASTEXITCODE)) } catch { [IO.File]::WriteAllText('$ep', (`$_.FullyQualifiedErrorId + ' | ' + `$_.Exception.Message)) }"
            $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command', $cmd) -WindowStyle Hidden -PassThru
            # czekamy, dopóki GameRadar żyje i coś robi (pierwsze uruchomienie potrafi trwać), najwyżej 90 s
            $lg = Join-Path $Data 'detector.log'; $t0 = Get-Date
            while (((Get-Date) - $t0).TotalSeconds -lt 90) {
                Start-Sleep -Milliseconds 600
                $st = Get-Radar; if ($st) { break }
                # nasza kopia się wycofała, bo GameRadar już działa (np. właśnie przechodzi na nową wersję) – czekamy, aż odpowie
                if ($p.HasExited -and (Test-RadarRunning)) {
                    for ($k = 0; $k -lt 40 -and -not $st; $k++) { Set-Step 3 'run' 'Uruchamia się w nowej wersji – czekam…'; Start-Sleep -Seconds 1; $st = Get-Radar }
                    if (-not $st) { $st = 'running' }
                    break
                }
                if ($p.HasExited) { Start-Sleep -Milliseconds 400; break }
                $last = ''; try { $last = [string](Get-Content $lg -Tail 1 -Encoding UTF8 -ErrorAction Stop) } catch {}
                if ($last) { Set-Step 3 'run' ('Uruchamiam… ' + ($last -replace '^[\d-]*\s*\[[\d:]+\]\s*', '')) }
            }
            if (-not $st) {
                $why = ''; if (Test-Path $errFile) { $why = [IO.File]::ReadAllText($errFile) }
                $tail = @(); if (Test-Path $lg) { $tail = @(Get-Content $lg -Tail 40 -Encoding UTF8 | Where-Object { [string]$_ -match '\[\d\d:\d\d:\d\d\]' }) }
                $hit = @($tail | Where-Object { $_ -match 'Nie mog|nie wczytany|zablokował|ParserError' } | Select-Object -Last 1)
                if (-not $why -or $why -like 'exit |*') { if ($hit) { $why = [string]$hit[0] } elseif ($why) { $why = $why.Substring(7) + $(if ($tail) { ' · ostatnio: ' + [string]$tail[-1] } else { ' · dziennik pusty' }) } }
                if ($why -match 'Malicious') { Set-Step 3 'err' 'Antywirus zablokował GameRadar (fałszywy alarm) – zobacz Historię ochrony' 'defender' }
                elseif ($why -match 'port') { Set-Step 3 'err' "Port $Port zajęty – zamknij drugą kopię GameRadara albo program na tym porcie" 'retry' }
                elseif ($why) { Set-Step 3 'err' ([string]$why).Trim() 'log' }
                else { Set-Step 3 'err' ('Nie odpowiada' + $(if ($tail) { ' · ostatnio: ' + [string]$tail[-1] } else { ' · dziennik pusty' })) 'log' }
                $sync.finished = $true; return
            }
        }
        if ($st -is [string]) { if ($sync.steps[3].state -ne 'warn') { Set-Step 3 'warn' ("Działa, ale kreator nie może się z nim połączyć: $($script:RadarErr)") 'log' } }
        else { Set-Step 3 'ok' "Działa – wersja $($st.installed)" }

        # 5. OBS
        $i = 4
        # motyw wyglądu OBS (przed uruchomieniem OBS – wtedy można go wybrać w ustawieniach OBS)
        $theme = ''; try { $theme = Install-VMObsTheme $App } catch { $theme = '' }
        if (Get-Process -Name obs64, obs32 -ErrorAction SilentlyContinue) { Set-Step 4 'ok' ('Już działa' + $(if ($theme) { ' · ' + $theme } else { '' })) }
        else {
            $obs = Find-Obs
            if (-not $obs) { Set-Step 4 'warn' 'Nie znalazłem OBS Studio na tym komputerze' 'obsdl' }
            else {
                Set-Step 4 'run' 'Uruchamiam…'
                Start-Process -FilePath $obs -WorkingDirectory (Split-Path $obs) -WindowStyle Minimized     # OBS w tle – stream prowadzisz z kokpitu
                $ok = $false
                for ($k = 0; $k -lt 40; $k++) { Start-Sleep -Milliseconds 500; if (Get-Process -Name obs64 -ErrorAction SilentlyContinue) { $ok = $true; break } }
                if ($ok) { Set-Step 4 'ok' ('Uruchomiony' + $(if ($theme) { ' · ' + $theme } else { '' })) } else { Set-Step 4 'warn' 'Nie wystartował w 20 s – uruchom go ręcznie' }
            }
        }

        # 6. kokpit
        $i = 5
        # kokpit: tylko gdy nie jest już otwarty (otwarty kokpit co kilkanaście sekund melduje się GameRadarowi)
        $seen = $null; if ($st -isnot [string] -and $st) { $u = Get-Radar; if ($u -and $u.PSObject.Properties['cockpitAgo']) { $seen = [int]$u.cockpitAgo } }
        if ($sync.cockpit -and $null -ne $seen -and $seen -ge 0 -and $seen -lt 130) { Set-Step 5 'ok' 'Już otwarty w przeglądarce – nie otwieram drugiego' }
        elseif ($sync.cockpit) { Set-Step 5 'run' 'Otwieram w przeglądarce…'; Start-Process $sync.url; Start-Sleep -Milliseconds 600; Set-Step 5 'ok' 'Otwarty – stream prowadzisz stamtąd' }
        else { Set-Step 5 'skip' 'Pominięty' }

        # 7. głosy Piper (domyślne głosy postaci) – pobierane raz, w GameRadarze w tle
        $i = 6
        if ($st -is [string]) { Set-Step 6 'warn' 'Pominięte – kreator nie łączy się z GameRadarem' }
        else {
            Set-Step 6 'run' 'Sprawdzam…'
            $pp = Get-RadarJson '/tts/piper'
            $need = { param($x) @($x.voices | Where-Object { $_.def -and -not $_.installed }).Count -gt 0 -or -not $x.exe }
            if (-not $pp -or -not $pp.voices) { Set-Step 6 'warn' 'Moduł Piper nie odpowiada – postacie mówią głosami Windows' 'log' }
            elseif (-not (& $need $pp) -and -not $pp.busy) { Set-Step 6 'ok' ('Gotowe: ' + ((@($pp.voices | Where-Object { $_.installed }) | ForEach-Object { $_.name }) -join ', ')) }
            else {
                if (-not $pp.busy) { $pp = Get-RadarJson '/tts/piper?install=1' }
                $t0 = Get-Date
                while ($pp -and $pp.busy -and ((Get-Date) - $t0).TotalMinutes -lt 20) {
                    Set-Step 6 'run' ("Pobieram $($pp.step)… $($pp.pct)% · możesz zamknąć okno, pobieranie trwa dalej")
                    Start-Sleep -Seconds 1; $pp = Get-RadarJson '/tts/piper'
                }
                if (-not $pp) { Set-Step 6 'warn' 'GameRadar przestał odpowiadać w trakcie pobierania' 'retry' }
                elseif ($pp.error) { Set-Step 6 'warn' "Nie udało się pobrać: $($pp.error)" 'retry' }
                elseif ($pp.busy) { Set-Step 6 'warn' 'Pobieranie jeszcze trwa w tle' }
                else { Set-Step 6 'ok' ('Pobrane: ' + ((@($pp.voices | Where-Object { $_.installed }) | ForEach-Object { $_.name }) -join ', ')) }
            }
        }
    } catch {
        Set-Step $i 'err' $_.Exception.Message 'retry'
    }
    $sync.finished = $true
}
$script:WorkPS = $null
function Start-Work {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($Work).AddArgument($sync).AddArgument($App)
    [void]$ps.BeginInvoke(); $script:WorkPS = $ps
}

# ---------------------------------------------------------------- okno
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Vincent-Media" Width="560" SizeToContent="Height" WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize" FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True">
  <Border x:Name="Card" Margin="18" CornerRadius="20" BorderThickness="1" BorderBrush="#2A2D38" Padding="26,22,26,22">
    <Border.Background>
      <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#191A22" Offset="0"/><GradientStop Color="#0E0F13" Offset="1"/></LinearGradientBrush>
    </Border.Background>
    <Border.Effect><DropShadowEffect BlurRadius="34" ShadowDepth="6" Opacity="0.55" Color="#000000"/></Border.Effect>
    <StackPanel>
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Image x:Name="Logo" Width="58" Height="58" Margin="0,0,16,0" RenderTransformOrigin="0.5,0.5"><Image.RenderTransform><ScaleTransform x:Name="LogoScale" ScaleX="1" ScaleY="1"/></Image.RenderTransform></Image>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock Text="Vincent-Media" Foreground="#F2F3F7" FontSize="23" FontWeight="Bold"/>
          <TextBlock x:Name="Sub" Text="Sprawdzam i uruchamiam wszystko" Foreground="#8F93A3" FontSize="13" Margin="0,2,0,0"/>
        </StackPanel>
        <Button x:Name="BClose" Grid.Column="2" Content="✕" Width="32" Height="32" VerticalAlignment="Top" Foreground="#8F93A3" Background="Transparent" BorderThickness="0" FontSize="14" Cursor="Hand" ToolTip="Zamknij"/>
      </Grid>
      <Border Height="4" CornerRadius="2" Background="#22252F" Margin="0,20,0,8">
        <Border x:Name="Bar" HorizontalAlignment="Left" Width="0" CornerRadius="2">
          <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#7C5CFF" Offset="0"/><GradientStop Color="#00E1FF" Offset="1"/></LinearGradientBrush></Border.Background>
        </Border>
      </Border>
      <StackPanel x:Name="Steps" Margin="0,8,0,0"/>
      <Grid Margin="0,18,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="Status" Text="" Foreground="#8F93A3" FontSize="13" VerticalAlignment="Center" TextWrapping="Wrap"/>
        <Button x:Name="BCockpit" Grid.Column="1" Content="Otwórz kokpit" Margin="10,0,0,0" Padding="16,8" Foreground="White" Background="#7C5CFF" BorderThickness="0" FontWeight="SemiBold" Cursor="Hand"/>
        <Button x:Name="BDone" Grid.Column="2" Content="Zamknij" Margin="8,0,0,0" Padding="16,8" Foreground="#E9EAF0" Background="#22252F" BorderThickness="0" Cursor="Hand"/>
      </Grid>
    </StackPanel>
  </Border>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$ui = @{}; foreach ($n in 'Card', 'Logo', 'LogoScale', 'Sub', 'BClose', 'Bar', 'Steps', 'Status', 'BCockpit', 'BDone') { $ui[$n] = $win.FindName($n) }
$ico = Join-Path $PSScriptRoot 'vincent-media.ico'; $png = Join-Path $PSScriptRoot 'logo.png'
try { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $ico)) } catch {}
try { $ui.Logo.Source = New-Object Windows.Media.Imaging.BitmapImage (New-Object Uri $png) } catch {}
$win.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })

# zaokrąglone przyciski
foreach ($b in $ui.BCockpit, $ui.BDone, $ui.BClose) {
    $tpl = [Windows.Markup.XamlReader]::Parse('<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Border x:Name="b" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" CornerRadius="10" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger></ControlTemplate.Triggers></ControlTemplate>')
    $b.Template = $tpl
}

$Brush = { param($hex) New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex)) }
function New-Anim([double]$from, [double]$to, [int]$ms, [switch]$Forever) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation($from, $to, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($ms))))
    if ($Forever) { $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever }
    else { $e = New-Object Windows.Media.Animation.CubicEase; $e.EasingMode = 'EaseOut'; $a.EasingFunction = $e }
    return $a
}

# wiersze kroków: kółko (czeka) → kręcący się łuk (trwa) → rysowany ✓ / ! / ✕
$rows = @()
function Build-Rows {
    $ui.Steps.Children.Clear(); $script:rows = @()
    $k = 0
    foreach ($s in $sync.steps) {
        $g = New-Object Windows.Controls.Grid; $g.Margin = '0,7,0,7'
        foreach ($w in 36, 0, -1) { $c = New-Object Windows.Controls.ColumnDefinition; $c.Width = $(if ($w -eq 0) { New-Object Windows.GridLength(1, 'Star') } elseif ($w -lt 0) { [Windows.GridLength]::Auto } else { New-Object Windows.GridLength($w) }); $g.ColumnDefinitions.Add($c) }
        $cv = New-Object Windows.Controls.Canvas; $cv.Width = 26; $cv.Height = 26; $cv.VerticalAlignment = 'Top'; $cv.Margin = '0,1,0,0'
        $ring = New-Object Windows.Shapes.Ellipse; $ring.Width = 26; $ring.Height = 26; $ring.StrokeThickness = 2; $ring.Stroke = & $Brush '#2A2D38'; $ring.Fill = & $Brush '#14151B'
        $spin = New-Object Windows.Shapes.Path; $spin.Data = [Windows.Media.Geometry]::Parse('M13,2 A11,11 0 0 1 24,13'); $spin.StrokeThickness = 2.6; $spin.StrokeStartLineCap = 'Round'; $spin.StrokeEndLineCap = 'Round'
        $spin.Stroke = & $Brush '#00E1FF'; $rt = New-Object Windows.Media.RotateTransform(0, 13, 13); $spin.RenderTransform = $rt; $spin.Visibility = 'Hidden'
        $mark = New-Object Windows.Shapes.Path; $mark.StrokeThickness = 2.6; $mark.StrokeStartLineCap = 'Round'; $mark.StrokeEndLineCap = 'Round'; $mark.StrokeLineJoin = 'Round'; $mark.Visibility = 'Hidden'
        [void]$cv.Children.Add($ring); [void]$cv.Children.Add($spin); [void]$cv.Children.Add($mark)
        $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1)
        $t1 = New-Object Windows.Controls.TextBlock; $t1.Text = $s.title; $t1.FontSize = 15; $t1.FontWeight = [Windows.FontWeights]::SemiBold; $t1.Foreground = & $Brush '#6B6F7E'
        $t2 = New-Object Windows.Controls.TextBlock; $t2.FontSize = 12.5; $t2.Foreground = & $Brush '#8F93A3'; $t2.TextWrapping = 'Wrap'; $t2.Margin = '0,2,0,0'
        [void]$sp.Children.Add($t1); [void]$sp.Children.Add($t2)
        $btn = New-Object Windows.Controls.Button; $btn.Visibility = 'Collapsed'; $btn.Padding = '12,5'; $btn.Margin = '10,0,0,0'; $btn.VerticalAlignment = 'Top'; $btn.Cursor = 'Hand'
        $btn.Foreground = & $Brush '#FFD9DD'; $btn.Background = & $Brush '#3A1D24'; $btn.BorderThickness = 0; $btn.Template = $ui.BDone.Template
        [Windows.Controls.Grid]::SetColumn($btn, 2)
        $btn.Add_Click({ param($sender) Invoke-Action ([string]$sender.Tag) })
        [void]$g.Children.Add($cv); [void]$g.Children.Add($sp); [void]$g.Children.Add($btn)
        # wejście wiersza: z dołu, po kolei
        $tt = New-Object Windows.Media.TranslateTransform(0, 10); $g.RenderTransform = $tt; $g.Opacity = 0
        $a1 = New-Anim 0 1 380; $a1.BeginTime = [TimeSpan]::FromMilliseconds(90 * $k); $g.BeginAnimation([Windows.UIElement]::OpacityProperty, $a1)
        $a2 = New-Anim 10 0 420; $a2.BeginTime = [TimeSpan]::FromMilliseconds(90 * $k); $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a2)
        [void]$ui.Steps.Children.Add($g)
        $script:rows += @{ step = $s; rev = -1; ring = $ring; spin = $spin; rot = $rt; mark = $mark; title = $t1; detail = $t2; btn = $btn }
        $k++
    }
}
$ACTIONS = @{ retry = 'Spróbuj ponownie'; defender = 'Historia ochrony'; obsdl = 'Pobierz OBS'; log = 'Dziennik' }
function Invoke-Action([string]$a) {
    switch ($a) {
        'retry' { Reset-Steps; $script:closeAt = $null; $ui.Status.Text = ''; Build-Rows; Start-Work }
        'defender' { try { Start-Process 'windowsdefender://threat' } catch {} }
        'obsdl' { Start-Process 'https://obsproject.com/download' }
        'log' { Start-Process ($Cockpit -replace 'live\.html$', 'log.html') }
    }
}
function Show-Row($r) {
    $s = $r.step; $r.rev = $s.rev
    $r.detail.Text = [string]$s.detail
    $colors = @{ wait = '#6B6F7E'; run = '#F2F3F7'; ok = '#F2F3F7'; warn = '#F2F3F7'; err = '#FFD9DD'; skip = '#6B6F7E' }
    $r.title.Foreground = & $Brush $colors[$s.state]
    if ($s.state -eq 'run') {
        if ($r.spin.Visibility -ne 'Visible') { $r.spin.Visibility = 'Visible'; $r.rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, (New-Anim 0 360 900 -Forever)) }
        $r.mark.Visibility = 'Hidden'; $r.ring.Stroke = & $Brush '#2A2D38'
    } else {
        $r.spin.Visibility = 'Hidden'; $r.rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null)
    }
    $kind = @{ ok = @('M8,13.5 L11.5,17 L18.5,9.5', '#3DDC84'); warn = @('M13,7.5 L13,14.5 M13,18.3 L13,18.4', '#FFB347'); err = @('M9,9 L17,17 M17,9 L9,17', '#FF4D5E'); skip = @('M8.5,13 L17.5,13', '#6B6F7E') }[$s.state]
    if ($kind) {
        $r.mark.Data = [Windows.Media.Geometry]::Parse($kind[0]); $r.mark.Stroke = & $Brush $kind[1]; $r.ring.Stroke = & $Brush $kind[1]
        $r.mark.StrokeDashArray = [Windows.Media.DoubleCollection]::Parse('8 8'); $r.mark.Visibility = 'Visible'
        $r.mark.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, (New-Anim 8 0 420))
        $pop = New-Anim 0.6 1 380; $sc = New-Object Windows.Media.ScaleTransform(1, 1, 13, 13); $r.ring.RenderTransform = $sc
        $sc.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $pop); $sc.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $pop)
    }
    if ($s.action -and $ACTIONS[$s.action]) { $r.btn.Content = $ACTIONS[$s.action]; $r.btn.Tag = $s.action; $r.btn.Visibility = 'Visible' } else { $r.btn.Visibility = 'Collapsed' }
}

$script:closing = $false; $script:closeAt = $null; $script:barW = 0
$timer = New-Object Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromMilliseconds(90)
$timer.Add_Tick({
    if ($sync.version) { $ui.Sub.Text = "Wersja $($sync.version) · sprawdzam i uruchamiam wszystko" }
    foreach ($r in $script:rows) { if ($r.rev -ne $r.step.rev) { Show-Row $r } }
    $done = @($sync.steps | Where-Object { $_.state -in 'ok', 'warn', 'skip', 'err' }).Count
    $w = [Math]::Round(($ui.Bar.Parent.ActualWidth) * $done / $sync.steps.Count)
    if ($w -ne $script:barW) { $ui.Bar.BeginAnimation([Windows.FrameworkElement]::WidthProperty, (New-Anim $script:barW $w 450)); $script:barW = $w }
    if ($sync.relaunch) {
        $timer.Stop(); $mutex.ReleaseMutex()
        Start-Process wscript.exe -ArgumentList ('"' + (Join-Path $PSScriptRoot 'launcher.vbs') + '"'); $win.Close(); return
    }
    if ($sync.finished -and -not $script:closeAt -and -not $script:closing) {
        $bad = @($sync.steps | Where-Object { $_.state -eq 'err' }).Count; $warn = @($sync.steps | Where-Object { $_.state -eq 'warn' }).Count
        if ($bad) { $ui.Status.Text = 'Coś wymaga uwagi – przycisk przy kroku pomoże.'; $ui.Status.Foreground = & $Brush '#FFB4BC' }
        elseif ($warn) { $ui.Status.Text = 'Gotowe, z uwagami powyżej.'; $ui.Status.Foreground = & $Brush '#FFD39A' }
        else {
            $ui.Status.Text = 'Wszystko gotowe – miłego streamu!'; $ui.Status.Foreground = & $Brush '#9FF0C4'
            $script:closeAt = (Get-Date).AddSeconds(3.5)
            $p = New-Anim 1 1.08 260; $p.AutoReverse = $true; if ($ui.LogoScale) { $ui.LogoScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $p); $ui.LogoScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $p) }
        }
    }
    if ($script:closeAt -and (Get-Date) -gt $script:closeAt -and -not $script:closing) { Close-Window }
})
function Close-Window {
    if ($script:closing) { return }; $script:closing = $true
    $a = New-Anim 1 0 260; $a.Add_Completed({ $timer.Stop(); $win.Close() }); $win.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
}
$ui.BClose.Add_Click({ Close-Window })
$ui.BDone.Add_Click({ Close-Window })
$ui.BCockpit.Add_Click({ Start-Process $Cockpit })
# najechanie myszą zatrzymuje automatyczne zamknięcie
$win.Add_MouseEnter({ if ($script:closeAt) { $script:closeAt = $null; $ui.Status.Text = 'Wszystko gotowe – miłego streamu!' } })
$win.Add_Loaded({
    $win.Opacity = 0; $win.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Anim 0 1 300))
    Build-Rows; Start-Work; $timer.Start()
})
[void]$win.ShowDialog()
try { $mutex.ReleaseMutex() } catch {}
