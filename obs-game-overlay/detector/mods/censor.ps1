#Requires -Version 5.1
# Moduł GameRadara: cenzura ekranu (OCR okna gry, wątek w tle)
# Wczytywany przez detector.ps1 (dot-source). Gdy antywirus albo błąd go zablokuje, reszta GameRadara działa dalej.

$CensorScript = {
    param($C)
    try {
        Add-Type -AssemblyName System.Drawing, System.Windows.Forms, System.Runtime.WindowsRuntime
        if (-not ('VMCensor.W' -as [type])) {
            Add-Type -Namespace VMCensor -Name W -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@
        }
        # piksele fizyczne (skalowanie Windows 125% itd.): bez tego zrzut okna i współrzędne słów wychodzą w różnej skali
        # (zasłony za wysoko i za bardzo w lewo). PER_MONITOR_AWARE_V2 = -4 – dla procesu i dla tego wątku.
        try { [void][VMCensor.W]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch {}
        try { [void][VMCensor.W]::SetThreadDpiAwarenessContext([IntPtr](-4)) } catch {}
        try { [void][VMCensor.W]::SetProcessDPIAware() } catch {}
        $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
        $asTask = @([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        $await = { param($op, [Type]$t) $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); [void]$task.Wait(-1); $task.Result }
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
        if (-not $engine) { $C.status = 'brak OCR'; $C.err = 'Windows nie ma rozpoznawania tekstu dla Twoich języków (Ustawienia → Czas i język → Język → Opcje języka → Rozpoznawanie tekstu)'; return }
        $C.lang = [string]$engine.RecognizerLanguage.LanguageTag
        $maxDim = [int][Windows.Media.Ocr.OcrEngine]::MaxImageDimension
        $exeOf = @{}; $times = New-Object Collections.Queue
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object Web.Script.Serialization.JavaScriptSerializer; $ser.MaxJsonLength = 16777216
        while (-not $C.quit) {
            if (-not $C.on -or (Get-Date) -gt $C.until) { $C.status = 'wyłączona'; $C.result = $null; Start-Sleep -Milliseconds 500; continue }
            try {
                # okno do skanu: to, które OBS przechwytuje w bieżącej scenie (target = plik .exe), także gdy jest pod innymi oknami;
                # bez celu – okno na pierwszym planie z listy skanowanych programów
                $h = [IntPtr]::Zero; $exe = ''
                if ($C.target) {
                    $tp = @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension([string]$C.target)) -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
                    $tp = @($tp | Sort-Object { -not $_.MainWindowTitle }) | Select-Object -First 1
                    if ($tp) { $h = $tp.MainWindowHandle; $exe = ([string]$C.target).ToLowerInvariant() }
                }
                if ($h -eq [IntPtr]::Zero) {
                    $h = [VMCensor.W]::GetForegroundWindow(); $procId = [uint32]0; [void][VMCensor.W]::GetWindowThreadProcessId($h, [ref]$procId)
                    if (-not $exeOf.ContainsKey($procId)) { $pe = ''; try { $pe = [IO.Path]::GetFileName((Get-Process -Id $procId -ErrorAction Stop).Path).ToLowerInvariant() } catch {}; $exeOf[$procId] = $pe }
                    $exe = $exeOf[$procId]
                    $list = @($C.exes)
                    if ($list.Count -and -not ($list -contains $exe)) { $t0 = [DateTimeOffset]::Now.ToUnixTimeMilliseconds(); $C.json = $ser.Serialize(@{ at = $t0; exe = $exe; skip = $true; lines = @() }); $C.result = @{ at = $t0 }; $C.status = "czeka (na wierzchu: $exe)"; Start-Sleep -Milliseconds 250; continue }
                }
                $r = New-Object VMCensor.W+RECT; [void][VMCensor.W]::GetClientRect($h, [ref]$r)
                $pt = New-Object VMCensor.W+POINT; [void][VMCensor.W]::ClientToScreen($h, [ref]$pt)
                $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
                if ($w -lt 80 -or $hh -lt 40 -or [VMCensor.W]::IsIconic($h)) { Start-Sleep -Milliseconds 250; continue }
                # PrintWindow (PW_RENDERFULLCONTENT) – zawartość samego okna, nawet przykrytego; potem wycinamy obszar klienta (to samo, co łapie OBS)
                $wr = New-Object VMCensor.W+RECT; [void][VMCensor.W]::GetWindowRect($h, [ref]$wr)
                $ww = $wr.Right - $wr.Left; $wh = $wr.Bottom - $wr.Top
                $full = New-Object Drawing.Bitmap $ww, $wh
                $g = [Drawing.Graphics]::FromImage($full); $hdc = $g.GetHdc(); $okPw = [VMCensor.W]::PrintWindow($h, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
                $bmp = New-Object Drawing.Bitmap $w, $hh
                $g = [Drawing.Graphics]::FromImage($bmp)
                if ($okPw) { $g.DrawImage($full, (New-Object Drawing.Rectangle 0, 0, $w, $hh), (New-Object Drawing.Rectangle ($pt.X - $wr.Left), ($pt.Y - $wr.Top), $w, $hh), [Drawing.GraphicsUnit]::Pixel) }
                else { $g.CopyFromScreen($pt.X, $pt.Y, 0, 0, $bmp.Size) }
                $g.Dispose(); $full.Dispose()
                $sc = [Math]::Min(1.0, $maxDim / [double]([Math]::Max($w, $hh)))
                if ($sc -lt 1) { $b2 = New-Object Drawing.Bitmap $bmp, ([int]($w * $sc)), ([int]($hh * $sc)); $bmp.Dispose(); $bmp = $b2 }
                $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Bmp); $bmp.Dispose(); $ms.Position = 0
                $ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($ms)
                $dec = & $await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
                $sb = & $await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
                $res = & $await ($engine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
                $sb.Dispose(); $ms.Dispose()
                $lines = New-Object Collections.ArrayList
                foreach ($ln in $res.Lines) {
                    $ws = New-Object Collections.ArrayList
                    foreach ($wd in $ln.Words) { $b = $wd.BoundingRect; [void]$ws.Add(@{ t = [string]$wd.Text; x = [int]($pt.X + $b.X / $sc); y = [int]($pt.Y + $b.Y / $sc); w = [int]($b.Width / $sc); h = [int]($b.Height / $sc) }) }
                    [void]$lines.Add(@{ words = @($ws) })
                }
                $mon = [System.Windows.Forms.Screen]::FromHandle($h).Bounds
                $now = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                $C.json = $ser.Serialize(@{ at = $now; exe = $exe; client = @{ x = $pt.X; y = $pt.Y; w = $w; h = $hh }; monitor = @{ x = $mon.X; y = $mon.Y; w = $mon.Width; h = $mon.Height }; lines = @($lines) })
                $C.result = @{ at = $now }
                $times.Enqueue($now); while ($times.Count -gt 10) { [void]$times.Dequeue() }
                if ($times.Count -gt 1) { $C.fps = [Math]::Round(($times.Count - 1) * 1000.0 / ($now - $times.Peek()), 1) }
                $C.status = 'działa'; $C.err = ''
            } catch { $C.err = $_.Exception.Message; Start-Sleep -Milliseconds 500 }
        }
    } catch { $C.status = 'błąd'; $C.err = $_.Exception.Message }
}
function Start-Censor {
    if ($script:CensorPS -and -not $script:CensorPS.InvocationStateInfo.State.ToString().StartsWith('Complet') -and $script:CensorPS.InvocationStateInfo.State -ne 'Failed') { return }
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($CensorScript).AddArgument($script:Censor)
    [void]$ps.BeginInvoke(); $script:CensorPS = $ps
    Log 'Cenzura ekranu: skan włączony' 'DarkCyan'
}
