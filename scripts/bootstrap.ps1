param(
    [string]$ConfigPath = "photowordfind.keystore"
)

Write-Host "Starting PhotoWordFind bootstrap..."

# Firebase project used for authentication and configs
$ProjectId = 'pwfapp-f314d'

# Firebase app id used for automatic SHA-1 registration
$FirebaseAppId = '1:1082599556322:android:66fb03c1d8192758440abb'

# Refreshes the PATH for the current session so newly installed CLIs are
# immediately available.
function Refresh-SessionPath {
    Write-Host "Refreshing session PATH..."
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = "$machinePath;$userPath"
}

# Returns $true when the given winget package id is installed
function Is-WingetPackageInstalled($id) {
    $out = winget list --id $id -e 2>$null
    return ($LASTEXITCODE -eq 0 -and $out -and $out -notmatch 'No installed')
}

# Ensure JDK 17 is installed and available
$jdkPackage = 'EclipseAdoptium.Temurin.17.JDK'
$javaCmd = Get-Command java -ErrorAction SilentlyContinue
if (-not $javaCmd) {
    if (-not (Is-WingetPackageInstalled $jdkPackage)) {
        Write-Host "Installing JDK 17 via winget..."
        winget install -e --id $jdkPackage
        Refresh-SessionPath
    } else {
        Write-Host "JDK package already installed." -ForegroundColor Green
    }
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
} else {
    Write-Host "Java command already available." -ForegroundColor Green
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
if (-not $studioCmd) {
    if (-not (Is-WingetPackageInstalled $studioPackage)) {
        Write-Host "Installing Android Studio via winget..."
        winget install -e --id $studioPackage
        Refresh-SessionPath
    } else {
        Write-Host "Android Studio package already installed." -ForegroundColor Green
    }
    $studioCmd = Get-Command studio64.exe -ErrorAction SilentlyContinue
} else {
    Write-Host "Android Studio command already available." -ForegroundColor Green
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
    $persistPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not ($persistPath -split ';' | Where-Object { $_ -eq $studioDir })) {
        Write-Host "Adding Android Studio to user PATH..."
        setx Path "$studioDir;" + $persistPath | Out-Null
    }
    if ($env:Path -notlike "$studioDir*") { $env:Path = "$studioDir;" + $env:Path }
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

    $persistPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $jdkPathEntry = "$env:PWF_JAVA_HOME\bin"
    if (-not ($persistPath -split ';' | Where-Object { $_ -eq $jdkPathEntry })) {
        Write-Host "Adding JDK 17 to user PATH..."
        $newPath = "$jdkPathEntry;" + $persistPath
        setx Path $newPath | Out-Null
    }

    if ($env:Path -notlike "$jdkPathEntry*") {
        $env:Path = "$jdkPathEntry;" + $env:Path
    }

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
    $persistPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not ($persistPath -split ';' | Where-Object { $_ -eq $adbPathEntry })) {
        Write-Host "Adding Android platform-tools to user PATH..."
        setx Path "$adbPathEntry;" + $persistPath | Out-Null
    }
    if ($env:Path -notlike "$adbPathEntry*") {
        $env:Path = "$adbPathEntry;" + $env:Path
    }
}

# Ensure Flutter is installed and on PATH
$flutterPackage = 'Flutter.Flutter'
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    if (-not (Is-WingetPackageInstalled $flutterPackage)) {
        Write-Host "Installing Flutter via winget..."
        winget install -e --id $flutterPackage
        Refresh-SessionPath
    } else {
        Write-Host "Flutter package already installed." -ForegroundColor Green
    }
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
} else {
    Write-Host "Flutter command already available." -ForegroundColor Green
}
if (-not $flutterCmd) {
    $searchDirs = @(
        "$env:LOCALAPPDATA\Programs\flutter\bin",
        "$env:ProgramFiles\flutter\bin",
        "$env:ProgramFiles(x86)\flutter\bin"
    )
    foreach ($d in $searchDirs) {
        $candidate = Join-Path $d 'flutter.bat'
        if (Test-Path $candidate) { $flutterCmd = @{ Source = $candidate }; break }
    }
}
if ($flutterCmd) {
    $flutterBin = Split-Path $flutterCmd.Source
    $persistPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not ($persistPath -split ';' | Where-Object { $_ -eq $flutterBin })) {
        Write-Host "Adding Flutter to user PATH..."
        setx Path "$flutterBin;" + $persistPath | Out-Null
    }
    if ($env:Path -notlike "$flutterBin*") { $env:Path = "$flutterBin;" + $env:Path }
    Push-Location (Split-Path $flutterBin -Parent)
    $desiredFlutterVersion = "3.24.5"
    $currentFlutterVersion = (& $flutterCmd.Source --version 2>$null | Select-String -Pattern "^Flutter\s+([0-9\.]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })[0]
    if ($currentFlutterVersion -ne $desiredFlutterVersion) {
        git fetch --tags
        git checkout $desiredFlutterVersion
    } else {
        Write-Host "Flutter $desiredFlutterVersion already checked out." -ForegroundColor Green
    }
    Pop-Location
} else {
    Write-Host "Flutter executable not found" -ForegroundColor Yellow
}

