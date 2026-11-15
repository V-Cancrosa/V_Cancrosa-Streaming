#Requires -Version 5.1
# Moduł GameRadara: lista otwartych okien (dodawanie gier w serwisie)
# Wczytywany przez detector.ps1 (dot-source). Gdy antywirus albo błąd go zablokuje, reszta GameRadara działa dalej.

function Get-OpenWindows {
    $known = @{}; foreach ($v in $script:GameLib.Values) { if ($v.exe) { $known[[string]$v.exe] = [string]$v.name } }
    $skip = '^(explorer|obs64|obs32|obs|powershell|pwsh|cmd|conhost|windowsterminal|applicationframehost|systemsettings|textinputhost|shellexperiencehost|searchhost|searchapp|startmenuexperiencehost|lockapp|wscript|msedgewebview2|taskmgr|nvidia overlay|gamebar|xboxgamebarwidgets)$'
    $list = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -and $_.ProcessName -notmatch $skip } | ForEach-Object {
        $exe = ($_.ProcessName + '.exe').ToLowerInvariant(); $path = ''; try { $path = [string]$_.Path } catch {}
        [pscustomobject]@{ exe = $exe; title = [string]$_.MainWindowTitle; path = $path; known = [string]$known[$exe]; custom = [bool]$script:Custom.ContainsKey($exe); ignored = [bool]$script:Ignore.ContainsKey($exe) }
    } | Sort-Object exe -Unique)
    return $list
}
