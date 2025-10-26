<#
Bootstrap script for personal_voice_notes Flutter project.

This is a template adapted from an existing project's bootstrap script. Fill in the TODOs below before running.

TODOs you MUST fill in:
 - $ConfigPath: path (dot-separated) in Firebase Functions config which contains a base64 keystore string, e.g. 'myapp.keystore'

Notes:
 - Run this script in PowerShell (Windows) as a normal user. Some operations (setx, creating junctions) may need elevation.
 - This script will try to install tools via winget when missing. Ensure winget is available.
 - The script will attempt to use the Firebase CLI. You must login (the script calls `firebase login`).
 - Review sections marked NOTE/REVIEW before using in CI.
#>

param(
    [string]$ConfigPath = "photowordfind.keystore"
)

Write-Host "Starting PhotoWordFind bootstrap..."

# Firebase project used for authentication and configs
$ProjectId = 'pwfapp-f314d'

# Firebase app id used for automatic SHA-1 registration
$FirebaseAppId = '1:1082599556322:android:66fb03c1d8192758440abb'

# Refreshes the PATH for the current session so newly installed CLIs are
# immediately available. This uses only persisted Machine + User PATH.
function Refresh-SessionPath {
    Write-Host "Refreshing session PATH..."
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = "$machinePath;$userPath"
}

# Returns $true when the given winget package id is installed
function Is-WingetPackageInstalled($id) {
    $out = winget list --id $id -e --accept-source-agreements --disable-interactivity 2>$null
    return ($LASTEXITCODE -eq 0 -and $out -and $out -notmatch 'No installed')
}

# Returns $true if a directory path is present in a PATH string (case-insensitive, trailing slashes ignored)
function Test-PathContainsEntry {
    param(
        [Parameter(Mandatory=$true)][string]$Dir,
        [Parameter(Mandatory=$true)][string]$PathString
    )
    function _Norm([string]$p) {
        if (-not $p) { return '' }
        $e = [Environment]::ExpandEnvironmentVariables($p).Trim().Trim('"')
        $e = $e.TrimEnd('\\')
        return $e.ToLowerInvariant()
    }
    $target = _Norm $Dir
    $entriesNormalized = (
        $PathString -split ';' |
        Where-Object { $_ -and $_.Trim() -ne '' } |
        ForEach-Object { _Norm $_ }
    )
    return ($entriesNormalized -contains $target)
}

# Ensures a directory is present in persistent User PATH. If changed, refreshes session.
function Ensure-PathEntry {
    param(
        [Parameter(Mandatory=$true)][string]$Dir,
        [string]$ToolName = 'Tool'
    )
    $Dir = $Dir.Trim().Trim('"')
    if (-not $Dir) { return $false }

    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $persisted   = "$machinePath;$userPath"

    if (Test-PathContainsEntry -Dir $Dir -PathString $persisted) {
        Write-Host "$ToolName path already present in persisted PATH." -ForegroundColor Green
        return $true
    }

    Write-Host "Persisting $ToolName path to User PATH: $Dir"
    $newUserPath = "$Dir;" + $userPath
    setx Path $newUserPath | Out-Null

    Refresh-SessionPath

    $finalUser = [Environment]::GetEnvironmentVariable('Path', 'User')
    $predicted = "$machinePath;$finalUser"
    $ok = Test-PathContainsEntry -Dir $Dir -PathString $predicted
    if ($ok) {
        Write-Host "$ToolName path ensured in persistence." -ForegroundColor Green
    } else {
        Write-Host "Warning: $ToolName path not found in persisted PATH after update." -ForegroundColor Yellow
    }
    return $ok
}

# Tries to resolve a command now; if not found, refresh PATH and try again. If found, ensures its directory persists.
function Ensure-CommandPersistence {
    param(
        [Parameter(Mandatory=$true)][string]$CommandName,
        [string]$ToolName = $null
    )
    if (-not $ToolName) { $ToolName = $CommandName }

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Refresh-SessionPath
        $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Host "Error: $ToolName command '$CommandName' not found after install and PATH refresh." -ForegroundColor Red
            return $false
        }
    }

    $dir = Split-Path $cmd.Source
    return (Ensure-PathEntry -Dir $dir -ToolName $ToolName)
}

