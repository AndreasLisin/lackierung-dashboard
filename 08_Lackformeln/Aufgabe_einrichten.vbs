Dim fso, ps1Path, shell

Set fso = CreateObject("Scripting.FileSystemObject")
ps1Path = fso.GetParentFolderName(WScript.ScriptFullName) & "\Aufgabe_einrichten.ps1"

Set shell = CreateObject("Shell.Application")
shell.ShellExecute "powershell.exe", _
    "-ExecutionPolicy Bypass -NoProfile -File """ & ps1Path & """", _
    "", "", 1

Set fso = Nothing
Set shell = Nothing