# Install Firebase CLI if missing
$firebasePackage = 'Google.FirebaseCLI'
$firebaseCmd = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $firebaseCmd) {
    if (-not (Is-WingetPackageInstalled $firebasePackage)) {
        Write-Host "Installing Firebase CLI via winget..."
        winget install -e --id $firebasePackage
        Refresh-SessionPath
    } else {
        Write-Host "Firebase CLI package already installed." -ForegroundColor Green
    }
    $firebaseCmd = Get-Command firebase -ErrorAction SilentlyContinue
} else {
    Write-Host "Firebase command already available." -ForegroundColor Green
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

# Install Google Cloud CLI if missing for OAuth client management
$gcloudPackage = 'Google.CloudSDK'
$gcloudCmd = Get-Command gcloud -ErrorAction SilentlyContinue
if (-not $gcloudCmd) {
    if (-not (Is-WingetPackageInstalled $gcloudPackage)) {
        Write-Host "Installing Google Cloud CLI via winget..."
        winget install -e --id $gcloudPackage
        Refresh-SessionPath
    } else {
        Write-Host "Google Cloud CLI package already installed." -ForegroundColor Green
    }
    $gcloudCmd = Get-Command gcloud -ErrorAction SilentlyContinue
} else {
    Write-Host "Google Cloud CLI already available." -ForegroundColor Green
}

# Configure GCP project for OAuth with automated client creation
if ($gcloudCmd) {
    Write-Host "Configuring GCP project for OAuth..." -ForegroundColor Cyan
    
    # Authenticate with Google Cloud if not already signed in
    Write-Host "Checking Google Cloud authentication..."
    $authStatus = & gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null
    if (-not $authStatus -or $LASTEXITCODE -ne 0) {
        Write-Host "Google Cloud authentication required. Opening browser for sign-in..." -ForegroundColor Yellow
        & gcloud auth login --project $ProjectId
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to authenticate with Google Cloud. Please run 'gcloud auth login' manually." -ForegroundColor Red
            return
        }
        Write-Host "Google Cloud authentication successful!" -ForegroundColor Green
    } else {
        Write-Host "Already authenticated with Google Cloud as: $authStatus" -ForegroundColor Green
    }
    
    Write-Host "Setting project to $ProjectId"
    & gcloud config set project $ProjectId
    
    # Verify project access
    $projectAccess = & gcloud projects describe $ProjectId --format="value(projectId)" 2>$null
    if ($LASTEXITCODE -ne 0 -or $projectAccess -ne $ProjectId) {
        Write-Host "Cannot access project $ProjectId. Please ensure you have proper permissions." -ForegroundColor Red
        Write-Host "You may need to be added as an owner/editor to the project." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Enabling required APIs..."
    & gcloud services enable oauth2.googleapis.com --project $ProjectId
    & gcloud services enable iap.googleapis.com --project $ProjectId
    
    # Check if OAuth consent screen is configured
    Write-Host "Checking OAuth consent screen configuration..."
    $consentStatus = & gcloud alpha oauth2 brands list --project $ProjectId --format="value(name)" 2>$null
    if (-not $consentStatus -or $LASTEXITCODE -ne 0) {
        Write-Host "OAuth consent screen setup required:" -ForegroundColor Yellow
        Write-Host "Please complete OAuth consent screen: https://console.cloud.google.com/apis/credentials/consent?project=$ProjectId" -ForegroundColor Yellow
        Write-Host "Press any key after completing the consent screen setup..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        Write-Host "OAuth consent screen already configured." -ForegroundColor Green
    }
    
    # Create or update Android OAuth client with SHA-1 fingerprint
    $packageName = "com.example.PhotoWordFind"
    $clientName = "PhotoWordFind-Android-Client"
    
    Write-Host "Creating/updating Android OAuth client with SHA-1 fingerprint..."
    
    # Check if client already exists
    $existingClients = & gcloud alpha oauth2 clients list --project $ProjectId --format="value(name,displayName)" 2>$null
    $clientExists = $false
    if ($LASTEXITCODE -eq 0 -and $existingClients) {
        $clientExists = $existingClients | Where-Object { $_ -like "*$clientName*" }
    }
    
    if ($clientExists) {
        Write-Host "Android OAuth client '$clientName' already exists." -ForegroundColor Green
        # Note: gcloud doesn't support updating Android clients with SHA-1, so we provide guidance
        Write-Host "Please verify the client includes SHA-1 fingerprint: $fingerprint" -ForegroundColor Yellow
        Write-Host "Update at: https://console.cloud.google.com/apis/credentials?project=$ProjectId" -ForegroundColor Yellow
    } else {
        # Create new Android OAuth client
        Write-Host "Creating new Android OAuth client..."
        $createResult = & gcloud alpha oauth2 clients create android `
            --project $ProjectId `
            --display-name $clientName `
            --package-name $packageName `
            --sha1-fingerprint $fingerprint 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Android OAuth client created successfully!" -ForegroundColor Green
            Write-Host "Client includes package: $packageName" -ForegroundColor Green
            Write-Host "Client includes SHA-1: $fingerprint" -ForegroundColor Green
        } else {
            Write-Host "Failed to create OAuth client automatically. Error: $createResult" -ForegroundColor Yellow
            Write-Host "Manual setup required:" -ForegroundColor Yellow
            Write-Host "1. Go to: https://console.cloud.google.com/apis/credentials?project=$ProjectId" -ForegroundColor Yellow
            Write-Host "2. Create OAuth 2.0 Client ID" -ForegroundColor Yellow
            Write-Host "   - Application type: Android" -ForegroundColor Yellow
            Write-Host "   - Package name: $packageName" -ForegroundColor Yellow
            Write-Host "   - SHA-1 fingerprint: $fingerprint" -ForegroundColor Yellow
        }
    }
    
    Write-Host "OAuth setup complete! No google-services.json needed - your Flutter plugin handles authentication!" -ForegroundColor Green
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