# Pre-warm winget (avoid prompts on first run)
try {
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host "Pre-warming winget sources..." -ForegroundColor Cyan
        winget source list --accept-source-agreements --disable-interactivity | Out-Null
    }
} catch { }

# -------------- Ensure JDK 17 --------------
Write-Host "== JDK setup ==" -ForegroundColor Cyan
$jdkPackage = 'EclipseAdoptium.Temurin.17.JDK'
$javaCmd = Get-Command java -ErrorAction SilentlyContinue
$jdkInstalled = Is-WingetPackageInstalled $jdkPackage
if (-not $javaCmd -or -not $jdkInstalled) {
    Write-Host "Installing JDK 17 via winget..."
    winget install -e --id $jdkPackage --accept-source-agreements --accept-package-agreements --disable-interactivity
    $null = Ensure-CommandPersistence -CommandName 'java' -ToolName 'JDK 17'
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
} else {
    Write-Host "JDK 17 is already installed and available." -ForegroundColor Green
}

# Optional: set JAVA_HOME to Adoptium installation if found
# Check if installed JDK is version 17
$jdkDir = Get-ChildItem "$Env:ProgramFiles\Eclipse Adoptium" -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
if ($jdkDir) {
    $env:PWF_JAVA_HOME = $jdkDir.FullName
    $env:JAVA_HOME = $env:PWF_JAVA_HOME

    $persistHome = [Environment]::GetEnvironmentVariable('PWF_JAVA_HOME', 'User')
    if (-not $persistHome -or $persistHome -ne $env:PWF_JAVA_HOME) {
        Write-Host "Persisting PWF_JAVA_HOME..."
        setx PWF_JAVA_HOME $env:PWF_JAVA_HOME | Out-Null
    }

    $jdkPathEntry = "$env:PWF_JAVA_HOME\bin"
    $null = Ensure-PathEntry -Dir $jdkPathEntry -ToolName 'JDK 17'
} else {
    Write-Host "Warning: Unable to locate a Temurin JDK 17 under Program Files. Ensure JDK 17 is installed and JAVA_HOME points to it." -ForegroundColor Yellow
}

# Print Java version (best-effort)
try {
    $jv = (& java -version 2>&1 | Select-Object -First 1)
    if ($jv) { Write-Host "Java detected: $jv" -ForegroundColor DarkGreen }
} catch { }

# -------------- Android Studio & SDK tools --------------
Write-Host "== Android Studio & SDK tools ==" -ForegroundColor Cyan
$studioPackage = 'Google.AndroidStudio'
$studioCmd = Get-Command studio64.exe -ErrorAction SilentlyContinue
$studioInstalled = Is-WingetPackageInstalled $studioPackage
if (-not $studioCmd -or -not $studioInstalled) {
    Write-Host "Installing Android Studio via winget..."
    winget install -e --id $studioPackage --accept-source-agreements --accept-package-agreements --disable-interactivity --no-upgrade
    $null = Ensure-CommandPersistence -CommandName 'studio64.exe' -ToolName 'Android Studio'
    $studioCmd = Get-Command studio64.exe -ErrorAction SilentlyContinue
} else {
    Write-Host "Android Studio is already installed and available." -ForegroundColor Green
}

# Guarantee studio64.exe is reachable from PATH
if (-not $studioCmd) {
    $searchDirs = @(
        "$env:LOCALAPPDATA\Programs\Android\Android Studio\bin",
        "$env:ProgramFiles\Android\Android Studio\bin",
        "$env:ProgramFiles\Google\Android Studio\bin"
    )
    foreach ($d in $searchDirs) {
        $candidate = Join-Path $d 'studio64.exe'
        if (Test-Path $candidate) { $studioCmd = @{ Source = $candidate }; break }
    }
}
if ($studioCmd) {
    $studioDir = Split-Path $studioCmd.Source
    $null = Ensure-PathEntry -Dir $studioDir -ToolName 'Android Studio'
} else {
    Write-Host "Android Studio executable not found" -ForegroundColor Yellow
}

