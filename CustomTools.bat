@echo off
rem ============================================================
rem  PCL / PCL CE custom homepage helper - run by its buttons.
rem  Usage: CustomTools.bat game ^| mods ^| saves ^| schematics ^| bg
rem                        ^| log1 ^| log2 ^| log3 ^| log4 ^| logs ^| glog ^| glogdir
rem  PCL2 settings live in Setup.ini, PCL CE settings live in
rem  config.v1.yml.  RefreshLog.ps1 resolves the paths and opens the
rem  folder or log itself, at click time, so paths containing spaces,
rem  ampersands, parentheses or non-ASCII text are never re-parsed by
rem  cmd's FOR command.
rem    bg   = ask PCL to pick a new random background image by
rem           driving its settings page (no launcher restart).
rem    glog = open the RUNNING game log (latest.log) in Notepad.
rem    glogdir = open the game log FOLDER (running game first, else the
rem              selected instance's logs folder).
rem    log1 = open the CURRENT launcher session log in Notepad
rem           (PCL2: PCL\Log1.txt, PCL CE: newest PCL\Log\Launch-*.log).
rem    logN = open the log of N-1 launcher launches ago; if it does not
rem           exist yet, open the log folder.
rem    logs = rebuild PCL\LogView.xaml (the snapshot shown on the
rem           homepage) and ask PCL to reload the homepage (F5).
rem ============================================================
setlocal
pushd "%~dp0"
set "BASE=%~dp0"
set "BASEARG=%~dp0"
if "%BASEARG:~-1%"=="\" set "BASEARG=%BASEARG:~0,-1%"

rem Self-heal: rebuild any missing helper file (RefreshLog.ps1,
rem BgRefresh.ps1, Egg.ps1, VideoWall.ps1) and import the
rem shared background image from the backup embedded at the end of
rem Custom.xaml.
if not exist "%BASE%RefreshLog.ps1" goto :heal
if not exist "%BASE%BgRefresh.ps1" goto :heal
if not exist "%BASE%Egg.ps1" goto :heal
if not exist "%BASE%VideoWall.ps1" goto :heal
if not exist "Pictures\CustomHomeBG.jpg" goto :heal
goto :healed
:heal
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=[IO.File]::ReadAllText('Custom.xaml');if(-not [IO.File]::Exists('CustomTools.bat')){$m=[regex]::Match($c,'(?sm)^@@YSM-TOOLS-BAT@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-PS1@@');if($m.Success){[IO.File]::WriteAllText('CustomTools.bat',$m.Groups[1].Value)}};if(-not [IO.File]::Exists('RefreshLog.ps1')){$m=[regex]::Match($c,'(?sm)^@@YSM-TOOLS-PS1@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-PS2@@');if($m.Success){[IO.File]::WriteAllText('RefreshLog.ps1',$m.Groups[1].Value,[Text.UTF8Encoding]::new($true))}};if(-not [IO.File]::Exists('BgRefresh.ps1')){$m=[regex]::Match($c,'(?sm)^@@YSM-TOOLS-PS2@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-PS3@@');if($m.Success){[IO.File]::WriteAllText('BgRefresh.ps1',$m.Groups[1].Value,[Text.UTF8Encoding]::new($true))}};if(-not [IO.File]::Exists('Egg.ps1')){$m=[regex]::Match($c,'(?sm)^@@YSM-TOOLS-PS3@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-PS4@@');if($m.Success){[IO.File]::WriteAllText('Egg.ps1',$m.Groups[1].Value,[Text.UTF8Encoding]::new($true))}};if(-not [IO.File]::Exists('VideoWall.ps1')){$m=[regex]::Match($c,'(?sm)^@@YSM-TOOLS-PS4@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-IMG@@');if($m.Success){[IO.File]::WriteAllText('VideoWall.ps1',$m.Groups[1].Value,[Text.UTF8Encoding]::new($true))}};[void][IO.Directory]::CreateDirectory('Pictures');if(-not [IO.File]::Exists('Pictures\CustomHomeBG.jpg')){$m=[regex]::Match($c,'(?sm)^@@YSM-TOOLS-IMG@@\r?\n(.*?)\r?\n^@@YSM-TOOLS-END@@');if($m.Success){[IO.File]::WriteAllBytes('Pictures\CustomHomeBG.jpg',[Convert]::FromBase64String(($m.Groups[1].Value -replace '\s','')))}};"
:healed

rem The homepage merges PCL\LogView.xaml; make sure it exists and was
rem produced by the current generator (older snapshots miss keys that
rem the homepage needs, which would make the page fail to load).
findstr /c:"YSMLOGG7" "%BASE%LogView.xaml" >nul 2>nul
if errorlevel 1 powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%RefreshLog.ps1" "%BASEARG%"

rem Keep the background log watcher alive (hidden, single instance).
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%BASE%RefreshLog.ps1" -Watch

rem Hidden diagnostics: CustomTools.bat paths prints the same values the
rem buttons use.  Let RefreshLog.ps1 print them directly; parsing the
rem output in a FOR loop would break on & and parentheses in paths.
if /i "%~1"=="paths" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%RefreshLog.ps1" "%BASEARG%" -Paths
    exit /b
)

if /i "%~1"=="bg" goto :bg
if /i "%~1"=="logs" goto :logs
if /i "%~1"=="glog" goto :glog
if /i "%~1"=="glogdir" goto :glogdir
if /i "%~1"=="log1" goto :log1
if /i "%~1"=="log2" goto :log2
if /i "%~1"=="log3" goto :log3
if /i "%~1"=="log4" goto :log4
if "%~1"=="" exit /b 0
if /i "%~1"=="game" goto :folder
if /i "%~1"=="mods" goto :folder
if /i "%~1"=="saves" goto :folder
if /i "%~1"=="schematics" goto :folder
exit /b 0

:folder
rem RefreshLog.ps1 reads the selected instance from Setup.ini or
rem config.v1.yml, creates the folder if needed and opens it.  Keeping
rem path resolution out of batch avoids FOR-variable expansion on & ( ).
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%RefreshLog.ps1" "%BASEARG%" -OpenFolder "%~1"
exit /b %errorlevel%

:glog
rem Open the running game log (needs a live Minecraft process).
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%RefreshLog.ps1" "%BASEARG%" -OpenGameLog
exit /b 0

:glogdir
rem Open the game log folder: the running game first, else the selected
rem instance's logs folder (the folder exists after the first launch).
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%RefreshLog.ps1" "%BASEARG%" -OpenGameLogDir
exit /b 0

:log1
set "LOGINDEX=1"
goto :openlauncherlog
:log2
set "LOGINDEX=2"
goto :openlauncherlog
:log3
set "LOGINDEX=3"
goto :openlauncherlog
:log4
set "LOGINDEX=4"
goto :openlauncherlog

:openlauncherlog
rem PCL CE keeps one file per launch; PCL2 rotates Log1.txt to LogN.txt.
rem RefreshLog.ps1 opens the file, or the log folder when it is not there.
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%RefreshLog.ps1" "%BASEARG%" -OpenLauncherLog %LOGINDEX%
exit /b 0

:logs
rem Rebuild the log snapshot and ask PCL to reload the homepage (F5).
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%RefreshLog.ps1" "%BASEARG%"
exit /b 0

:bg
rem Drive PCL's settings page via UI Automation (BgRefresh.ps1).
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%BASE%BgRefresh.ps1" "%BASEARG%"
exit /b 0
