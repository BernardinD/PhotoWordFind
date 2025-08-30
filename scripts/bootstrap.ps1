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

# Pre-warm winget sources to avoid first-run prompts/hangs
try {
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host "Pre-warming winget sources..." -ForegroundColor Cyan
        winget source list --accept-source-agreements --disable-interactivity | Out-Null
    }
} catch { }

# Ensure JDK 17 is installed and available
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
# Check if installed JDK is version 17
$needJdk = $true
$verCheck = Get-Command java -ErrorAction SilentlyContinue
if ($verCheck) {
    $verLine = (& java -version 2>&1)[0]
    if ($verLine -match '"(\d+)"') {
        if ([int]$Matches[1] -eq 17) { $needJdk = $false }
    }
}
if ($needJdk) {
    Write-Host "Warning: JAVA_HOME not set to JDK 17" -ForegroundColor Yellow
}

# Ensure Android Studio and command line tools are installed
$studioPackage = 'Google.AndroidStudio'
$studioCmd = Get-Command studio64.exe -ErrorAction SilentlyContinue
$studioInstalled = Is-WingetPackageInstalled $studioPackage
if (-not $studioCmd -or -not $studioInstalled) {
    Write-Host "Installing Android Studio via winget..."
    winget install -e --id $studioPackage --accept-source-agreements --accept-package-agreements --disable-interactivity
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

$sdkManager = "$Env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkManager)) {
    $sdkManager = "$Env:LOCALAPPDATA\Android\Sdk\tools\bin\sdkmanager.bat"
}
$needStudioSetup = $false
if (Test-Path $sdkManager) {
    Write-Host "Found Android cmdline tools." -ForegroundColor Green
} else {
    $needStudioSetup = $true
}
$studioProcess = $null

$jdkDir = Get-ChildItem "$Env:ProgramFiles\Eclipse Adoptium" -Directory -Filter 'jdk-17*' | Sort-Object Name -Descending | Select-Object -First 1
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

    $jdkLink = Join-Path $PSScriptRoot '..\.jdk'
    if (-not (Test-Path $jdkLink)) {
        # Use a junction instead of a symbolic link so admin privileges aren't
        # required. This still allows Gradle to locate the project's JDK without
        # modifying global paths.
        New-Item -ItemType Junction -Path $jdkLink -Target $env:PWF_JAVA_HOME | Out-Null
        Write-Host "Linked .jdk -> $env:PWF_JAVA_HOME" -ForegroundColor Green
    } else {
        Write-Host "JDK link already exists at $jdkLink" -ForegroundColor Yellow
    }
} else {
    Write-Warning "Unable to locate a Temurin JDK 17 under $Env:ProgramFiles. Android Studio may not have been run yet."
}



$adbPathEntry = "$Env:LOCALAPPDATA\Android\Sdk\platform-tools"
if (Test-Path $adbPathEntry) {
    $null = Ensure-PathEntry -Dir $adbPathEntry -ToolName 'Android platform-tools'
}

# Kick off Flutter SDK setup via VS Code (non-blocking). Actual pinning happens after Android Studio wizard closes.
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Host "Triggering Flutter extension to set up the SDK (you may see prompts in VS Code)..." -ForegroundColor Cyan
    try { Start-Process "vscode://command/flutter.changeSdk" 2>$null | Out-Null } catch { }
    try { Start-Process "vscode://command/flutter.doctor" 2>$null | Out-Null } catch { }
}

# Install Firebase CLI if missing
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

# Sign in to Firebase
Write-Host "Authenticating with Firebase..."
firebase login

# Launch Android Studio setup wizard if cmdline tools are missing
if ($needStudioSetup -and $studioCmd) {
    Write-Host "Starting Android Studio to complete SDK setup..."
    Write-Host "Please finish the wizard while the script continues running."
    $studioProcess = Start-Process -FilePath $studioCmd.Source -PassThru
}

