' Fuehrt den Lackformeln-Sync sofort aus (ohne Fenster).
Dim fso, ps1Path, shell

Set fso = CreateObject("Scripting.FileSystemObject")
ps1Path = fso.GetParentFolderName(WScript.ScriptFullName) & "\Sync_Lackformeln.ps1"

Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File """ & ps1Path & """", 0, False

Set fso = Nothing
Set shell = Nothing