# Try to locate sdkmanager
$sdkManager = "$Env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkManager)) {
    $sdkManager = "$Env:LOCALAPPDATA\Android\Sdk\tools\bin\sdkmanager.bat"
}
if (Test-Path $sdkManager) {
    Write-Host "Found Android cmdline tools." -ForegroundColor Green
    Write-Host "sdkmanager path: $sdkManager" -ForegroundColor DarkGreen
} else {
    Write-Host "Android cmdline tools not found. You may be prompted to finish Android Studio setup." -ForegroundColor Yellow
}

$adbPathEntry = "$Env:LOCALAPPDATA\Android\Sdk\platform-tools"
if (Test-Path $adbPathEntry) { $null = Ensure-PathEntry -Dir $adbPathEntry -ToolName 'Android platform-tools' }
if (Test-Path $adbPathEntry) { Write-Host "Platform-tools directory present: $adbPathEntry" -ForegroundColor DarkGreen }

# Attempt to install SDK command-line tools and platform-tools directly if missing
if (-not (Test-Path $sdkManager)) {
    Write-Host "== SDK direct install (no Android Studio) ==" -ForegroundColor Cyan
    Write-Host "Attempting direct install of Android SDK tools..." -ForegroundColor Cyan

    # Helpers
    function Ensure-Dir([string]$p) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
    function Download-File([string]$url, [string]$outPath) {
        Write-Host "Downloading: $url" -ForegroundColor DarkCyan
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $outPath -ErrorAction Stop
            return $true
        } catch {
            Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Yellow
            return $false
        }
    }
    function Expand-Zip([string]$zipPath, [string]$destDir) {
        Write-Host "Extracting $zipPath to $destDir" -ForegroundColor DarkCyan
        Ensure-Dir $destDir
        try { Expand-Archive -Path $zipPath -DestinationPath $destDir -Force ; return $true } catch { Write-Host "Extract failed: $($_.Exception.Message)" -ForegroundColor Yellow ; return $false }
    }

    $sdkRoot = Join-Path $Env:LOCALAPPDATA 'Android\Sdk'
    Ensure-Dir $sdkRoot

    # 1) Platform-tools (latest URL is stable)
    $ptUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
    $ptZip = Join-Path $env:TEMP 'platform-tools-latest-windows.zip'
    if (-not (Test-Path (Join-Path $sdkRoot 'platform-tools'))) {
        Write-Host "Fetching platform-tools from: $ptUrl" -ForegroundColor DarkCyan
        if (Download-File $ptUrl $ptZip) {
            if (Expand-Zip $ptZip $sdkRoot) {
                $ptPath = Join-Path $sdkRoot 'platform-tools'
                if (Test-Path $ptPath) {
                    Write-Host "Extracted platform-tools to: $ptPath" -ForegroundColor DarkGreen
                    $null = Ensure-PathEntry -Dir $ptPath -ToolName 'Android platform-tools'
                    try {
                        $adbExe = Join-Path $ptPath 'adb.exe'
                        if (Test-Path $adbExe) {
                            $adbVer = & $adbExe --version | Select-Object -First 1
                        } else {
                            $adbCmd = Get-Command adb -ErrorAction SilentlyContinue
                            if ($adbCmd) { $adbVer = & $adbCmd.Source --version | Select-Object -First 1 }
                        }
                        if ($adbVer) { Write-Host "adb: $adbVer" -ForegroundColor DarkGreen }
                    } catch { }
                }
            }
        }
    }

    # 2) Command-line tools (determine latest dynamically from repository XML; fallback to known build if needed)
    $cltUrl = $null
    try {
        $repoXmlUrl = 'https://dl.google.com/android/repository/repository2-1.xml'
        $xmlTmp = Join-Path $env:TEMP 'android-repository2-1.xml'
        if (Download-File $repoXmlUrl $xmlTmp) {
            [xml]$repo = Get-Content $xmlTmp
            # Find remotePackage path='cmdline-tools' with a Windows archive
            $pkgs = $repo.SelectNodes("//*[local-name()='remotePackage' and @path='cmdline-tools']")
            if ($pkgs -and $pkgs.Count -gt 0) {
                # Pick the first package that has a windows archive with complete/url
                foreach ($p in $pkgs) {
                    $archives = $p.SelectNodes(".//*[local-name()='archive'][.//*[local-name()='host-os' and (text()='windows' or text()='any')]]")
                    foreach ($a in $archives) {
                        $urlNode = $a.SelectSingleNode(".//*[local-name()='complete']/*[local-name()='url']")
                        if ($urlNode -and $urlNode.InnerText -like 'commandlinetools-win*-latest.zip') {
                            $cltUrl = 'https://dl.google.com/android/repository/' + $urlNode.InnerText
                            break
                        }
                    }
                    if ($cltUrl) { break }
                }
            }
        }
    } catch { Write-Host "Failed to resolve cmdline-tools URL dynamically: $($_.Exception.Message)" -ForegroundColor Yellow }

    if (-not $cltUrl) {
        # Fallback to current public filename from Android Studio downloads page (updated Oct 2025)
        $cltUrl = 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip'
        Write-Host "Using fallback cmdline-tools URL: $cltUrl" -ForegroundColor Yellow
    }
    if ($cltUrl) { Write-Host "cmdline-tools URL resolved: $cltUrl" -ForegroundColor DarkCyan }

    $cltZip = Join-Path $env:TEMP (Split-Path $cltUrl -Leaf)
    $cltExtractTmp = Join-Path $env:TEMP 'cmdline-tools-extract'

    $installed = Test-Path (Join-Path $Env:LOCALAPPDATA 'Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat')
    if (-not $installed) {
        if (Download-File $cltUrl $cltZip) {
            if (Expand-Zip $cltZip $cltExtractTmp) {
                $srcCmdTools = Join-Path $cltExtractTmp 'cmdline-tools'
                if (Test-Path $srcCmdTools) {
                    $destRoot = Join-Path $sdkRoot 'cmdline-tools'
                    $destLatest = Join-Path $destRoot 'latest'
                    if (Test-Path $destLatest) { try { Remove-Item -Recurse -Force $destLatest } catch { } }
                    Ensure-Dir $destLatest
                    try {
                        Copy-Item -Recurse -Force (Join-Path $srcCmdTools '*') $destLatest
                        $sdkManager = Join-Path $destLatest 'bin\sdkmanager.bat'
                        if (Test-Path $sdkManager) {
                            $null = Ensure-PathEntry -Dir (Join-Path $destLatest 'bin') -ToolName 'Android cmdline-tools'
                            Write-Host "Android command-line tools installed at: $destLatest" -ForegroundColor Green
                            try { $sdkv = & $sdkManager --version 2>$null ; if ($sdkv) { Write-Host "sdkmanager: $sdkv" -ForegroundColor DarkGreen } } catch { }
                        } else {
                            Write-Host "sdkmanager not found after extraction." -ForegroundColor Yellow
                        }
                    } catch { Write-Host "Failed to finalize cmdline-tools install: $($_.Exception.Message)" -ForegroundColor Yellow }
                } else {
                    Write-Host "Unexpected archive structure: 'cmdline-tools' folder not found in zip." -ForegroundColor Yellow
                }
            }
        }
    }
}