# Fetch debug keystore
$keystorePath = Join-Path $PSScriptRoot "..\android\app\debug.keystore"
if (-not (Test-Path $keystorePath)) {
    Write-Host "Downloading debug keystore from Functions config..."
    $cfgOut = firebase functions:config:get $ConfigPath --project $ProjectId
    if ($LASTEXITCODE -eq 0 -and $cfgOut) {
        Write-Host "Raw config output: $cfgOut"
        $trim = $cfgOut.Trim()
        $base64 = $null
        if ($trim.StartsWith('{') -or $trim.StartsWith('[')) {
            try {
                Write-Host "Parsing JSON config..."
                $cfg = $trim | ConvertFrom-Json
                foreach ($seg in $ConfigPath -split '\\.') { $cfg = $cfg.$seg }
                $base64 = $cfg
            } catch {
                Write-Host "Failed to parse JSON config" -ForegroundColor Yellow
            }
        } else {
            if ($trim.StartsWith('"') -and $trim.EndsWith('"')) {
                Write-Host "Stripping quotes from config string..."
                $base64 = $trim.Trim('"')
            } else {
                $base64 = $trim
            }
        }
        if ($base64) {
            Write-Host "Writing keystore to $keystorePath"
            [IO.File]::WriteAllBytes($keystorePath, [Convert]::FromBase64String($base64))
        } else {
            Write-Host "No keystore config found" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Failed to fetch keystore config" -ForegroundColor Yellow
    }
} else {
    Write-Host "Keystore already exists at $keystorePath" -ForegroundColor Green
}

# Calculate SHA-1 fingerprint and add to Firebase if app id provided
$keytool = (Get-Command keytool).Source
$fingerprint = & $keytool -list -v -keystore $keystorePath -alias androiddebugkey -storepass android -keypass android |
    Select-String 'SHA1:' | ForEach-Object { $_.ToString().Replace('SHA1:', '').Trim() }
Write-Host "Keystore SHA-1 fingerprint is $fingerprint"

Write-Host "Checking Firebase app for existing fingerprint..."
# Normalize fingerprint: remove colons and lowercase
$normFingerprint = ($fingerprint -replace ':','').ToLower()
# Fetch existing SHA hashes and normalize
$existingJson = firebase apps:android:sha:list $FirebaseAppId --project $ProjectId --json 2>$null
$existing = @()
if ($LASTEXITCODE -eq 0 -and $existingJson) {
    try {
        $convertedJson = $existingJson | ConvertFrom-Json
        $existing = $convertedJson.result | ForEach-Object { $_.shaHash.ToLower() }
    } catch {
        Write-Host "Failed to parse Firebase JSON response." -ForegroundColor Yellow
    }
}

if ($existing -contains $normFingerprint) {
    Write-Host "Fingerprint already registered." -ForegroundColor Green
} else {
    Write-Host "Registering SHA-1 fingerprint with Firebase..." -ForegroundColor Green
    firebase apps:android:sha:create $FirebaseAppId $normFingerprint --project $ProjectId
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SHA-1 fingerprint registered successfully." -ForegroundColor Green
    } else {
        Write-Host "Failed to register fingerprint." -ForegroundColor Yellow
    }
}

# Wait for Android Studio wizard if it was started
if ($studioProcess) {
    Write-Host "Waiting for Android Studio setup to finish..."
    Wait-Process -Id $studioProcess.Id
    Refresh-SessionPath
    $sdkManager = "$Env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat"
    if (Test-Path $sdkManager) {
        Write-Host "Installing Android cmdline tools..."
        & $sdkManager --install "cmdline-tools;latest" "platform-tools" | Out-Null
    } else {
        Write-Host "SDK manager still not found" -ForegroundColor Yellow
    }
}

# After Android Studio setup, pause briefly, then check Flutter once and pin if available
Write-Host "Preparing to finalize Flutter SDK setup..." -ForegroundColor Yellow
$resp = Read-Host "Press Enter to wait 5 seconds, or type 's' to skip the wait if Flutter is already installed"
if (($resp | ForEach-Object { $_.ToString().Trim().ToLower() }) -ne 's') {
    Write-Host "Sleeping 5 seconds before checking for Flutter..." -ForegroundColor DarkYellow
    Start-Sleep -Seconds 5
}

Refresh-SessionPath
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCmd) {
    try {
        $verText = & $flutterCmd.Source --version 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $verText) { throw "Flutter command not ready" }
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

# Mark bootstrap complete
$flagPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.bootstrap_complete'
Write-Host "Marking bootstrap complete at $flagPath" -ForegroundColor Green
Set-Content -Path $flagPath -Value 'ok'

# Ensure Windows Developer Mode is enabled for Flutter deployment
$devModeRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$devModeEnabled = $false
try {
    $reg = Get-ItemProperty -Path $devModeRegPath -ErrorAction Stop
    if ($reg -and $reg.AllowDevelopmentWithoutDevLicense -eq 1) {
        $devModeEnabled = $true
    }
} catch {
    # Key may not exist if never enabled
}
if (-not $devModeEnabled) {
    Write-Host "Windows Developer Mode is not enabled. Opening Developer Mode settings..." -ForegroundColor Cyan
    Start-Process "ms-settings:developers"
    Write-Host "Please enable Developer Mode in the settings window for Flutter deployment."
} else {
    Write-Host "Windows Developer Mode is already enabled." -ForegroundColor Green
}
