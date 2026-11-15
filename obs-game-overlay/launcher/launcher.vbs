' Vincent-Media: uruchamia kreator startu (okno z krokami) bez czarnego okna konsoli.
' Z parametrem /tlo: sam GameRadar w tle (autostart z Windows).
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
d = fso.GetParentFolderName(WScript.ScriptFullName)
mode = ""
If WScript.Arguments.Count > 0 Then mode = LCase(WScript.Arguments(0))
If mode = "/tlo" Then
  sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & fso.GetParentFolderName(d) & "\detector\detector.ps1"" -Hidden", 0, False
Else
  sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & d & "\launcher.ps1""", 0, False
End If
