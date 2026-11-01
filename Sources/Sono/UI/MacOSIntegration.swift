import SwiftUI
import AVFoundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// Native macOS integration for Sono.
/// Handles media keys, system notifications, menu bar integration, and application lifecycle.
@MainActor
final class MacOSIntegration: ObservableObject {
    static let shared = MacOSIntegration()
    
    @Published var isNowPlayingInfoEnabled = true
    @Published var isMediaKeysEnabled = true
    @Published var isMenuBarPlayerEnabled = false
    
    private var nowPlayingInfo: [String: Any] = [:]
    private var mediaKeysSetup = false
    
    private init() {
        setupMediaKeys()
        updateNowPlayingInfo()
    }
    
    // MARK: - Now Playing Info
    
    /// Updates the Now Playing info center with current track information.
    func updateNowPlayingInfo(song: Song? = nil, player: Player? = nil) {
        #if canImport(MediaPlayer)
        var info: [String: Any] = [:]
        
        if let song = song {
            info[MPMediaItemPropertyTitle] = song.title
            info[MPMediaItemPropertyArtist] = song.artist ?? ""
            info[MPMediaItemPropertyAlbumTitle] = song.album ?? ""
            
            if let duration = song.duration, duration > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = Double(duration)
            }
            
            // Set artwork if available
            if let coverArt = song.coverArt, let client = player?.client {
                Task {
                    if let url = client.cover(coverArt, size: 400) {
                        if let data = try? Data(contentsOf: url), 
                           let image = NSImage(data: data) {
                            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                            info[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                        }
                    }
                }
            }
        }
        
        // Update play/pause state
        if let player = player {
            info[MPNowPlayingInfoPropertyPlaybackRate] = player.isPlaying ? 1.0 : 0.0
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.time
        }
        
        nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info.isEmpty ? nil : info
        #endif
    }
    
    /// Clears the Now Playing info center.
    func clearNowPlayingInfo() {
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
        nowPlayingInfo = [:]
    }
    
    // MARK: - Media Keys
    
    private func setupMediaKeys() {
        guard !mediaKeysSetup else { return }
        mediaKeysSetup = true
        
        #if canImport(MediaPlayer)
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play/Pause
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleMediaKey(.togglePlayPause)
            return .success
        }
        
        // Play
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handleMediaKey(.play)
            return .success
        }
        
        // Pause
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handleMediaKey(.pause)
            return .success
        }
        
        // Next
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.handleMediaKey(.next)
            return .success
        }
        
        // Previous
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.handleMediaKey(.previous)
            return .success
        }
        
        // Stop
        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.handleMediaKey(.stop)
            return .success
        }
        
        // Enable remote control events
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.stopCommand.isEnabled = true
        
        // Set up playback state
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }
    
    private func handleMediaKey(_ key: MediaKey) {
        guard isMediaKeysEnabled else { return }
        
        // Notify the player to handle the media key
        NotificationCenter.default.post(
            name: .sono_mediaKeyPressed,
            object: nil,
            userInfo: ["key": key.rawValue]
        )
    }
    
    enum MediaKey: String {
        case togglePlayPause
        case play
        case pause
        case next
        case previous
        case stop
    }
    
    // MARK: - Notifications
    
    /// Shows a system notification.
    func showNotification(title: String, subtitle: String, body: String, identifier: String = UUID().uuidString) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        
        center.add(request)
        #endif
    }
    
    /// Requests notification permissions.
    func requestNotificationPermission() async -> Bool {
        #if canImport(UserNotifications)
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
    
    // MARK: - Menu Bar Player
    
    /// Shows a mini player in a popover.
    func showMenuBarPlayer() {
        guard isMenuBarPlayerEnabled else { return }
        
        let popover = NSPopover()
        popover.behavior = .transient
        
        if #available(macOS 14.0, *) {
            let hostingView = NSHostingView(rootView: NowPlayingMiniView())
            popover.contentView = hostingView
        } else {
            // Fallback for older macOS
            let hostingView = NSHostingView(rootView: NowPlayingMiniView())
            popover.contentSize = NSSize(width: 280, height: 120)
            // For older macOS, we need to use contentViewController
            let viewController = NSViewController()
            viewController.view = hostingView
            popover.contentViewController = viewController
        }
        
        // Show the popover
        if let button = NSApplication.shared.windows.first?.contentView {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    /// Toggles the menu bar player visibility.
    func toggleMenuBarPlayer() {
        isMenuBarPlayerEnabled.toggle()
    }
    
    // MARK: - Application Lifecycle
    
    /// Handles application will terminate.
    func applicationWillTerminate() {
        // Save playback state
        NotificationCenter.default.post(
            name: .sono_savePlaybackState,
            object: nil
        )
    }
    
    /// Handles application will resign active.
    func applicationWillResignActive() {
        // Pause playback if needed
        NotificationCenter.default.post(
            name: .sono_applicationWillResignActive,
            object: nil
        )
    }
    
    /// Handles application did become active.
    func applicationDidBecomeActive() {
        // Restore playback state if needed
        NotificationCenter.default.post(
            name: .sono_applicationDidBecomeActive,
            object: nil
        )
    }
}

// MARK: - Now Playing Mini View

struct NowPlayingMiniView: View {
    @Environment(AppState.self) var s
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Artwork
            if let current = s.player.current {
                Art(id: current.coverArt, size: 48, cornerRadius: 6)
            } else {
                SonoLogo(size: 48)
            }
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                if let current = s.player.current {
                    Text(current.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if let artist = current.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("No track playing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Controls
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Button {
                        s.player.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        s.player.toggle()
                    } label: {
                        Image(systemName: s.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        s.player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                
                // Progress
                if let current = s.player.current, let duration = current.duration, duration > 0 {
                    let progress = s.player.time / Double(duration)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .frame(width: 180)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let sono_mediaKeyPressed = Notification.Name("sono_mediaKeyPressed")
    static let sono_savePlaybackState = Notification.Name("sono_savePlaybackState")
    static let sono_applicationWillResignActive = Notification.Name("sono_applicationWillResignActive")
    static let sono_applicationDidBecomeActive = Notification.Name("sono_applicationDidBecomeActive")
}
