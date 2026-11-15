#Requires -Version 5.1
# Moduł GameRadara: głosy neuronowe Piper (domyślny głos postaci)
# Wczytywany przez detector.ps1 (dot-source). Gdy antywirus albo błąd go zablokuje, reszta GameRadara działa dalej.
#
# Piper (https://github.com/rhasspy/piper, MIT) – synteza mowy na Twoim komputerze, bez internetu.
# Program i głosy pobierane raz (za zgodą – kreator startu albo strona «Głos postaci») do detector\data\piper.
# Głosy: https://huggingface.co/rhasspy/piper-voices – karty modeli (MODEL_CARD) mówią o licencjach zbiorów danych.

$PiperDir = Join-Path $DataDir 'piper'
$PiperZip = 'https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip'
$PiperHF = 'https://huggingface.co/rhasspy/piper-voices/resolve/main'
$PiperVoices = [ordered]@{
    'pl_PL-gosia-medium'     = @{ name = 'Gosia'; lang = 'pl-PL'; gender = 'female'; path = 'pl/pl_PL/gosia/medium'; def = $true }
    'pl_PL-darkman-medium'   = @{ name = 'Darkman'; lang = 'pl-PL'; gender = 'male'; path = 'pl/pl_PL/darkman/medium'; def = $true }
    'pl_PL-mc_speech-medium' = @{ name = 'MC Speech'; lang = 'pl-PL'; gender = 'male'; path = 'pl/pl_PL/mc_speech/medium'; def = $false }
    'en_US-lessac-medium'    = @{ name = 'Lessac'; lang = 'en-US'; gender = 'female'; path = 'en/en_US/lessac/medium'; def = $true }
    'en_US-ryan-medium'      = @{ name = 'Ryan'; lang = 'en-US'; gender = 'male'; path = 'en/en_US/ryan/medium'; def = $true }
}
$script:Piper = [hashtable]::Synchronized(@{ busy = $false; pct = 0; step = ''; error = ''; ps = $null })

function Get-PiperExe { $e = Join-Path $PiperDir 'piper\piper.exe'; if (Test-Path $e) { return $e } else { return '' } }
function Get-PiperInstalled {
    $vd = Join-Path $PiperDir 'voices'
    # model to kilkadziesiąt MB – mały plik to strona z błędem zamiast modelu (nieudane pobieranie): nie liczy się, pobierze się od nowa
    return @($PiperVoices.Keys | Where-Object {
        $o = Join-Path $vd "$_.onnx"; $j = Join-Path $vd "$_.onnx.json"
        (Test-Path $o) -and (Test-Path $j) -and (Get-Item $o).Length -gt 5MB -and (Get-Item $j).Length -gt 200 -and ([IO.File]::ReadAllText($j).TrimStart().StartsWith([string][char]123))
    })
}
function Get-PiperStatus {
    $inst = Get-PiperInstalled
    return [pscustomobject]@{
        ok = [bool](Get-PiperExe) -and $inst.Count -gt 0; exe = [bool](Get-PiperExe); busy = [bool]$script:Piper.busy; pct = [int]$script:Piper.pct
        step = [string]$script:Piper.step; error = [string]$script:Piper.error
        voices = @($PiperVoices.Keys | ForEach-Object { $v = $PiperVoices[$_]; [pscustomobject]@{ id = $_; name = $v.name; lang = $v.lang; gender = $v.gender; installed = ($inst -contains $_); def = [bool]$v.def } })
    }
}
# lista do /tts/voices: głosy Piper jako «piper:…»
function Get-PiperVoiceList {
    if (-not (Get-PiperExe)) { return @() }
    return @(Get-PiperInstalled | ForEach-Object { $v = $PiperVoices[$_]; [pscustomobject]@{ id = "piper:$_"; name = "$($v.name) · Piper"; lang = $v.lang; gender = $v.gender; engine = 'piper' } })
}

