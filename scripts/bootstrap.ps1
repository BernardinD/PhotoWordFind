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

# Ensure JDK 17 is installed and available
$jdkPackage = 'EclipseAdoptium.Temurin.17.JDK'
$needJdk = $true
$verCheck = Get-Command java -ErrorAction SilentlyContinue
if ($verCheck) {
    Write-Host "Existing Java detected: $($verCheck.Source)"
} else {
    Write-Host "No Java installation detected in PATH."
}
if ($verCheck) {
    $verLine = (& java -version 2>&1)[0]
    if ($verLine -match '"(\d+)"') {
        if ([int]$Matches[1] -eq 17) { $needJdk = $false }
    }
}
if ($needJdk) {
    Write-Host "Installing JDK 17 via winget..."
    winget install -e --id $jdkPackage
    Refresh-SessionPath
} else {
    Write-Host "Compatible JDK already present." -ForegroundColor Green
}

# Ensure Android Studio and command line tools are installed
if (-not (Get-Command studio64.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Android Studio via winget..."
    winget install -e --id Google.AndroidStudio
    Refresh-SessionPath
} else {
    Write-Host "Android Studio already installed." -ForegroundColor Green
}

$sdkManager = "$Env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkManager)) {
    $sdkManager = "$Env:LOCALAPPDATA\Android\Sdk\tools\bin\sdkmanager.bat"
}
if (Test-Path $sdkManager) {
    Write-Host "Ensuring Android cmdline tools installed..."
    & $sdkManager --install "cmdline-tools;latest" "platform-tools" | Out-Null
}

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

    $gradleProps = Join-Path $PSScriptRoot "..\android\gradle.properties"
    if (Test-Path $gradleProps) {
        $props = Get-Content $gradleProps
        $newLine = "org.gradle.java.home=$env:PWF_JAVA_HOME"
        $updated = $false
        $props = $props | ForEach-Object {
            if ($_ -match '^\s*#?\s*org\.gradle\.java\.home=') {
                $updated = $true
                $newLine
            } else {
                $_
            }
        }
        if (-not $updated) { $props += $newLine }
        Set-Content $gradleProps $props
        Write-Host "Set org.gradle.java.home in gradle.properties" -ForegroundColor Green
    }
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

# Install Firebase CLI if missing
if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Firebase CLI via winget..."
    winget install -e --id Google.FirebaseCLI
    Refresh-SessionPath
}

# Sign in to Firebase
Write-Host "Authenticating with Firebase..."
firebase login

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
$existingJson = firebase apps:android:sha:list $FirebaseAppId --project $ProjectId --json 2>$null
$existing = @()
if ($LASTEXITCODE -eq 0 -and $existingJson) {
    $existing = ($existingJson | ConvertFrom-Json).result | ForEach-Object { $_.shaHash }
}

if ($existing -contains $fingerprint) {
    Write-Host "Fingerprint already registered." -ForegroundColor Green
} else {
    Write-Host "Registering SHA-1 fingerprint with Firebase..." -ForegroundColor Green
    firebase apps:android:sha:create $FirebaseAppId $fingerprint --project $ProjectId
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SHA-1 fingerprint registered successfully." -ForegroundColor Green
    } else {
        Write-Host "Failed to register fingerprint." -ForegroundColor Yellow
    }
}

# Mark bootstrap complete
$flagPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.bootstrap_complete'
Write-Host "Marking bootstrap complete at $flagPath" -ForegroundColor Green
Set-Content -Path $flagPath -Value 'ok'
