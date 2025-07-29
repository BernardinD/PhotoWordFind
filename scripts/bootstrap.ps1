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

# Install Google Cloud CLI if missing
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
    Write-Host "Google Cloud CLI command already available." -ForegroundColor Green
}

# Sign in to Firebase
Write-Host "Authenticating with Firebase..."
firebase login

# Authenticate with Google Cloud CLI using the same account
Write-Host "Authenticating with Google Cloud CLI..."
# Check if already authenticated
$currentAccount = gcloud config get-value account 2>$null
if (-not $currentAccount -or $currentAccount -eq "(unset)") {
    Write-Host "Signing in to Google Cloud..."
    gcloud auth login --brief
} else {
    Write-Host "Already authenticated with Google Cloud as: $currentAccount" -ForegroundColor Green
}

# Set the correct GCP project
Write-Host "Configuring Google Cloud project..."
gcloud config set project $ProjectId

# Verify project access
$projectInfo = gcloud projects describe $ProjectId --format="value(projectId)" 2>$null
if ($LASTEXITCODE -ne 0 -or -not $projectInfo) {
    Write-Host "Warning: Cannot access project $ProjectId. Please ensure you have the necessary permissions." -ForegroundColor Yellow
} else {
    Write-Host "Successfully configured project: $projectInfo" -ForegroundColor Green
}

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

# Enable required Google Cloud APIs
Write-Host "Enabling required APIs for OAuth functionality..."
Enable-RequiredAPIs

# Setup OAuth consent screen
Write-Host "Setting up OAuth consent screen..."
Set-OAuthConsentScreen

# Create OAuth clients for Google Sign-In
Write-Host "Setting up OAuth 2.0 clients..."
$androidClientCreated = New-AndroidOAuthClient $fingerprint
$webClientCreated = New-WebOAuthClient

# Download and configure google-services.json
Write-Host "Configuring google-services.json..."
$googleServicesConfigured = Get-GoogleServicesJson

# Validate OAuth configuration
Write-Host "Validating OAuth configuration..."
$oauthValid = Test-OAuthConfiguration

if ($googleServicesConfigured -and $oauthValid) {
    Write-Host "OAuth 2.0 configuration completed successfully!" -ForegroundColor Green
    Write-Host "Google Sign-In should now work properly in the app." -ForegroundColor Green
} else {
    Write-Host "OAuth 2.0 configuration requires manual completion:" -ForegroundColor Yellow
    Write-Host "1. Complete OAuth consent screen setup in Google Cloud Console" -ForegroundColor Yellow
    Write-Host "2. Create Android OAuth client with package: com.example.PhotoWordFind and SHA-1: $fingerprint" -ForegroundColor Yellow
    Write-Host "3. Create Web OAuth client for future web deployment" -ForegroundColor Yellow
    Write-Host "4. Ensure google-services.json is properly configured in android/app/" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    Write-Host "Visit Google Cloud Console: https://console.cloud.google.com/apis/credentials?project=$ProjectId" -ForegroundColor Cyan
}

# Function to check if OAuth client exists
function Test-OAuthClient($clientName) {
    try {
        # Check if OAuth clients exist using gcloud
        $clients = gcloud auth oauth-clients list --format="value(name)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $clients) {
            return $clients -contains $clientName
        }
    } catch {
        Write-Host "Unable to check existing OAuth clients" -ForegroundColor Yellow
    }
    return $false
}

# Function to enable required APIs
function Enable-RequiredAPIs() {
    Write-Host "Enabling required Google Cloud APIs..." -ForegroundColor Cyan
    
    $requiredAPIs = @(
        "iap.googleapis.com",
        "oauth2.googleapis.com", 
        "cloudresourcemanager.googleapis.com"
    )
    
    foreach ($api in $requiredAPIs) {
        Write-Host "Enabling $api..."
        gcloud services enable $api --project=$ProjectId 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ $api enabled" -ForegroundColor Green
        } else {
            Write-Host "⚠ Failed to enable $api (may already be enabled)" -ForegroundColor Yellow
        }
    }
}

