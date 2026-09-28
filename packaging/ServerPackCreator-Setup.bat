@echo off
rem ===========================================================================
rem  ServerPackCreator installer
rem
rem  Download this one file and double-click it. It will set everything up on
rem  this machine: check for Java, download the application, create the
rem  launchers and a Start Menu entry.
rem
rem  You do NOT need to download any source code, and you do NOT need to build
rem  anything yourself.
rem
rem  Double-clicking asks where to put it. Passing -Location skips the question,
rem  which is what scripts and unattended runs should do.
rem
rem  The location is a place to put ServerPackCreator in, not the folder it is
rem  installed as: a folder named ServerPackCreator is created inside it and
rem  everything goes there. Pointing at a desktop or a downloads folder therefore
rem  leaves that folder itself untouched.
rem
rem  Options (from a command prompt):
rem     ServerPackCreator-Setup.bat -Location "D:\"
rem     ServerPackCreator-Setup.bat -Location "C:\Users\you\Desktop"
rem     ServerPackCreator-Setup.bat -JavaPath "C:\path\to\jdk-21\bin\java.exe"
rem     ServerPackCreator-Setup.bat -JarPath ".\serverpackcreator-app.jar"
rem     ServerPackCreator-Setup.bat -Uninstall
rem ===========================================================================

setlocal enableextensions
set "SPC_SELF=%~f0"
set "SPC_UNINSTALL="
set "SPC_LOCATION="
set "SPC_JARPATH="
set "SPC_JAVAPATH="

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="-uninstall"   set "SPC_UNINSTALL=1"           & shift & goto parse
if /i "%~1"=="/uninstall"   set "SPC_UNINSTALL=1"           & shift & goto parse
if /i "%~1"=="-location"    set "SPC_LOCATION=%~2"          & shift & shift & goto parse
if /i "%~1"=="-installdir"  set "SPC_LOCATION=%~2"          & shift & shift & goto parse
if /i "%~1"=="-jarpath"     set "SPC_JARPATH=%~2"           & shift & shift & goto parse
if /i "%~1"=="-javapath"    set "SPC_JAVAPATH=%~2"          & shift & shift & goto parse
if /i "%~1"=="-nopause"     set "SPC_NOPAUSE=1"            & shift & goto parse
if /i "%~1"=="-help"        goto usage
if /i "%~1"=="-h"           goto usage
echo Unknown option: %~1
goto usage

:usage
echo.
echo Usage: ServerPackCreator-Setup.bat [options]
echo.
echo   -Location ^<path^>    Where to put ServerPackCreator. Its own folder is
echo                        created inside that location, so nothing is written
echo                        directly into it. Omit to be asked. Default: D:\, or
echo                        %%LOCALAPPDATA%% if D: is not writable
echo   -JavaPath    ^<path^>  Path to java.exe to use.
echo   -JarPath     ^<path^>  Install from a local JAR instead of downloading one.
echo   -Uninstall           Remove a previous installation.
echo   -NoPause             Do not wait for a keypress when finished.
echo.
pause
exit /b 2

:parsed
rem Hand the work over to PowerShell, which is the script embedded below the
rem marker line. Reading ourselves means there is only one file to download.
rem Keep this on a single line: batch line-continuation with ^ breaks on
rem trailing whitespace, and this file is edited by hand.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$lines=[IO.File]::ReadAllLines($env:SPC_SELF); $i=[Array]::IndexOf($lines,'#PS-BEGIN#'); if($i -lt 0){ Write-Host 'Corrupted installer: marker not found.' -ForegroundColor Red; exit 9 }; Invoke-Expression (($lines[($i+1)..($lines.Length-1)]) -join [Environment]::NewLine)"
set "SPC_RC=%ERRORLEVEL%"

if not "%SPC_RC%"=="0" echo Setup exited with code %SPC_RC%.

rem Pause so the result stays readable when this file was double-clicked. Pass
rem -NoPause when driving this from a script or CI, where a prompt would hang.
if not defined SPC_NOPAUSE (
    echo.
    pause
)
endlocal & exit /b %SPC_RC%



#PS-BEGIN#
# ===========================================================================
#  PowerShell installer. Everything below this line is executed by the
#  bootstrap above; cmd.exe never reaches it.
# ===========================================================================

# The repository this build is published from. Replace before publishing.
$Repo    = 'compound0921/ServerPackCreator-Patch'
$Version = '8.1.2'

