# GitHub Secrets Setup for CI/CD Pipeline

This document explains the required GitHub secrets for the xomify-ios CI/CD pipeline.

## Required Secrets

### Spotify API Credentials
- **SPOTIFY_CLIENT_ID**: Your Spotify API Client ID
  - Obtain from: https://developer.spotify.com/dashboard
  - Used in: PR checks and TestFlight deployment
  
- **SPOTIFY_REDIRECT_URI**: Your Spotify API Redirect URI
  - Format: `spotifyxomify://callback` or your configured URI
  - Used in: PR checks and TestFlight deployment

### Apple Developer Credentials
- **APPLE_ID**: Apple ID email used for App Store Connect
  - Format: `your-email@example.com`
  - Used in: TestFlight deployment
  
- **APPLE_APP_PASSWORD**: App-specific password for Apple ID
  - Generate from: https://appleid.apple.com/account/manage (Security > App-specific passwords)
  - Note: Regular Apple ID password won't work with altool
  - Used in: TestFlight deployment

- **APPLE_TEAM_ID**: Apple Developer Team ID
  - Format: Usually 10 character alphanumeric
  - Obtain from: https://developer.apple.com/account/#/membership
  - Used in: TestFlight deployment

- **APPLE_CODE_SIGN_IDENTITY**: Code signing certificate identity
  - Format: Certificate name as shown in Xcode
  - Example: `Apple Distribution: Company Name (XXXXXXXXXX)`
  - Used in: TestFlight deployment

- **APPLE_CERTIFICATE_P12**: Code signing certificate in P12 format (base64 encoded)
  - How to create:
    1. In Xcode: Preferences > Accounts > View Details
    2. Click "Download All" for certificates
    3. Export the distribution certificate as `.p12` file
    4. Base64 encode: `base64 -i certificate.p12 | pbcopy`
  - Used in: TestFlight deployment

- **APPLE_CERTIFICATE_PASSWORD**: Password for the P12 certificate
  - Set when exporting the certificate from Keychain
  - Used in: TestFlight deployment

- **APPLE_PROVISIONING_PROFILE_BASE64**: Provisioning profile (base64 encoded)
  - How to create:
    1. Go to: https://developer.apple.com/account/resources/profiles
    2. Create/download provisioning profile for the app
    3. Base64 encode: `base64 -i profile.mobileprovision | pbcopy`
  - Used in: TestFlight deployment

- **APPLE_PROVISIONING_PROFILE_UUID**: Provisioning profile UUID
  - Extract from provisioning profile:
    ```bash
    cat profile.mobileprovision | grep -ao '<string>[A-F0-9-]*</string>' | grep -i uuid | head -1
    ```
  - Or view in Xcode under: Signing & Capabilities > Provisioning Profile
  - Used in: TestFlight deployment

### Optional Secrets

- **CODECOV_TOKEN**: Codecov token for code coverage reports
  - Obtain from: https://codecov.io
  - Used in: PR checks (coverage upload)

- **SLACK_WEBHOOK_URL**: Slack incoming webhook for build notifications
  - Create from: https://api.slack.com/apps > Your App > Incoming Webhooks
  - Used in: TestFlight deployment notifications

## Setup Steps

1. Go to: https://github.com/Xomware/xomify-ios/settings/secrets/actions

2. Click "New repository secret" for each secret above

3. Enter the secret name exactly as specified (case-sensitive)

4. Paste the secret value

5. Click "Add secret"

## Testing Secrets

To verify secrets are properly configured without exposing them:

```bash
# This will show which secrets are available (not their values)
gh secret list --repo Xomware/xomify-ios
```

## Rotating Secrets

### Apple Developer Credentials
1. Generate new certificate in Apple Developer account
2. Export as P12 and base64 encode
3. Update `APPLE_CERTIFICATE_P12` and `APPLE_CERTIFICATE_PASSWORD`
4. Revoke old certificate in Apple Developer account

### Spotify Credentials
1. Regenerate in Spotify Developer Dashboard
2. Update `SPOTIFY_CLIENT_ID` and `SPOTIFY_REDIRECT_URI`

### App-Specific Password
1. Generate new password from https://appleid.apple.com/account/manage
2. Update `APPLE_APP_PASSWORD`
3. Revoke old password

## Workflow-Specific Usage

### pr-checks.yml
Required:
- SPOTIFY_CLIENT_ID
- SPOTIFY_REDIRECT_URI
- CODECOV_TOKEN (optional)

### testflight-deploy.yml
Required:
- SPOTIFY_CLIENT_ID
- SPOTIFY_REDIRECT_URI
- APPLE_ID
- APPLE_APP_PASSWORD
- APPLE_TEAM_ID
- APPLE_CODE_SIGN_IDENTITY
- APPLE_CERTIFICATE_P12
- APPLE_CERTIFICATE_PASSWORD
- APPLE_PROVISIONING_PROFILE_BASE64
- APPLE_PROVISIONING_PROFILE_UUID
- SLACK_WEBHOOK_URL (optional)

### dependabot.yml
No secrets required (automatic GitHub token used)

## Troubleshooting

### Build Fails with "Secrets not available"
- Ensure secret names match exactly (case-sensitive)
- Check repository settings > Secrets

### TestFlight Upload Fails
- Verify APPLE_APP_PASSWORD is a Xcode app-specific password, not regular Apple ID password
- Check that APPLE_TEAM_ID matches your account
- Ensure certificate and provisioning profile are not expired

### Code Signing Fails
- Verify APPLE_CERTIFICATE_P12 is valid and not expired
- Check APPLE_PROVISIONING_PROFILE_UUID matches the profile
- Ensure code signing identity exists in certificate

## Support

For issues with Apple Developer credentials, visit:
- https://developer.apple.com/help/account/

For Spotify API issues, visit:
- https://developer.spotify.com/documentation/web-api/
