param(
    [string]$ProjectId,
    [string]$SecretName = "photowordfind-debug-keystore"
)

# Firebase app id used for automatic SHA-1 registration
$FirebaseAppId = '1:1082599556322:android:66fb03c1d8192758440abb'

# Install gcloud using winget if necessary
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "winget not found. Install winget first." -ForegroundColor Red
        exit 1
    }
    Write-Host "Installing Google Cloud SDK via winget..."
    winget install -e --id Google.CloudSDK
}

# Sign in to Google Cloud
Write-Host "Authenticating with Google Cloud..."
gcloud auth login
if ($ProjectId) {
    gcloud config set project $ProjectId
}

# Fetch debug keystore
$keystorePath = Join-Path $PSScriptRoot "..\android\app\debug.keystore"
if (-not (Test-Path $keystorePath)) {
    Write-Host "Downloading debug keystore from Secret Manager..."
    gcloud secrets versions access latest --secret=$SecretName | Out-File -Encoding byte $keystorePath
}

# Calculate SHA-1 fingerprint and add to Firebase if app id provided
$keytool = (Get-Command keytool).Source
$fingerprint = & $keytool -list -v -keystore $keystorePath -alias androiddebugkey -storepass android -keypass android |
    Select-String 'SHA1:' | ForEach-Object { $_.ToString().Replace('SHA1:', '').Trim() }

Write-Host "Checking Firebase app for existing fingerprint..."
$existing = gcloud firebase apps android sha list $FirebaseAppId --format="value(shaHash)" 2>$null
if ($existing -contains $fingerprint) {
    Write-Host "Fingerprint already registered." -ForegroundColor Green
} else {
    Write-Host "Registering SHA-1 fingerprint with Firebase..." -ForegroundColor Green
    gcloud firebase apps android sha create $FirebaseAppId $fingerprint
}

# Mark bootstrap complete
$flagPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.bootstrap_complete'
Set-Content -Path $flagPath -Value 'ok'