# Upstream project this is derived from, for the notice we install alongside it.
$UpstreamUrl = 'https://github.com/Griefed/ServerPackCreator'

$AppName      = 'ServerPackCreator'
$JarFileName  = 'serverpackcreator-app.jar'   # stable name, so /releases/latest/download/ always resolves
$JarUrl       = "https://github.com/$Repo/releases/latest/download/$JarFileName"
$MinJavaMajor = 21

# The location is a place to put ServerPackCreator *in* - never the folder it is
# installed *as*. Its own folder is created inside whatever is chosen, so pointing
# at somewhere that already holds other files (a desktop, a downloads folder, D:\)
# cannot scatter the application and its working directories among them.
$AppFolderName = $AppName

# Everything - the JAR, the launchers and the working directories - ends up in that
# single folder, which is ServerPackCreator's home. The launchers pass it as --home.
$preferredLocation = 'D:\'
$fallbackLocation  = $env:LOCALAPPDATA

$Location        = $env:SPC_LOCATION
$defaultLocation = $fallbackLocation

# Prefer D:\ but only if it exists and its root is actually writable - a standard
# user can create folders there on most systems, not all.
try {
    if (Test-Path -LiteralPath $preferredLocation) {
        $probe = Join-Path $preferredLocation ("{0}-write-test-{1}" -f $AppName, $PID)
        New-Item -ItemType Directory -Path $probe -Force | Out-Null
        Remove-Item -LiteralPath $probe -Force
        $defaultLocation = $preferredLocation
    }
} catch {
    $defaultLocation = $fallbackLocation
}

$JavaPath   = $env:SPC_JAVAPATH
$JarPath    = $env:SPC_JARPATH
$Uninstall  = [bool]$env:SPC_UNINSTALL

function Write-Step  { param([string]$m) Write-Host "  $m" }
function Write-Ok    { param([string]$m) Write-Host "  $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "  $m" -ForegroundColor Yellow }
function Fail        { param([string]$m) Write-Host "`nERROR: $m`n" -ForegroundColor Red; exit 1 }

# Windows PowerShell 5.1 defaults to TLS 1.0, which GitHub rejects.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# Turn the chosen location into the folder that actually holds everything.
function Resolve-InstallDir {
    param([string]$Base)
    $full = [IO.Path]::GetFullPath($Base)
    # Already pointing at a ServerPackCreator folder? Use it rather than nesting
    # another one inside it.
    if ((Split-Path -Leaf $full) -ieq $AppFolderName) { return $full }
    return (Join-Path $full $AppFolderName)
}

# Ask where to put it, unless -Location was passed. Enter accepts the default.
# Skipped when stdin is not a terminal, so redirected and unattended runs cannot
# hang waiting for an answer.
if (-not $Location) {
    $answer = ''
    try {
        if (-not [Console]::IsInputRedirected) {
            Write-Host ''
            if ($Uninstall) {
                Write-Host "  Where was $AppName installed?"
            } else {
                Write-Host "  Where should $AppName be installed?"
            }
            Write-Host "  A folder named $AppFolderName is created inside that location." -ForegroundColor DarkGray
            Write-Host '  Press Enter to accept the default.' -ForegroundColor DarkGray
            Write-Host ''
            Write-Host '  Location ' -NoNewline
            Write-Host "[$defaultLocation]" -NoNewline -ForegroundColor DarkGray
            Write-Host ' '
            $answer = Read-Host
        }
    } catch {
        $answer = ''
    }
    $Location = if ($answer -and $answer.Trim()) { $answer.Trim().Trim('"') } else { $defaultLocation }
}

try {
    $InstallDir = Resolve-InstallDir $Location
} catch {
    Fail "Not a usable location: $Location"
}

function Get-JavaMajorVersion {
    param([string]$JavaExe)
    if (-not (Test-Path -LiteralPath $JavaExe)) { return 0 }

    # java -version writes to stderr. Under $ErrorActionPreference = 'Stop', capturing a native
    # command's stderr with 2>&1 raises a terminating error, so relax it for the call.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = (& $JavaExe -version 2>&1 | Out-String)
    } catch {
        return 0
    } finally {
        $ErrorActionPreference = $previous
    }

    # Older JVMs report 1.8, newer ones report 21.
    if ($output -match 'version "(\d+)') {
        $major = [int]$Matches[1]
        if ($major -eq 1 -and $output -match 'version "1\.(\d+)') { return [int]$Matches[1] }
        return $major
    }
    return 0
}

