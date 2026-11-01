# Sono
Open-source, high-fidelity Navidrome & Subsonic client in Swift/SwiftUI for macOS and Windows.

Build: `Scripts/make_icns.sh && Scripts/build_app.sh`, then open `build/Sono.app` (or `swift build` on Windows/macOS).

## Features
- **Navidrome Controls & Admin Panel**:
  - **Media Library Rescanning**: Trigger Quick Scans (incremental) or Deep Full Scans directly from the app, with real-time scan progress polling and automatic library reload.
  - **Configured Media Directories**: Inspect server music folders and library metrics (tracks, albums, playlists, genres).
  - **User & Access Management**: Full admin account management (create users, update permissions/roles, reset passwords, delete users).
  - **Internet Radio**: Browse, manage, and stream live internet radio stations registered on your Navidrome server.
  - **System Telemetry & OpenSubsonic**: Inspect server version, OpenSubsonic extensions, round-trip latency, license info, and configure server-side transcoding bitrate limits.
- **Cross-Platform Compatibility**: Supports macOS and Windows with zero extra external library requirements and native fallbacks.
- **Welcome & Onboarding**: First-run welcome experience with guided server setup and Navidrome configuration guide.
- **Server Diagnostics & Error Screens**: Real-time connection testing, latency measurement, Subsonic error code decoding, and diagnostic troubleshooting suggestions.
- **Lossless & Original Streaming**: Uncompressed bit-perfect playback directly from your personal music library.
- **Live Synced Lyrics**: Frame-rate synchronized karaoke lyrics provided natively by Subsonic & Navidrome LRC streaming.
- **Modern Fluid Design**: Vibrant glassmorphic materials, custom queue management, album grid views, interactive toasts, and native menu bar controls.
- **Offline Downloads**: High-fidelity offline storage with zero DRM and playlist export (.m3u8, .csv, .json).
