@echo off
setlocal
rem ============================================================
rem  PCL / PCL CE custom homepage - one file installer
rem
rem  double click this file, choose PCL2 or PCL CE, then pick the
rem  matching data folder (the folder that contains Setup.ini or
rem  config.v1.yml, usually the PCL folder next to the launcher
rem  exe).  everything is installed into it.
rem
rem  works with PCL2 (Setup.ini) and PCL CE (config.v1.yml) and
rem  writes only the config file of the launcher you selected.
rem
rem  command line:  ...bat pcl [folder]   or   ...bat ce [folder]
rem  run with the argument  uninstall  to remove it again.
rem ============================================================
set "SELF=%~f0"
set "PCLHOME_MODE1=%~1"
set "PCLHOME_MODE2=%~2"
set "PCLHOME_PSHIDE="
if "%PCLHOME_NO_CONSOLE%"=="1" set "PCLHOME_PSHIDE=-WindowStyle Hidden"
powershell -NoProfile %PCLHOME_PSHIDE% -ExecutionPolicy Bypass -Command "$f=$env:SELF;$b=[IO.File]::ReadAllLines($f,[Text.Encoding]::UTF8);$i=[Array]::IndexOf($b,'::SCRIPT-BEGIN');$j=[Array]::IndexOf($b,'::SCRIPT-END');if($i -lt 0 -or $j -le $i){exit 2};$t=New-Object Text.StringBuilder;for($k=$i+1;$k -lt $j;$k++){if($b[$k].Length -ge 2){[void]$t.AppendLine($b[$k].Substring(2))}};$p=Join-Path $env:TEMP ('pclhome_'+[Guid]::NewGuid().ToString('N')+'.ps1');[IO.File]::WriteAllText($p,$t.ToString(),(New-Object Text.UTF8Encoding($true)));$ia=@('-NoProfile','-ExecutionPolicy','Bypass');if($env:PCLHOME_NO_CONSOLE -eq '1'){$ia+='-WindowStyle','Hidden'};$ia+='-File',$p;& powershell @ia;$c=$LASTEXITCODE;Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue;exit $c"
::SCRIPT-BEGIN
::SCRIPT-END
::DATA-BEGIN
::DATA-END