# pobieranie w tle (osobny wątek): program + wybrane głosy; postęp w $script:Piper
$PiperInstallScript = {
    param($P, $dir, $zipUrl, $hf, $list)
    $ErrorActionPreference = 'Stop'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    function Get-File([string]$url, [string]$out, [double]$from, [double]$span, [string]$label) {
        $P.step = $label
        $rq = [Net.HttpWebRequest]::Create($url); $rq.UserAgent = 'Vincent-Media'; $rq.Timeout = 30000; $rq.ReadWriteTimeout = 60000; $rq.AllowAutoRedirect = $true
        $rs = $rq.GetResponse(); $len = [double]$rs.ContentLength
        $in = $rs.GetResponseStream(); $part = "$out.part"; $fs = [IO.File]::Create($part)
        try {
            $buf = New-Object byte[] 262144; $got = 0.0
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                $fs.Write($buf, 0, $n); $got += $n
                if ($len -gt 0) { $P.pct = [int][Math]::Floor(100 * ($from + $span * [Math]::Min(1.0, $got / $len))) }
            }
        } finally { $fs.Close(); $in.Close(); $rs.Close() }
        Move-Item -LiteralPath $part -Destination $out -Force
    }
    try {
        $P.busy = $true; $P.error = ''; $P.pct = 0
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'voices') | Out-Null
        $todo = @($list); $n = $todo.Count + 1; $k = 0
        if (-not (Test-Path (Join-Path $dir 'piper\piper.exe'))) {
            $zip = Join-Path $dir 'piper.zip'
            Get-File $zipUrl $zip 0 (1.0 / $n) 'program Piper'
            $P.step = 'rozpakowuję program'
            Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
            Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        }
        $k = 1
        foreach ($v in $todo) {
            $base = Join-Path (Join-Path $dir 'voices') $v.id
            foreach ($x in "$base.onnx", "$base.onnx.json") { if ((Test-Path $x) -and (Get-Item $x).Length -lt $(if ($x.EndsWith('.json')) { 200 } else { 5MB })) { Remove-Item -LiteralPath $x -Force } }   # uszkodzone – od nowa
            if (-not (Test-Path "$base.onnx.json")) { Get-File "$hf/$($v.path)/$($v.id).onnx.json?download=true" "$base.onnx.json" ($k / $n) 0 "głos $($v.name)" }
            if (-not (Test-Path "$base.onnx")) { Get-File "$hf/$($v.path)/$($v.id).onnx?download=true" "$base.onnx" ($k / $n) (1.0 / $n) "głos $($v.name)" }
            $k++
        }
        $P.pct = 100; $P.step = 'gotowe'
    } catch { $P.error = $_.Exception.Message } finally { $P.busy = $false }
}
function Start-PiperInstall([string[]]$ids) {
    if ($script:Piper.busy) { return }
    if (-not $ids -or -not $ids.Count) { $ids = @($PiperVoices.Keys | Where-Object { $PiperVoices[$_].def }) }
    $list = @($ids | Where-Object { $PiperVoices.Contains($_) } | ForEach-Object { @{ id = $_; name = $PiperVoices[$_].name; path = $PiperVoices[$_].path } })
    $script:Piper.busy = $true; $script:Piper.error = ''; $script:Piper.pct = 0; $script:Piper.step = 'start'
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($PiperInstallScript).AddArgument($script:Piper).AddArgument($PiperDir).AddArgument($PiperZip).AddArgument($PiperHF).AddArgument($list)
    [void]$ps.BeginInvoke(); $script:Piper.ps = $ps
    Log ('Głos (Piper): pobieram ' + (($list | ForEach-Object { $_.name }) -join ', ')) 'Cyan'
}

# synteza: tekst → WAV; lengthScale > 1 = wolniej (wysokość głosu dokłada przeglądarka – themes/tts.js)
function Get-PiperWav([string]$id, [string]$text, [double]$lengthScale) {
    $exe = Get-PiperExe; if (-not $exe) { throw 'Piper nie jest zainstalowany' }
    $model = Join-Path (Join-Path $PiperDir 'voices') "$id.onnx"
    if (-not (Test-Path $model)) { throw "brak głosu $id" }
    $out = Join-Path $env:TEMP ('vm-piper-' + [guid]::NewGuid().ToString('N') + '.wav')
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = ('--model "{0}" --output_file "{1}" --length_scale {2} --sentence_silence 0.15' -f $model, $out, $lengthScale.ToString('0.00', $inv))
    $psi.WorkingDirectory = Split-Path $exe; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardOutput = $true
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $b = (New-Object Text.UTF8Encoding($false)).GetBytes($text + "`n")
        $p.StandardInput.BaseStream.Write($b, 0, $b.Length); $p.StandardInput.Close()
        $errTask = $p.StandardError.ReadToEndAsync(); $outTask = $p.StandardOutput.ReadToEndAsync()
        if (-not $p.WaitForExit(20000)) { try { $p.Kill() } catch {}; throw 'Piper nie zdążył (20 s)' }
        if (-not (Test-Path $out)) { throw ('Piper: ' + (([string]$errTask.Result) -split "`n" | Select-Object -Last 1)) }
        return [IO.File]::ReadAllBytes($out)
    } finally { $p.Dispose(); Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
}
