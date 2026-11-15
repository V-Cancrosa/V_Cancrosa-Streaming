#Requires -Version 5.1
# Moduł GameRadara: głos postaci (TTS, głosy Windows)
# Wczytywany przez detector.ps1 (dot-source). Gdy antywirus albo błąd go zablokuje, reszta GameRadara działa dalej.

# ---------------------------------------------------------------- głos (TTS): głosy Windows – OneCore przez WinRT, zapasowo SAPI
# Za darmo i bez internetu. Barwę postaci (wysokość, tempo) daje SSML, a efekty (robot, radio, pogłos) dokłada przeglądarka.
$script:Tts = @{ ready = $false; err = ''; voices = @(); raw = @{}; cache = [ordered]@{}; mode = '' }
function Initialize-Tts {
    if ($script:Tts.ready -or $script:Tts.err) { return }
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime]
        $script:Tts.asTask = @([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        $script:Tts.synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
        $list = New-Object Collections.ArrayList
        foreach ($v in [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices) {
            $script:Tts.raw[[string]$v.Id] = $v
            [void]$list.Add([pscustomobject]@{ id = [string]$v.Id; name = ([string]$v.DisplayName -replace '^Microsoft\s+', ''); lang = [string]$v.Language; gender = ([string]$v.Gender).ToLowerInvariant() })
        }
        if (-not $list.Count) { throw 'brak głosów OneCore' }
        $script:Tts.voices = @($list); $script:Tts.mode = 'onecore'
    } catch {
        try {
            Add-Type -AssemblyName System.Speech
            $script:Tts.sapi = New-Object System.Speech.Synthesis.SpeechSynthesizer
            $script:Tts.voices = @($script:Tts.sapi.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $i = $_.VoiceInfo; [pscustomobject]@{ id = [string]$i.Name; name = ([string]$i.Name -replace '^Microsoft\s+', '' -replace '\s+Desktop$', ''); lang = [string]$i.Culture.Name; gender = ([string]$i.Gender).ToLowerInvariant() } })
            $script:Tts.mode = 'sapi'
        } catch { $script:Tts.err = $_.Exception.Message; Log "Głos (TTS) niedostępny: $($script:Tts.err)" 'Yellow'; return }
    }
    $script:Tts.ready = $true
    Log ("Głos (TTS): {0} głosów Windows ({1})" -f $script:Tts.voices.Count, ((@($script:Tts.voices | ForEach-Object { $_.lang }) | Sort-Object -Unique) -join ', ')) 'DarkGray'
}
function Get-TtsWav([string]$text, [string]$voice, [double]$rate, [int]$pitch) {
    $text = ($text -replace '\s+', ' ').Trim()
    if ($text.Length -gt 400) { $text = $text.Substring(0, 400) }
    if (-not $text) { return $null }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $rate = [Math]::Max(0.5, [Math]::Min(2.0, $rate)); $pitch = [Math]::Max(-50, [Math]::Min(50, $pitch))
    $key = "$voice|$rate|$pitch|$text"
    if ($script:Tts.cache.Contains($key)) { return $script:Tts.cache[$key] }
    $v = @($script:Tts.voices | Where-Object { $_.id -eq $voice })[0]
    if (-not $v) { $v = @($script:Tts.voices)[0] }
    $esc = [Security.SecurityElement]::Escape($text)
    $ps = $(if ($pitch -ge 0) { "+$pitch%" } else { "$pitch%" })
    if ($script:Tts.mode -eq 'onecore') {
        $sy = $script:Tts.synth
        $sy.Voice = $script:Tts.raw[$v.id]
        $ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='$($v.lang)'><prosody rate='$($rate.ToString('0.00', $inv))' pitch='$ps'>$esc</prosody></speak>"
        $task = $script:Tts.asTask.MakeGenericMethod([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]).Invoke($null, @($sy.SynthesizeSsmlToStreamAsync($ssml)))
        [void]$task.Wait(15000)
        $st = $task.Result
        $ns = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($st.GetInputStreamAt(0))
        $ms = New-Object IO.MemoryStream; $ns.CopyTo($ms); $bytes = $ms.ToArray(); $ns.Dispose(); $st.Dispose()
    } else {
        $sy = $script:Tts.sapi; $ms = New-Object IO.MemoryStream
        try {
            $sy.SelectVoice($v.id); $sy.Rate = [int][Math]::Round(($rate - 1) * 10)
            $sy.SetOutputToWaveStream($ms); $sy.Speak($text)
        } finally { $sy.SetOutputToNull() }
        $bytes = $ms.ToArray()
    }
    $script:Tts.cache[$key] = $bytes
    while ($script:Tts.cache.Count -gt 40) { $script:Tts.cache.RemoveAt(0) }
    return $bytes
}
