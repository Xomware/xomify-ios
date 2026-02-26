# xomify-ios CI/CD Pipeline Documentation

## Overview

This document describes the automated CI/CD pipeline for xomify-ios, including GitHub Actions workflows for continuous integration, testing, and deployment to TestFlight.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Events                           │
└──────────┬──────────────────────────────┬──────────────────┘
           │                              │
    ┌──────▼─────────┐           ┌───────▼──────────┐
    │  Pull Requests │           │ Push to main/    │
    │  (PR Checks)   │           │ master (Deploy)  │
    └──────┬─────────┘           └───────┬──────────┘
           │                             │
      ┌────▼──────────────────────┐     │
      │  PR Checks Workflow       │     │
      │  ├─ Lint (SwiftLint)      │     │
      │  ├─ Build                 │     │
      │  ├─ Unit Tests            │     │
      │  └─ Code Coverage         │     │
      └─────────────────────────  │     │
                                  │     │
                           ┌──────▼─────────┐
                           │ TestFlight     │
                           │ Deployment     │
                           │ ├─ Archive     │
                           │ ├─ Export IPA  │
                           │ └─ Upload      │
                           └────────────────┘
```

## Workflows

### 1. PR Checks Workflow (pr-checks.yml)

**Trigger:** Pull requests to main/master/develop, pushes to develop

**Jobs:**
- **Lint**: Runs SwiftLint for code quality analysis
- **Build**: Builds the app for iOS Simulator
- **Test**: Runs unit tests with code coverage

**Artifacts:**
- lint-results.json: SwiftLint output
- test-results: Test results bundle
- ios-archive: Built archive

**Duration:** ~15-20 minutes

### 2. TestFlight Deployment Workflow (testflight-deploy.yml)

**Trigger:** Push to main/master branch OR manual workflow_dispatch

**Jobs:**
- Import code signing certificates
- Download provisioning profiles
- Build iOS archive for release
- Export IPA file
- Upload to TestFlight via App Store Connect
- Notify Slack

**Artifacts:**
- release-notes: Build metadata and release notes

**Duration:** ~20-30 minutes

**Requirements:**
- All PR checks must pass
- Commit must be on main/master
- Apple Developer credentials configured

### 3. Dependabot Workflow (dependabot.yml)

**Trigger:** Automatic, runs on schedule

**Configuration:**
- Swift Package Manager updates: Weekly (Monday 3 AM UTC)
- GitHub Actions updates: Weekly (Monday 3 AM UTC)
- Automatically creates PRs for updates
- Security alerts always enabled

**Features:**
- Automatic PR creation for dependency updates
- Code review assignment
- Issue labeling
- Commit message formatting

## CI/CD Status

### Environment Variables

**GitHub Actions automatically provides:**
- `GITHUB_SHA`: Commit SHA
- `GITHUB_REF`: Branch reference
- `GITHUB_RUN_NUMBER`: Build number
- `GITHUB_WORKFLOW`: Workflow name

### Build Output

All workflows produce detailed build logs available in:
- GitHub Actions tab of the repository
- Artifact downloads (test results, builds, etc.)
- Slack notifications (TestFlight deployments)

## Local Development

### Running Tests Locally

```bash
# Run all tests
xcodebuild test \
  -project Xomify-iOS.xcodeproj \
  -scheme Xomify-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test class
xcodebuild test \
  -project Xomify-iOS.xcodeproj \
  -scheme Xomify-iOS \
  -only-testing:Xomify-iOSTests/WorkflowTests
```

### Running SwiftLint Locally

```bash
# Install if needed
brew install swiftlint

# Run lint
swiftlint lint Xomify-iOS/ --reporter github-actions-logging
```

### Building Archive

```bash
xcodebuild archive \
  -project Xomify-iOS.xcodeproj \
  -scheme Xomify-iOS \
  -destination generic/platform=iOS \
  -archivePath "Xomify-iOS.xcarchive" \
  -configuration Release
```

## Secrets Configuration

See [GITHUB_SECRETS_SETUP.md](GITHUB_SECRETS_SETUP.md) for complete setup instructions.

**Required Secrets:**
1. Spotify API Credentials
   - SPOTIFY_CLIENT_ID
   - SPOTIFY_REDIRECT_URI

2. Apple Developer Credentials
   - APPLE_ID
   - APPLE_APP_PASSWORD
   - APPLE_TEAM_ID
   - APPLE_CODE_SIGN_IDENTITY
   - APPLE_CERTIFICATE_P12
   - APPLE_CERTIFICATE_PASSWORD
   - APPLE_PROVISIONING_PROFILE_BASE64
   - APPLE_PROVISIONING_PROFILE_UUID

3. Optional
   - CODECOV_TOKEN (code coverage)
   - SLACK_WEBHOOK_URL (notifications)

## Build Requirements

**Xcode:**
- Xcode 16.1 or later
- Swift 5.9+
- iOS Deployment Target: 13.0+

**Dependencies:**
- SwiftLint (for lint checks)
- Xcpretty (for formatted output)
- Cocoapods or SPM (for dependencies)

## Troubleshooting

### PR Checks Failing

1. **SwiftLint errors**: Fix style issues in Xcode
   ```bash
   swiftlint autocorrect Xomify-iOS/
   ```

2. **Build failures**: Check Xcode build output
   - Verify deployment target matches minimum supported iOS version
   - Check for missing dependencies

3. **Test failures**: Run locally to reproduce
   ```bash
   xcodebuild test -project Xomify-iOS.xcodeproj -scheme Xomify-iOS
   ```

### TestFlight Deployment Failing

1. **Certificate issues**: Re-export certificate and update APPLE_CERTIFICATE_P12
2. **Provisioning profile**: Verify not expired in Apple Developer account
3. **App version**: Check Info.plist for version conflicts
4. **Apple ID**: Ensure app-specific password is used, not regular password

## Best Practices

1. **PR Reviews**: Ensure PR checks pass before requesting review
2. **Commit Messages**: Use conventional commits for clarity
3. **Testing**: Write tests for new features before PR
4. **Secrets**: Never commit secrets to repository
5. **Dependencies**: Update dependencies regularly via Dependabot

## Future Enhancements

- [ ] UI/snapshot testing
- [ ] Performance profiling
- [ ] Security scanning (OWASP)
- [ ] Automated beta tester notifications
- [ ] Integration testing on real devices
- [ ] App Store deployment automation
- [ ] Custom metrics and analytics

## Support

For issues with:
- **GitHub Actions**: Check workflow logs in Actions tab
- **Apple Developer**: Visit https://developer.apple.com/help/
- **Spotify API**: Visit https://developer.spotify.com/documentation/
- **Build Issues**: Check GITHUB_SECRETS_SETUP.md

## Related Files

- `.github/workflows/pr-checks.yml` - PR validation workflow
- `.github/workflows/testflight-deploy.yml` - TestFlight deployment
- `.github/dependabot.yml` - Dependency updates
- `GITHUB_SECRETS_SETUP.md` - Secrets configuration guide
- `Xomify-iOS/Tests/WorkflowTests.swift` - Workflow tests
