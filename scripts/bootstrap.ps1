param(
    [string]$ProjectId,
    [string]$FirebaseAppId,
    [string]$SecretName = "photowordfind-debug-keystore"
)

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

if ($FirebaseAppId) {
    Write-Host "Registering SHA-1 fingerprint with Firebase..."
    gcloud firebase apps android sha create $FirebaseAppId $fingerprint
} else {
    Write-Host "SHA-1 fingerprint: $fingerprint"
    Write-Host "Add this fingerprint to your OAuth credentials or Firebase app if required."
}
