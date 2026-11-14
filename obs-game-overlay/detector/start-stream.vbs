' Vincent-Media: start streamu jednym kliknieciem - GameRadar w tle (bez okna), a zaraz po nim OBS.
' Gdy GameRadar juz dziala, uruchamia tylko OBS.
Set fso = CreateObject("Scripting.FileSystemObject")
d = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & d & "\detector.ps1"" -Hidden -StartObs", 0, False
