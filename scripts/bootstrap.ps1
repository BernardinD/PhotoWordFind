param(
    [string]$SecretName = "photowordfind-debug-keystore"
)

# Firebase project used for authentication and secrets
$ProjectId = 'pwfapp-f314d'

# Firebase app id used for automatic SHA-1 registration
$FirebaseAppId = '1:1082599556322:android:66fb03c1d8192758440abb'

# Ensure JDK 17 is installed and available
$jdkPackage = 'EclipseAdoptium.Temurin.17.JDK'
$needJdk = $true
if (Get-Command java -ErrorAction SilentlyContinue) {
    $verLine = (& java -version 2>&1)[0]
    if ($verLine -match '"(\d+)') {
        if ([int]$Matches[1] -eq 17) { $needJdk = $false }
    }
}
if ($needJdk) {
    Write-Host "Installing JDK 17 via winget..."
    winget install -e --id $jdkPackage
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
}

# Install Firebase CLI if missing
if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Firebase CLI via winget..."
    winget install -e --id Google.FirebaseCLI
}

# Sign in to Firebase
Write-Host "Authenticating with Firebase..."
firebase login
firebase use $ProjectId

# Fetch debug keystore
$keystorePath = Join-Path $PSScriptRoot "..\android\app\debug.keystore"
if (-not (Test-Path $keystorePath)) {
    Write-Host "Downloading debug keystore from Secret Manager..."
    firebase functions:secrets:versions:access $SecretName --project $ProjectId |
        Out-File -Encoding byte $keystorePath
}

# Calculate SHA-1 fingerprint and add to Firebase if app id provided
$keytool = (Get-Command keytool).Source
$fingerprint = & $keytool -list -v -keystore $keystorePath -alias androiddebugkey -storepass android -keypass android |
    Select-String 'SHA1:' | ForEach-Object { $_.ToString().Replace('SHA1:', '').Trim() }

Write-Host "Checking Firebase app for existing fingerprint..."
$existingJson = firebase apps:android:sha:list $FirebaseAppId --json 2>$null
$existing = @()
if ($LASTEXITCODE -eq 0 -and $existingJson) {
    $existing = ($existingJson | ConvertFrom-Json).result | ForEach-Object { $_.shaHash }
}

if ($existing -contains $fingerprint) {
    Write-Host "Fingerprint already registered." -ForegroundColor Green
} else {
    Write-Host "Registering SHA-1 fingerprint with Firebase..." -ForegroundColor Green
    firebase apps:android:sha:create $FirebaseAppId $fingerprint
}

# Mark bootstrap complete
$flagPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.bootstrap_complete'
Set-Content -Path $flagPath -Value 'ok'