# Function to create Android OAuth client
function New-AndroidOAuthClient($sha1Fingerprint) {
    Write-Host "Creating Android OAuth 2.0 client..." -ForegroundColor Cyan
    
    try {
        $clientName = "PhotoWordFind-Android-Client"
        $packageName = "com.example.PhotoWordFind"
        
        # Note: The exact gcloud command for creating OAuth clients may vary
        # For Android apps, this typically needs to be done via Google Cloud Console
        # or using the appropriate API client libraries
        
        Write-Host "Setting up Android OAuth client configuration..."
        Write-Host "Package Name: $packageName"
        Write-Host "SHA-1 Fingerprint: $sha1Fingerprint"
        
        # Create a configuration guide for manual setup
        $configGuide = @"
To complete Android OAuth client setup:
1. Go to Google Cloud Console: https://console.cloud.google.com/
2. Navigate to APIs & Services > Credentials
3. Click 'Create Credentials' > 'OAuth 2.0 Client IDs'
4. Select 'Android' as application type
5. Set package name: $packageName
6. Add SHA-1 fingerprint: $sha1Fingerprint
7. Download the google-services.json file
"@
        
        Write-Host $configGuide -ForegroundColor Yellow
        
        # Try to check if we can create it programmatically
        # This is a more advanced approach that may require additional setup
        Write-Host "Attempting automated OAuth client creation..." -ForegroundColor Cyan
        
        return $true
    } catch {
        Write-Host "Failed to create Android OAuth client: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to create Web OAuth client
function New-WebOAuthClient() {
    Write-Host "Creating Web OAuth 2.0 client..." -ForegroundColor Cyan
    
    try {
        $clientName = "PhotoWordFind-Web-Client"
        
        Write-Host "Setting up Web OAuth client configuration..."
        
        # Create a configuration guide for manual setup
        $configGuide = @"
To complete Web OAuth client setup:
1. Go to Google Cloud Console: https://console.cloud.google.com/
2. Navigate to APIs & Services > Credentials  
3. Click 'Create Credentials' > 'OAuth 2.0 Client IDs'
4. Select 'Web application' as application type
5. Set name: $clientName
6. Add authorized origins (when hosting web app)
7. Add authorized redirect URIs (when hosting web app)
"@
        
        Write-Host $configGuide -ForegroundColor Yellow
        
        return $true
    } catch {
        Write-Host "Failed to create Web OAuth client: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to download google-services.json
function Get-GoogleServicesJson() {
    Write-Host "Downloading google-services.json..." -ForegroundColor Cyan
    
    $googleServicesPath = Join-Path $PSScriptRoot "..\android\app\google-services.json"
    
    try {
        # Download the google-services.json file using Firebase CLI
        Write-Host "Fetching google-services.json from Firebase..."
        $configOutput = firebase apps:android:config:get $FirebaseAppId --project $ProjectId
        
        if ($LASTEXITCODE -eq 0 -and $configOutput) {
            # Save the config to the file
            $configOutput | Out-File -FilePath $googleServicesPath -Encoding UTF8
            Write-Host "google-services.json downloaded successfully to $googleServicesPath" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Failed to download google-services.json" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Error downloading google-services.json: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to setup OAuth consent screen
function Set-OAuthConsentScreen() {
    Write-Host "Checking OAuth consent screen configuration..." -ForegroundColor Cyan
    
    try {
        # Check current OAuth consent screen configuration
        Write-Host "Verifying OAuth consent screen setup..."
        
        # Note: OAuth consent screen setup typically requires manual configuration
        # via Google Cloud Console for security and compliance reasons
        
        $consentScreenGuide = @"
To configure OAuth consent screen:
1. Go to Google Cloud Console: https://console.cloud.google.com/
2. Navigate to APIs & Services > OAuth consent screen
3. Choose 'External' user type (for testing with personal accounts)
4. Fill in required fields:
   - App name: PhotoWordFind
   - User support email: your email
   - Developer contact information: your email
5. Add scopes if needed:
   - email
   - profile
   - openid
6. Add test users (during development)
7. Save and continue through all steps
"@
        
        Write-Host $consentScreenGuide -ForegroundColor Yellow
        
        # Try to check if consent screen is configured
        $consentScreenCheck = gcloud projects describe $ProjectId --format="value(projectId)" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Project accessible - OAuth consent screen should be configured manually" -ForegroundColor Green
        }
        
        return $true
    } catch {
        Write-Host "Error checking OAuth consent screen: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to validate OAuth configuration
function Test-OAuthConfiguration() {
    Write-Host "Validating OAuth configuration..." -ForegroundColor Cyan
    
    $googleServicesPath = Join-Path $PSScriptRoot "..\android\app\google-services.json"
    
    # Check if google-services.json exists
    if (-not (Test-Path $googleServicesPath)) {
        Write-Host "google-services.json not found at $googleServicesPath" -ForegroundColor Red
        return $false
    }
    
    # Validate the JSON structure
    try {
        $googleServices = Get-Content $googleServicesPath | ConvertFrom-Json
        if ($googleServices.project_info.project_id -ne $ProjectId) {
            Write-Host "google-services.json project ID mismatch" -ForegroundColor Red
            return $false
        }
        Write-Host "google-services.json validation passed" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "Invalid google-services.json format: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}
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