# -------------- Flutter SDK --------------
Write-Host "== Flutter SDK ==" -ForegroundColor Cyan
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Host "Triggering VS Code Flutter extension to set up the SDK (non-blocking)..." -ForegroundColor Cyan
    try { Start-Process "vscode://command/flutter.changeSdk" 2>$null | Out-Null } catch { }
    try { Start-Process "vscode://command/flutter.doctor" 2>$null | Out-Null } catch { }
} else {
    Write-Host "Flutter already available." -ForegroundColor Green
}

# (Version pinning is handled later once the Flutter CLI is confirmed ready.)

# -------------- Firebase CLI --------------
Write-Host "== Firebase CLI ==" -ForegroundColor Cyan
$firebasePackage = 'Google.FirebaseCLI'
$firebaseCmd = Get-Command firebase -ErrorAction SilentlyContinue
$firebaseInstalled = Is-WingetPackageInstalled $firebasePackage
if (-not $firebaseCmd -or -not $firebaseInstalled) {
    Write-Host "Installing Firebase CLI via winget..."
    winget install -e --id $firebasePackage --accept-source-agreements --accept-package-agreements --disable-interactivity
    $null = Ensure-CommandPersistence -CommandName 'firebase' -ToolName 'Firebase CLI'
    $firebaseCmd = Get-Command firebase -ErrorAction SilentlyContinue
} else {
    Write-Host "Firebase CLI is already installed and available." -ForegroundColor Green
}

