# Xomify iOS

A native iOS app for enhanced Spotify features including Release Radar tracking, Monthly Wrapped stats, and playlist building.

![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![iOS](https://img.shields.io/badge/iOS-17.0+-blue)
![Spotify](https://img.shields.io/badge/Spotify-API-green)

## Features

### 🎵 Release Radar
Track new music releases from artists you follow on Spotify.
- **Weekly updates** - New releases tracked every Saturday
- **Browse history** - View past weeks of releases
- **Stats dashboard** - See release counts, artists, tracks, albums, and singles
- **Quick actions** - Add releases to playlist builder or play in Spotify

### 📊 Monthly Wrapped
Your personalized monthly listening stats.
- **Top Songs** - Your most played tracks with 4-week, 6-month, and all-time views
- **Top Artists** - Artists you've listened to most
- **Top Genres** - Genre breakdown with visual bars
- **Save playlists** - Create Spotify playlists from your top songs

### 🎧 Playlist Builder
Build custom playlists from anywhere in the app.
- **Search songs** - Find and add any track on Spotify
- **Add from anywhere** - Add tracks from Top Items, Release Radar, Wrapped, Albums, Artists
- **Drag to reorder** - Arrange your playlist
- **Create on Spotify** - Save directly to your Spotify account with custom cover art

### 👤 Profile
- View your Spotify profile and stats
- Manage Release Radar and Wrapped enrollment
- See followed artists count and top genres

### 📈 Top Items
- View your top tracks and artists
- Filter by time range (4 weeks, 6 months, all time)
- Navigate to album and artist details
- Add tracks to playlist builder

## Architecture

```
Xomify-iOS/
├── App/
│   └── Xomify_iOSApp.swift
├── Config/
│   ├── Config.swift
│   └── XomifyConstants.swift
├── Models/
│   ├── SpotifyModels.swift
│   └── XomifyModels.swift
├── Services/
│   ├── AuthService.swift
│   ├── NetworkService.swift
│   ├── SpotifyService.swift
│   ├── XomifyService.swift
│   └── PlaylistBuilderManager.swift
├── ViewModels/
│   ├── ProfileViewModel.swift
│   ├── TopItemsViewModel.swift
│   ├── ReleaseRadarViewModel.swift
│   └── PlaylistBuilderViewModel.swift
├── Views/
│   ├── MainTabView.swift
│   ├── ProfileView.swift
│   ├── TopItemsView.swift
│   ├── ReleaseRadarView.swift
│   ├── WrappedView.swift
│   ├── AlbumView.swift
│   ├── ArtistView.swift
│   ├── FollowingView.swift
│   ├── PlaylistBuilderView.swift
│   ├── LoginView.swift
│   └── ContentView.swift
├── Utilities/
│   └── ColorExtensions.swift
└── Assets.xcassets/
```

## Setup

### Prerequisites
- Xcode 15+
- iOS 17.0+
- Spotify Developer Account
- Xomify Backend API (AWS Lambda + API Gateway + DynamoDB)

### Configuration

1. **Create `Secrets.xcconfig`** in the project root (gitignored):

```xcconfig
// Spotify API Credentials
SPOTIFY_CLIENT_ID = your_spotify_client_id

// Xomify Backend API
XOMIFY_API_ID = your_api_gateway_id
XOMIFY_API_TOKEN = your_api_key
```

2. **Update Info.plist** with these keys:

```xml
<key>SPOTIFY_CLIENT_ID</key>
<string>$(SPOTIFY_CLIENT_ID)</string>
<key>XOMIFY_API_ID</key>
<string>$(XOMIFY_API_ID)</string>
<key>XOMIFY_API_TOKEN</key>
<string>$(XOMIFY_API_TOKEN)</string>
```

3. **Configure URL Scheme** for OAuth callback:
   - URL Schemes: `xomify`
   - Callback URL: `xomify://callback`

4. **Add to Spotify Dashboard**:
   - Redirect URI: `xomify://callback`
   - Required Scopes:
     - `user-read-email`
     - `user-read-private`
     - `user-top-read`
     - `user-follow-read`
     - `user-library-read`
     - `playlist-modify-public`
     - `playlist-modify-private`
     - `ugc-image-upload`
     - `user-modify-playback-state`
     - `user-read-playback-state`
     - `streaming`

### Assets

Add these images to `Assets.xcassets`:
- **AppIcon** - 1024x1024 app icon
- **logo** - Square logo for navigation bars
- **banner** - Wide banner image for headers (optional)

## Tech Stack

- **SwiftUI** - Modern declarative UI
- **Swift 6** - Latest Swift with strict concurrency
- **Observation** - `@Observable` macro for state management
- **async/await** - Modern concurrency
- **Spotify Web API** - Music data and playback
- **Xomify Backend** - AWS Lambda + API Gateway + DynamoDB

## API Endpoints

### Spotify API
- `GET /me` - Current user profile
- `GET /me/top/tracks` - Top tracks
- `GET /me/top/artists` - Top artists
- `GET /me/following` - Followed artists
- `GET /albums/{id}` - Album details
- `GET /artists/{id}` - Artist details
- `POST /users/{id}/playlists` - Create playlist
- `POST /playlists/{id}/tracks` - Add tracks to playlist
- `PUT /playlists/{id}/images` - Upload playlist cover

### Xomify API
- `GET /release-radar/history` - Past release radar weeks
- `GET /release-radar/live` - Current week releases
- `GET /wrapped/data` - Monthly wrapped data
- `POST /user/user-table` - Save/update user enrollment

## Color Palette

| Color | Hex | Usage |
|-------|-----|-------|
| Xomify Purple | `#9C0ABF` | Primary accent, artists |
| Xomify Green | `#1BDC6F` | Success, songs, CTA buttons |
| Xomify Dark | `#0A0A14` | Background |
| Xomify Card | `#1A1A2E` | Card backgrounds |
| Spotify Green | `#1DB954` | Spotify-related actions |

## Building

1. Clone the repository
2. Create `Secrets.xcconfig` with your credentials
3. Open `Xomify-iOS.xcodeproj` in Xcode
4. Select your target device/simulator
5. Build and run (⌘R)

## License

Private project - All rights reserved.

## Author

Dominick Giordano