function Find-Java {
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($JavaPath) { $candidates.Add($JavaPath) }

    # JAVA_HOME first - it is the most deliberate signal of intent.
    if ($env:JAVA_HOME) { $candidates.Add((Join-Path $env:JAVA_HOME 'bin\java.exe')) }

    # Common JDK vendors.
    $globs = @(
        'C:\Program Files\Eclipse Adoptium\jdk-21*\bin\java.exe',
        'C:\Program Files\Microsoft\jdk-21*\bin\java.exe',
        'C:\Program Files\Java\jdk-21*\bin\java.exe',
        'C:\Program Files\Zulu\zulu-21*\bin\java.exe',
        'C:\Program Files\Amazon Corretto\jdk21*\bin\java.exe',
        'C:\Program Files\BellSoft\LibericaJDK-21*\bin\java.exe',
        'C:\Program Files (x86)\Eclipse Adoptium\jdk-21*\bin\java.exe'
    )
    foreach ($g in $globs) {
        try {
            Get-ChildItem -Path $g -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                ForEach-Object { $candidates.Add($_.FullName) }
        } catch { }
    }

    # Whatever is on PATH.
    $onPath = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($onPath) { $candidates.Add($onPath.Source) }

    $seen = @{}
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $resolved = $c
        try { $resolved = (Resolve-Path -LiteralPath $c -ErrorAction Stop).Path } catch { continue }
        if ($seen.ContainsKey($resolved)) { continue }
        $seen[$resolved] = $true

        $major = Get-JavaMajorVersion -JavaExe $resolved
        if ($major -ge $MinJavaMajor) {
            return @{ Path = $resolved; Major = $major }
        }
    }
    return $null
}

function New-Launcher {
    param(
        [string]$Path,
        [string]$JavaExe,
        [string]$JarFileName,
        [string]$ExtraArgs,
        [switch]$Console
    )

    $javaCommand    = if ($Console) { 'java.exe' } else { 'javaw.exe' }
    $javaExeSibling = Join-Path (Split-Path -Parent $JavaExe) $javaCommand

    $body = @'
@echo off
setlocal
rem Use the Java that was present at install time, falling back to whatever is on PATH.
set "SPC_JAVA=__SPC_JAVA__"
if exist "%SPC_JAVA%" goto javafound
set "SPC_JAVA=__SPC_JAVA_FALLBACK__"
where %SPC_JAVA% >nul 2>&1
if errorlevel 1 goto nojava

:javafound
rem This script lives in the home-directory itself, so that is what --home gets.
rem The trailing dot makes %%~fI drop the trailing backslash of %~dp0.
for %%I in ("%~dp0.") do set "SPC_HOME=%%~fI"
cd /d "%~dp0"
__SPC_LAUNCH__"%SPC_JAVA%" -jar "%~dp0__SPC_JAR__" --home "%SPC_HOME%" __SPC_ARGS__%*
exit /b 0

:nojava
echo.
echo ERROR: A Java 21 or newer runtime was not found.
echo        Install one from https://adoptium.net/ and run the installer again.
echo.
pause
exit /b 1
'@

    $launch = if ($Console) { '' } else { 'start "ServerPackCreator" ' }

    $body = $body.Replace('__SPC_JAVA__', $javaExeSibling)
    $body = $body.Replace('__SPC_JAVA_FALLBACK__', $javaCommand)
    $body = $body.Replace('__SPC_JAR__', $JarFileName)
    $body = $body.Replace('__SPC_ARGS__', $(if ($ExtraArgs) { "$ExtraArgs " } else { '' }))
    $body = $body.Replace('__SPC_LAUNCH__', $launch)

    # cmd.exe wants CRLF; the here-string above is LF-only.
    $crlf = ($body -split "`n") -join "`r`n"
    Set-Content -LiteralPath $Path -Value $crlf -Encoding ASCII
}

function Invoke-Uninstall {
    if (-not (Test-Path -LiteralPath $InstallDir)) {
        Write-Warn2 "Nothing to remove: $InstallDir does not exist."
    } else {
        Write-Step "Removing $InstallDir ..."
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
        Write-Ok 'Removed.'
    }

    # The app stores its home-directory in the registry; clear it so a stale path
    # is not left pointing at a directory that no longer exists.
    $pref = Get-SpcPreferenceNode
    if (Test-Path -LiteralPath $pref) {
        try { Remove-Item -LiteralPath $pref -Recurse -Force; Write-Ok 'Cleared stored home-directory preference.' }
        catch { Write-Warn2 "Could not clear the preference at $pref - remove it by hand if you reinstall elsewhere." }
    }

    $shortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$AppName.lnk"
    if (Test-Path -LiteralPath $shortcut) {
        Remove-Item -LiteralPath $shortcut -Force
        Write-Ok 'Removed Start Menu shortcut.'
    }
    Write-Host ''
}

