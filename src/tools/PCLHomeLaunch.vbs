' PCLHomeLaunch.vbs - windowless launcher for the PCL custom homepage.
' Modes: watch | tool <name> | commands | bg | refresh | egg | heal
'
' wscript.exe is a GUI-subsystem program, so starting this file never creates
' a console window.  Every PowerShell and cmd child is started with window
' style 0 as well.  The homepage buttons and the logon Run entry use this file
' instead of cmd.exe or powershell.exe directly.
Option Explicit

Dim fso, sh, base, mode, rc

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
base = fso.GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = base

Function Q(s)
    Q = Chr(34) & s & Chr(34)
End Function

Sub RunHidden(cmd)
    sh.Run cmd, 0, False
End Sub

Function RunHiddenWait(cmd)
    RunHiddenWait = sh.Run(cmd, 0, True)
End Function

Function PsFile(script, extra)
    PsFile = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Q(base & "\" & script) & extra
End Function

Function PsFileSta(script, extra)
    PsFileSta = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Q(base & "\" & script) & extra
End Function

Sub EnsureTools
    Dim need, extractCmd
    need = False
    If Not fso.FileExists(base & "\CustomTools.bat") Then need = True
    If Not fso.FileExists(base & "\RefreshLog.ps1") Then need = True
    If Not fso.FileExists(base & "\BgRefresh.ps1") Then need = True
    If Not fso.FileExists(base & "\Egg.ps1") Then need = True
    If Not fso.FileExists(base & "\VideoWall.ps1") Then need = True
    If Not fso.FileExists(base & "\CommandManager.ps1") Then need = True
    If Not fso.FileExists(base & "\Pictures\CustomHomeBG.jpg") Then need = True
    If Not need Then Exit Sub

    ' CustomTools.bat is the bootstrap that can rebuild every other helper
    ' from the backup embedded in Custom.xaml.  Recreate it first if needed.
    If Not fso.FileExists(base & "\CustomTools.bat") Then
        extractCmd = "$c=[IO.File]::ReadAllText('Custom.xaml');$m=[regex]::Match($c,'(?sm)^@@YSM-TOOLS-BAT@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-PS1@@');if($m.Success){[IO.File]::WriteAllText('CustomTools.bat',$m.Groups[1].Value)}"
        RunHiddenWait "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command " & Q(extractCmd)
    End If
    If fso.FileExists(base & "\CustomTools.bat") Then
        RunHiddenWait "cmd.exe /d /s /c " & Q(Q(base & "\CustomTools.bat") & " heal")
    End If
End Sub

If WScript.Arguments.Count = 0 Then WScript.Quit 0
mode = LCase(WScript.Arguments(0))
EnsureTools

Select Case mode
    Case "watch"
        RunHidden PsFile("RefreshLog.ps1", " -Watch")
    Case "tool"
        If WScript.Arguments.Count < 2 Then WScript.Quit 0
        RunHidden "cmd.exe /d /s /c " & Q(Q(base & "\CustomTools.bat") & " " & LCase(WScript.Arguments(1)))
    Case "commands"
        RunHidden PsFileSta("CommandManager.ps1", " " & Q(base))
    Case "bg"
        RunHidden PsFile("BgRefresh.ps1", " " & Q(base))
    Case "refresh"
        rc = RunHiddenWait(PsFile("RefreshLog.ps1", " " & Q(base)))
        WScript.Quit rc
    Case "egg"
        RunHidden PsFile("Egg.ps1", "")
    Case "heal"
        ' EnsureTools already handled the repair.
End Select
WScript.Quit 0