# Print Firebase CLI version (best-effort)
try { $fbv = (& firebase --version 2>$null) ; if ($fbv) { Write-Host "firebase: $fbv" -ForegroundColor DarkGreen } } catch { }

Write-Host "Authenticating with Firebase (you may be prompted)..."
# NOTE: this will open a browser for interactive login. If you plan to run in CI, skip this and use service account credentials.
try { firebase login } catch { Write-Host "firebase login failed or interrupted." -ForegroundColor Yellow }

# -------------- Fetch debug keystore from Firebase functions config (optional) --------------
Write-Host "== Keystore fetch from Firebase functions config ==" -ForegroundColor Cyan
$keystorePath = Join-Path $PSScriptRoot "..\android\app\debug.keystore"
if (-not (Test-Path $keystorePath) -and $ConfigPath -and $ProjectId -and $ConfigPath -ne '<KEYSTORE_CONFIG_PATH>') {
    Write-Host "Attempting to fetch keystore from Firebase Functions config ($ConfigPath)..."
    $cfgOut = firebase functions:config:get $ConfigPath --project $ProjectId 2>$null
    if ($LASTEXITCODE -eq 0 -and $cfgOut) {
        $trim = $cfgOut.Trim()
        $base64 = $null
        if ($trim.StartsWith('{') -or $trim.StartsWith('[')) {
            try {
                $cfg = $trim | ConvertFrom-Json
                foreach ($seg in $ConfigPath -split '\\.') { $cfg = $cfg.$seg }
                $base64 = $cfg
            } catch {
                Write-Host "Failed to parse JSON config: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            if ($trim.StartsWith('"') -and $trim.EndsWith('"')) { $base64 = $trim.Trim('"') } else { $base64 = $trim }
        }
        if ($base64) {
            Write-Host "Writing keystore to $keystorePath"
            try { [IO.File]::WriteAllBytes($keystorePath, [Convert]::FromBase64String($base64)) ; Write-Host "Keystore written." -ForegroundColor Green } catch { Write-Host "Failed to write keystore: $($_.Exception.Message)" -ForegroundColor Yellow }
        } else {
            Write-Host "No keystore data found in config." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Failed to fetch keystore config from Firebase (or config missing)." -ForegroundColor Yellow
    }
} else {
    if (Test-Path $keystorePath) { Write-Host "Keystore already exists at $keystorePath" -ForegroundColor Green }
}

# -------------- Calculate SHA-1 and optionally register with Firebase --------------
Write-Host "== Keystore fingerprint & Firebase registration ==" -ForegroundColor Cyan
try {
    $keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
    if ($keytool -and (Test-Path $keystorePath)) {
        $fingerprint = & $keytool -list -v -keystore $keystorePath -alias androiddebugkey -storepass android -keypass android |
            Select-String 'SHA1:' | ForEach-Object { $_.ToString().Replace('SHA1:', '').Trim() }
        Write-Host "Keystore SHA-1 fingerprint is $fingerprint"

        if ($FirebaseAppId -and $FirebaseAppId -ne '<FIREBASE_ANDROID_APP_ID>' -and $ProjectId -and $ProjectId -ne '<FIREBASE_PROJECT_ID>') {
            Write-Host "Checking Firebase app for existing fingerprint..."
            $normFingerprint = ($fingerprint -replace ':','').ToLower()
            $existingJson = firebase apps:android:sha:list $FirebaseAppId --project $ProjectId --json 2>$null
            if ($LASTEXITCODE -eq 0 -and $existingJson) {
                try {
                    $convertedJson = $existingJson | ConvertFrom-Json
                    $existing = $convertedJson.result | ForEach-Object { $_.shaHash.ToLower() }
                } catch { $existing = @() }
                if ($existing -contains $normFingerprint) {
                    Write-Host "Fingerprint already registered." -ForegroundColor Green
                } else {
                    Write-Host "Registering SHA-1 fingerprint with Firebase..."
                    firebase apps:android:sha:create $FirebaseAppId $normFingerprint --project $ProjectId
                    if ($LASTEXITCODE -eq 0) { Write-Host "SHA-1 fingerprint registered successfully." -ForegroundColor Green } else { Write-Host "Failed to register fingerprint." -ForegroundColor Yellow }
                }
            } else {
                Write-Host "Unable to list existing Android app SHA hashes from Firebase." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Firebase app id or project id not set; skipping SHA-1 registration." -ForegroundColor Yellow
        }
    } else {
        Write-Host "keytool not found or keystore missing; skipping SHA-1 steps." -ForegroundColor Yellow
    }
} catch { Write-Host "Error while computing/ registering fingerprint: $($_.Exception.Message)" -ForegroundColor Yellow }

# Removed Android Studio wizard wait; direct download path installs tools when missing.

# After Android Studio setup, pause briefly, then check Flutter once and pin if available
Write-Host "Preparing to finalize Flutter SDK setup..." -ForegroundColor Yellow
$resp = Read-Host "Press Enter to wait 5 seconds, or type 's' to skip the wait if Flutter is already installed"
if ($resp.Trim().ToLower() -ne 's') {
    Write-Host "Sleeping 5 seconds before checking for Flutter..." -ForegroundColor DarkYellow
    Start-Sleep -Seconds 5
}

Refresh-SessionPath
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCmd) {
    try {
        $verText = & $flutterCmd.Source --version 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $verText) { throw "Flutter command not ready" }
        else { Write-Host ("Flutter detected: " + ($verText -split "`n")[0]) -ForegroundColor DarkGreen }
    } catch {
        Write-Host "Flutter command found but not ready. Skipping version pin for now." -ForegroundColor Yellow
        $flutterCmd = $null
    }
}

if ($flutterCmd) {
    $flutterBin = Split-Path $flutterCmd.Source
    $null = Ensure-PathEntry -Dir $flutterBin -ToolName 'Flutter'
    $flutterRoot = (Split-Path $flutterBin -Parent)
    $desiredFlutterVersion = "3.24.5"
    $currentFlutterVersion = (& $flutterCmd.Source --version 2>$null | Select-String -Pattern "^Flutter\s+([0-9\.]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })[0]
    $gitDir = Join-Path $flutterRoot '.git'
    if (Test-Path $gitDir) {
        if ($currentFlutterVersion -ne $desiredFlutterVersion) {
            Push-Location $flutterRoot
            try {
                git fetch --tags
                git checkout $desiredFlutterVersion
            } catch {
                Write-Host "Warning: Failed to switch Flutter to $desiredFlutterVersion. Continuing with current version." -ForegroundColor Yellow
            }
            Pop-Location
        } else {
            Write-Host "Flutter $desiredFlutterVersion already checked out." -ForegroundColor Green
        }
    } else {
        if ($currentFlutterVersion -and $currentFlutterVersion -ne $desiredFlutterVersion) {
            Write-Host "Flutter SDK is not a git checkout; cannot pin to $desiredFlutterVersion automatically. Current: $currentFlutterVersion" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Flutter not detected after brief wait; skipping version pin." -ForegroundColor Yellow
}

# -------------- Windows developer mode hint --------------
Write-Host "== Windows Developer Mode check ==" -ForegroundColor Cyan
$devModeRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$devModeEnabled = $false
try {
    $reg = Get-ItemProperty -Path $devModeRegPath -ErrorAction Stop
    if ($reg -and $reg.AllowDevelopmentWithoutDevLicense -eq 1) { $devModeEnabled = $true }
} catch { }
if (-not $devModeEnabled) {
    Write-Host "Windows Developer Mode is not enabled. Opening Developer Mode settings..." -ForegroundColor Cyan
    try { Start-Process "ms-settings:developers" } catch { }
    Write-Host "Please enable Developer Mode in the settings window for Flutter deployment." -ForegroundColor Yellow
} else {
    Write-Host "Windows Developer Mode is already enabled." -ForegroundColor Green
}

# -------------- Finish --------------
$flagPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.bootstrap_complete'
Write-Host "Marking bootstrap complete at $flagPath" -ForegroundColor Green
try { Set-Content -Path $flagPath -Value 'ok' } catch { }

Write-Host "Bootstrap finished. Review TODOs at the top of this file if any settings remain." -ForegroundColor Cyan