function Get-SpcPreferenceNode {
    'HKCU:\Software\JavaSoft\Prefs\/Server/Pack/Creator'
}

# ---------------------------------------------------------------- uninstall

if ($Uninstall) {
    Write-Host "`n$AppName uninstaller`n" -ForegroundColor Cyan
    Invoke-Uninstall
    exit 0
}

Write-Host "`n$AppName installer`n" -ForegroundColor Cyan

# ---------------------------------------------------------------- java

Write-Step 'Looking for a Java 21 runtime...'
$java = Find-Java
if (-not $java) {
    Fail @"
No Java 21 or newer runtime found.

ServerPackCreator needs Java 21 or newer. Install one - Temurin is a good
choice - from:

    https://adoptium.net/

Then run this installer again. If you already have a suitable Java somewhere
unusual, point this installer at it:

    ServerPackCreator-Setup.bat -JavaPath "C:\path\to\jdk-21\bin\java.exe"
"@
}
Write-Ok "Using Java $($java.Major): $($java.Path)"

# ---------------------------------------------------------------- download

<#
    Redraw the download progress line in place. Deliberately hand-rolled rather than
    using Write-Progress: the built-in progress bar costs enough per update to make
    large downloads markedly slower, which is why it is normally switched off.
#>
function Write-DownloadProgress {
    param(
        [long]$Done,
        [long]$Total,
        [DateTime]$Started,
        [switch]$Final
    )

    if ([Console]::IsOutputRedirected) {
        if ($Final) { Write-Host ("  Downloaded {0:N1} MB" -f ($Done / 1MB)) }
        return
    }

    $elapsed = ([DateTime]::UtcNow - $Started).TotalSeconds
    $speed   = if ($elapsed -gt 0) { $Done / $elapsed } else { 0 }

    if ($Total -gt 0) {
        $percent = [math]::Min(100, [int](100 * $Done / $Total))
        $width   = 30
        $filled  = [int]($width * $percent / 100)
        $bar     = ('#' * $filled).PadRight($width, '-')
        $line    = "  [{0}] {1,3}%   {2,6:N1} / {3:N1} MB   {4,5:N1} MB/s" -f `
                       $bar, $percent, ($Done / 1MB), ($Total / 1MB), ($speed / 1MB)
    } else {
        $line    = "  Downloaded {0:N1} MB   {1:N1} MB/s" -f ($Done / 1MB), ($speed / 1MB)
    }

    # [char]13 rather than `r: this text is embedded in a .bat and read back by
    # Invoke-Expression, where a backtick escape is easy to lose.
    Write-Host ([char]13 + $line.PadRight(74)) -NoNewline
    if ($Final) { Write-Host '' }
}

<#
    Download $Url to $Destination, drawing a progress line while it runs.
    Streams in 80 KB chunks and only redraws every 200 ms, so the reporting itself
    stays cheap.
#>
function Get-RemoteFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination
    )

    $request                   = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Url)
    $request.UserAgent         = 'ServerPackCreator-Setup'
    $request.AllowAutoRedirect = $true
    $request.Timeout           = 60000
    $request.ReadWriteTimeout  = 60000

    $response  = $null
    $inStream  = $null
    $outStream = $null
    try {
        $response  = $request.GetResponse()
        $total     = $response.ContentLength
        $inStream  = $response.GetResponseStream()
        $outStream = [IO.File]::Create($Destination)

        $buffer   = New-Object byte[] 81920
        $done     = [long]0
        $started  = [DateTime]::UtcNow
        $lastDraw = $started

        while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outStream.Write($buffer, 0, $read)
            $done += $read

            $now = [DateTime]::UtcNow
            if (($now - $lastDraw).TotalMilliseconds -ge 200) {
                Write-DownloadProgress -Done $done -Total $total -Started $started
                $lastDraw = $now
            }
        }
        $outStream.Flush()
        Write-DownloadProgress -Done $done -Total $total -Started $started -Final
    } finally {
        if ($outStream) { $outStream.Dispose() }
        if ($inStream)  { $inStream.Dispose() }
        if ($response)  { $response.Dispose() }
    }
}

