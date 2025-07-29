# GCP OAuth Client Registration Enhancement

This document describes the enhancements made to the PhotoWordFind bootstrap script to support complete Google Sign-In functionality through Google Cloud Platform (GCP) OAuth client registration.

## Overview

The enhanced bootstrap script now handles both Firebase configuration and Google Cloud Platform OAuth client setup, providing a comprehensive solution for Google Sign-In functionality.

## New Features

### 1. Google Cloud CLI Installation
- Automatically installs Google Cloud CLI via winget
- Package: `Google.CloudSDK`
- Command: `gcloud`

### 2. GCP Authentication
- Authenticates with Google Cloud using the same account as Firebase
- Sets the correct GCP project (`pwfapp-f314d`)
- Verifies project access and permissions

### 3. Required API Enablement
The script automatically enables the following APIs:
- `iap.googleapis.com` - Identity-Aware Proxy API
- `oauth2.googleapis.com` - OAuth 2.0 API
- `cloudresourcemanager.googleapis.com` - Cloud Resource Manager API

### 4. OAuth Client Management
- **Android OAuth Client**: Creates configuration for Android app with debug keystore SHA-1
- **Web OAuth Client**: Sets up configuration for future web deployment
- Provides detailed setup instructions for manual completion via Google Cloud Console

### 5. OAuth Consent Screen Setup
- Guides through OAuth consent screen configuration
- Provides step-by-step instructions for manual setup
- Ensures compliance with Google's OAuth requirements

### 6. google-services.json Management
- Downloads google-services.json from Firebase
- Places file in correct location (`android/app/google-services.json`)
- Validates JSON structure and project ID

### 7. Configuration Validation
- Verifies google-services.json exists and is valid
- Checks project ID consistency
- Provides detailed feedback on setup status

## Enhanced Android Configuration

### Google Services Plugin
The script ensures proper Android build configuration:

**Root build.gradle** (`android/build.gradle`):
```gradle
dependencies {
    classpath 'com.google.gms:google-services:4.3.15'
}
```

**App build.gradle** (`android/app/build.gradle`):
```gradle
apply plugin: 'com.google.gms.google-services'
```

## Usage

Run the enhanced bootstrap script as before:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
powershell -ExecutionPolicy Bypass -File ./scripts/bootstrap.ps1
```

## Manual Steps Required

Due to Google's security requirements, some OAuth configuration steps must be completed manually:

### 1. OAuth Consent Screen
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to APIs & Services > OAuth consent screen
3. Choose 'External' user type
4. Fill in required fields:
   - App name: PhotoWordFind
   - User support email: your email
   - Developer contact information: your email
5. Add scopes: email, profile, openid
6. Add test users during development

### 2. Android OAuth Client
1. Go to [Google Cloud Console Credentials](https://console.cloud.google.com/apis/credentials)
2. Click 'Create Credentials' > 'OAuth 2.0 Client IDs'
3. Select 'Android' as application type
4. Set package name: `com.example.PhotoWordFind`
5. Add SHA-1 fingerprint (provided by script)

### 3. Web OAuth Client (Future)
1. In Google Cloud Console Credentials
2. Create 'Web application' OAuth client
3. Configure authorized origins and redirect URIs when hosting web app

## Validation

The script performs comprehensive validation:
- ✅ Google Cloud CLI installation
- ✅ GCP authentication and project configuration
- ✅ Required API enablement
- ✅ google-services.json download and validation
- ✅ Android build configuration
- ⚠️ OAuth client creation (manual step)
- ⚠️ OAuth consent screen setup (manual step)

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure you have appropriate permissions in the GCP project
2. **API Not Enabled**: The script attempts to enable required APIs automatically
3. **Authentication Failed**: Use the same Google account for both Firebase and GCP
4. **Missing google-services.json**: Verify Firebase app configuration and download manually if needed

### Recovery Steps

If the automated setup fails:
1. Check authentication: `gcloud auth list`
2. Verify project: `gcloud config get-value project`
3. Enable APIs manually: `gcloud services enable oauth2.googleapis.com`
4. Download google-services.json manually from Firebase Console

## Security Considerations

- google-services.json is properly ignored in git (`.gitignore`)
- OAuth clients are project-specific and secured
- Debug keystore is fetched securely from Firebase Functions config
- All sensitive configurations are excluded from version control

## Developer Experience

The enhanced script provides:
- Clear progress messages for each step
- Detailed error messages with recovery instructions
- Comprehensive validation of all configurations
- Direct links to Google Cloud Console for manual steps
- Single command setup for new developers

## Future Enhancements

Potential future improvements:
- Automated OAuth client creation via Google Cloud APIs
- Support for production keystore configuration
- Integration with CI/CD pipelines
- Multi-environment configuration support