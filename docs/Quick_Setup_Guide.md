# Quick Setup Guide for Google Sign-In

## Automated Setup (Most Steps)

1. Run the enhanced bootstrap script:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
powershell -ExecutionPolicy Bypass -File ./scripts/bootstrap.ps1
```

The script will automatically:
- ✅ Install Google Cloud CLI
- ✅ Authenticate with GCP
- ✅ Enable required APIs
- ✅ Download google-services.json
- ✅ Configure Android build files

## Manual Steps Required

### 1. OAuth Consent Screen (5 minutes)
🔗 [Google Cloud Console - OAuth Consent](https://console.cloud.google.com/apis/credentials/consent)

1. Select **"External"** user type
2. Fill in basic info:
   - **App name**: PhotoWordFind
   - **User support email**: [your email]
   - **Developer contact**: [your email]
3. Skip optional fields
4. Click **"Save and Continue"** through all steps

### 2. Android OAuth Client (3 minutes)
🔗 [Google Cloud Console - Credentials](https://console.cloud.google.com/apis/credentials)

1. Click **"Create Credentials"** → **"OAuth 2.0 Client IDs"**
2. Select **"Android"** application type
3. Enter details:
   - **Package name**: `com.example.PhotoWordFind`
   - **SHA-1 fingerprint**: [copied from script output]
4. Click **"Create"**

### 3. Web OAuth Client (Optional - for future web deployment)
1. Click **"Create Credentials"** → **"OAuth 2.0 Client IDs"**
2. Select **"Web application"**
3. Name: `PhotoWordFind-Web-Client`
4. Click **"Create"**

## Verification

After completing manual steps:
1. Run Flutter app: `flutter run`
2. Test Google Sign-In functionality
3. Check that cloud backup works

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Sign-in failed" | Complete OAuth consent screen setup |
| "Developer Error" | Create Android OAuth client with correct SHA-1 |
| "App not verified" | Add your email as test user in OAuth consent screen |
| "API not enabled" | Run `gcloud services enable oauth2.googleapis.com` |

## Quick Links

- 📋 [OAuth Consent Screen](https://console.cloud.google.com/apis/credentials/consent?project=pwfapp-f314d)
- 🔑 [OAuth Credentials](https://console.cloud.google.com/apis/credentials?project=pwfapp-f314d)
- 🔥 [Firebase Console](https://console.firebase.google.com/project/pwfapp-f314d)
- ☁️ [Google Cloud Console](https://console.cloud.google.com/home/dashboard?project=pwfapp-f314d)