# ---------------------------------------------------------------- jar

# Flat layout: the JAR and launchers sit in the home-directory itself.
$appDir = $InstallDir

Write-Step "Creating $appDir ..."
New-Item -ItemType Directory -Path $appDir -Force | Out-Null

$jarDestination = Join-Path $appDir $JarFileName

if ($JarPath) {
    if (-not (Test-Path -LiteralPath $JarPath)) { Fail "JAR not found: $JarPath" }
    Write-Step "Copying local JAR $JarPath ..."
    Copy-Item -LiteralPath $JarPath -Destination $jarDestination -Force
} else {
    Write-Step 'Downloading ServerPackCreator (about 76 MB)...'
    Write-Host ''
    try {
        Get-RemoteFile -Url $JarUrl -Destination $jarDestination
    } catch {
        # Do not leave a half-written JAR behind for the launchers to find.
        if (Test-Path -LiteralPath $jarDestination) {
            Remove-Item -LiteralPath $jarDestination -Force -ErrorAction SilentlyContinue
        }
        Fail @"
Download failed: $($_.Exception.Message)

    URL: $JarUrl

Check your internet connection, or whether a release has been published yet.
"@
    }
    Write-Host ''
}
$sizeMb = [math]::Round((Get-Item -LiteralPath $jarDestination).Length / 1MB, 1)
Write-Ok "Installed $JarFileName ($sizeMb MB)"

# ---------------------------------------------------------------- launchers

Write-Step 'Writing launchers...'
New-Launcher -Path (Join-Path $appDir "$AppName.bat")            -JavaExe $java.Path -JarFileName $JarFileName -ExtraArgs ''
New-Launcher -Path (Join-Path $appDir "$AppName-CLI.bat")        -JavaExe $java.Path -JarFileName $JarFileName -ExtraArgs '-cli' -Console
New-Launcher -Path (Join-Path $appDir "$AppName-WebService.bat") -JavaExe $java.Path -JarFileName $JarFileName -ExtraArgs '-web' -Console
Write-Ok 'Wrote ServerPackCreator.bat, -CLI.bat, -WebService.bat'

# ---------------------------------------------------------------- notice

# LGPL: a modified version has to carry its licence and a statement of changes.
Write-Step 'Installing licence and notice files...'
# Published as release assets rather than fetched from raw.githubusercontent.com: that host
# is a different domain from the one the JAR came from and is commonly unreachable even when
# github.com itself works. Same host as the JAR means if one download worked, these will too.
$docs = @(
    @{ Url = "https://github.com/$Repo/releases/latest/download/LICENSE";   Name = 'LICENSE' },
    @{ Url = "https://github.com/$Repo/releases/latest/download/NOTICE.md"; Name = 'NOTICE.md' }
)
foreach ($doc in $docs) {
    $tmp = Join-Path $env:TEMP "$AppName-$($doc.Name)"
    try {
        Invoke-WebRequest -Uri $doc.Url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        Copy-Item -LiteralPath $tmp -Destination (Join-Path $InstallDir $doc.Name) -Force
        Remove-Item -LiteralPath $tmp -Force
    } catch {
        Write-Warn2 "Could not install $($doc.Name): $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------- shortcut

Write-Step 'Creating Start Menu shortcut...'
try {
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut((Join-Path $startMenu "$AppName.lnk"))
    $lnk.TargetPath       = Join-Path $appDir "$AppName.bat"
    $lnk.WorkingDirectory = $appDir
    $lnk.Description      = $AppName
    $lnk.Save()
    Write-Ok 'Added to the Start Menu.'
} catch {
    Write-Warn2 "Could not create the Start Menu shortcut: $($_.Exception.Message)"
}

# ---------------------------------------------------------------- done

Write-Host "`nInstalled successfully.`n" -ForegroundColor Green
Write-Host "  Everything lives in:"
Write-Host "    $InstallDir"
Write-Host ''
Write-Host "  Start it from the Start Menu, or run:"
Write-Host "    $(Join-Path $InstallDir "$AppName.bat")"
Write-Host ''
Write-Host "  Configurations, server packs and logs are in that same folder."
Write-Host ''
Write-Host "  To remove it again:"
Write-Host "    ServerPackCreator-Setup.bat -Uninstall -Location `"$InstallDir`""
Write-Host ''
