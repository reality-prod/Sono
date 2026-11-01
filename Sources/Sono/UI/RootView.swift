import SwiftUI

struct RootView: View {
    @Environment(AppState.self) var s
    
    var body: some View {
        ZStack {
            Ambient(intensity: 0.55)
            
            VStack(spacing: 0) {
                // Main split: Sidebar + Content (+ Queue)
                HStack(spacing: 0) {
                    Sidebar()
                    
                    VStack(spacing: 0) {
                        WindowHeader()
                        
                        Divider().overlay(Color.white.opacity(0.08))
                        
                        // Active page content
                        Group {
                            switch s.page {
                            case .listenNow:
                                ListenNowPage()
                            case .search:
                                SearchPage()
                            case .library:
                                SongList(title: "Your Library", subtitle: "\(s.library.count) tracks in collection", songs: s.library)
                            case .albums:
                                AlbumsPage()
                            case .playlists:
                                PlaylistsPage()
                            case .liked:
                                SongList(title: "Liked Songs", subtitle: "\(s.liked.count) favorite tracks", songs: s.liked)
                            case .downloads:
                                SongList(title: "Downloads", subtitle: "\(s.downloads.songs.count) tracks offline", songs: s.downloads.songs, showFolder: true)
                            case .history:
                                SongList(title: "Recently Played", subtitle: "Last \(s.player.history.count) played tracks", songs: s.player.history)
                            case .radio:
                                RadioPage()
                            case .serverControl:
                                ServerAdminPage()
                            case .servers:
                                ServersPage()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    if s.showQueue {
                        QueuePanel()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                
                // Bottom Playback Bar
                BottomBar()
                    .padding(.bottom, 8)
            }
            
            // Full-screen Synced Lyrics overlay
            if s.showLyrics {
                LyricsView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(2)
            }
            
            // Toast Notification Overlay
            if let toast = s.toast {
                VStack {
                    ToastBannerView(toast: toast)
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: s.showQueue)
        .animation(.easeInOut(duration: 0.3), value: s.showLyrics)
        .sheet(isPresented: Bindable(s).showWelcome) {
            WelcomeView()
        }
    }
}

// MARK: - Window Header

struct WindowHeader: View {
    @Environment(AppState.self) var s
    
    var body: some View {
        HStack(spacing: 14) {
            // Page title breadcrumb
            HStack(spacing: 8) {
                Image(systemName: s.page.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.purple)
                Text(s.page.rawValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            // Live Library Scanning Pill
            if s.isScanning {
                Button {
                    s.page = .serverControl
                } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Scanning (\(s.scanStatus?.count ?? 0))")
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.warningOrange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.warningOrange.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.warningOrange.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Media library scan in progress. Click to view Server Control.")
            }
            
            // Server Connection Status Pill
            if let active = s.active {
                Button {
                    s.page = .serverControl
                } label: {
                    HStack(spacing: 6) {
                        StatusDot(status: s.serverStatus)
                        Text(active.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                        if case .connected(_, let ping) = s.serverStatus {
                            Text("\(ping)ms")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("View Server Control & Admin")
            }
            
            // Server Control Shortcut Button
            Button {
                s.page = .serverControl
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(s.page == .serverControl ? Theme.purple : .secondary)
            }
            .buttonStyle(.plain)
            .help("Navidrome Server Control & Admin")
            
            // Refresh Library button
            Button {
                Task { await s.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(s.isRefreshing ? 360 : 0))
                    .animation(s.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: s.isRefreshing)
                    .foregroundStyle(s.isRefreshing ? Theme.purple : .secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh library from server")
        }
        .padding(.horizontal, 24)
        .frame(height: 48)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(AppState.self) var s
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header / App Identity (with macOS window button spacing)
            HStack(spacing: 10) {
                SonoLogo(size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sono")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Navidrome Client")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 14)
            .padding(.horizontal, 12)
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Section: Discover
                    sectionHeader("DISCOVER")
                    navButton(.listenNow, badge: nil)
                    navButton(.search, badge: nil)
                    navButton(.radio, badge: s.radioStations.isEmpty ? nil : "\(s.radioStations.count)")
                    
                    // Section: Library
                    sectionHeader("LIBRARY")
                    navButton(.library, badge: s.library.isEmpty ? nil : "\(s.library.count)")
                    navButton(.albums, badge: s.albums.isEmpty ? nil : "\(s.albums.count)")
                    navButton(.playlists, badge: s.playlists.isEmpty ? nil : "\(s.playlists.count)")
                    navButton(.liked, badge: s.liked.isEmpty ? nil : "\(s.liked.count)")
                    navButton(.history, badge: nil)
                    
                    // Section: Offline
                    sectionHeader("OFFLINE")
                    navButton(.downloads, badge: s.downloads.songs.isEmpty ? nil : "\(s.downloads.songs.count)")
                    
                    // Section: Server & Admin
                    sectionHeader("SERVER")
                    navButton(.serverControl, badge: s.isScanning ? "Scanning…" : (s.isAdmin ? "Admin" : nil))
                    navButton(.servers, badge: "\(s.servers.count)")
                }
                .padding(.horizontal, 8)
            }
            
            Spacer(minLength: 0)
            
            // Bottom Active Server Pill / Quick Manager
            if let active = s.active {
                Button {
                    s.page = .servers
                } label: {
                    HStack(spacing: 10) {
                        StatusDot(status: s.serverStatus)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(active.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(active.user)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .padding(.top, 10)
        .frame(width: 220)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Divider().overlay(Color.white.opacity(0.08))
        }
    }
    
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.top, 4)
    }
    
    private func navButton(_ p: Page, badge: String?) -> some View {
        let isSelected = s.page == p
        return Button {
            s.page = p
        } label: {
            HStack(spacing: 10) {
                Image(systemName: p.icon)
                    .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : Theme.purple)
                    .frame(width: 20)
                
                Text(p.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .secondary)
                
                Spacer()
                
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ?
                LinearGradient(colors: [Theme.purple, Theme.deep], startPoint: .leading, endPoint: .trailing) :
                LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Queue Panel

struct QueuePanel: View {
    @Environment(AppState.self) var s
    
    var body: some View {
        let p = s.player
        let upcoming = p.current.flatMap { c in p.queue.firstIndex(of: c).map { Array(p.queue[($0 + 1)...]) } } ?? []
        
        VStack(alignment: .leading, spacing: 16) {
            // Queue Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Playing Queue")
                        .font(.system(size: 16, weight: .bold))
                    Text("\(upcoming.count) track\(upcoming.count == 1 ? "" : "s") upcoming")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !upcoming.isEmpty {
                    Button("Clear") {
                        p.queue = p.current.map { [$0] } ?? []
                    }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                }
            }
            
            Divider().overlay(Color.white.opacity(0.08))
            
            // Now Playing Card
            if let c = p.current {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOW PLAYING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.purple)
                    
                    HStack(spacing: 12) {
                        Art(id: c.coverArt, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(c.artist ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        PlayingWaveform()
                    }
                    .padding(10)
                    .background(Theme.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            
            // Up Next List
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT UP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                
                if upcoming.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundStyle(.secondary.opacity(0.4))
                            .padding(.top, 20)
                        Text("No upcoming songs")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Add songs to queue or turn on shuffle.")
                            .font(.caption)
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(upcoming.enumerated()), id: \.element.id) { idx, song in
                                HStack(spacing: 8) {
                                    Text("\(idx + 1)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)
                                    SongRow(song: song, list: p.queue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Divider().overlay(Color.white.opacity(0.08))
        }
    }
}

// MARK: - Bottom Playback Bar

struct BottomBar: View {
    @Environment(AppState.self) var s
    @State private var isDraggingSeeker = false
    @State private var dragSeekTime: Double = 0
    
    var body: some View {
        @Bindable var p = s.player
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            VStack(spacing: 0) {
                Divider().overlay(Color.white.opacity(0.12))
                
                HStack(spacing: 20) {
                    // Left: Current Song Information
                    HStack(spacing: 12) {
                        if p.hasVideo {
                            VideoSurface(player: p.av)
                                .frame(width: 80, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if let c = p.current {
                            Art(id: c.coverArt, size: 52, cornerRadius: 8)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.05))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "music.note")
                                    .foregroundStyle(.secondary.opacity(0.4))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.current?.title ?? "No track playing")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            Text(p.current?.artist ?? "Select a song to start listening")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        if let c = p.current {
                            Button {
                                Task { await s.toggleLike(c) }
                            } label: {
                                Image(systemName: s.likedIDs.contains(c.id) ? "heart.fill" : "heart")
                                    .font(.system(size: 14))
                                    .foregroundStyle(s.likedIDs.contains(c.id) ? Theme.purple : .secondary)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            
                            DownloadButton(song: c)
                        }
                    }
                    .frame(width: 280, alignment: .leading)
                    
                    Spacer()
                    
                    // Center: Controls & Timeline Seeker
                    VStack(spacing: 6) {
                        // Transport Buttons
                        HStack(spacing: 20) {
                            // Shuffle
                            Button {
                                p.shuffle.toggle()
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(p.shuffle ? Theme.purple : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("True Shuffle")
                            
                            // Previous
                            Button {
                                p.previous()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .disabled(p.current == nil)
                            
                            // Play / Pause (Large Glowing Pill)
                            Button {
                                p.toggle()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Theme.purple, Theme.deep],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 42, height: 42)
                                        .shadow(color: Theme.purple.opacity(p.isPlaying ? 0.6 : 0.2), radius: p.isPlaying ? 8 : 4)
                                    
                                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)
                                        .offset(x: p.isPlaying ? 0 : 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(p.current == nil)
                            
                            // Next
                            Button {
                                p.next()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .disabled(p.current == nil)
                            
                            // Repeat
                            Button {
                                p.cycleRepeat()
                            } label: {
                                Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(p.repeatMode == .off ? .secondary : Theme.purple)
                            }
                            .buttonStyle(.plain)
                            .help("Repeat Mode: \(p.repeatMode == .off ? "Off" : p.repeatMode == .all ? "All" : "One")")
                        }
                        
                        // Timeline Scrubber
                        let maxDuration = Double(max(p.current?.duration ?? 1, 1))
                        let currentProgress = isDraggingSeeker ? dragSeekTime : p.time
                        let remaining = max(0, maxDuration - currentProgress)
                        
                        HStack(spacing: 8) {
                            Text(format(currentProgress))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                            
                            Slider(
                                value: Binding(
                                    get: { isDraggingSeeker ? dragSeekTime : p.time },
                                    set: { newValue in
                                        dragSeekTime = newValue
                                        p.seek(newValue)
                                    }
                                ),
                                in: 0...maxDuration
                            )
                            .tint(Theme.purple)
                            .frame(width: 260)
                            
                            Text("-\(format(remaining))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .leading)
                        }
                    }
                    
                    Spacer()
                    
                    // Right: Utilities & Audio Volume
                    HStack(spacing: 12) {
                        // Speed Menu
                        Menu {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { v in
                                Button("\(v, specifier: "%g")×") {
                                    p.speed = Float(v)
                                }
                            }
                        } label: {
                            Text("\(Double(p.speed), specifier: "%g")×")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Playback Speed")
                        
                        // Sleep Timer
                        Button {
                            if p.sleepAt != nil {
                                p.setSleep(minutes: nil)
                                s.showToast("Sleep timer cancelled", kind: .info)
                            } else {
                                p.setSleep(minutes: 30)
                                s.showToast("Sleep timer set for 30 minutes", kind: .info)
                            }
                        } label: {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(p.sleepAt == nil ? .secondary : Theme.purple)
                        }
                        .buttonStyle(.plain)
                        .help(p.sleepAt == nil ? "Sleep Timer" : "Sleep timer active")
                        // Lyrics Toggle
                        Button {
                            withAnimation { s.showLyrics.toggle() }
                        } label: {
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(s.showLyrics ? Theme.purple : p.current == nil ? .secondary.opacity(0.4) : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(p.current == nil)
                        .help("Synced Lyrics ")
                        
                        // Queue Toggle
                        Button {
                            s.showQueue.toggle()
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 14))
                                .foregroundStyle(s.showQueue ? Theme.purple : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Queue ")
                        
                        // Volume Control
                        HStack(spacing: 6) {
                            Button {
                                if p.volume > 0 {
                                    p.volume = 0
                                } else {
                                    p.volume = 0.8
                                }
                            } label: {
                                Image(systemName: p.volume == 0 ? "speaker.slash.fill" : p.volume < 0.33 ? "speaker.wave.1.fill" : p.volume < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Slider(value: $p.volume, in: 0...1)
                                .frame(width: 60)
                                .tint(Theme.purple)
                        }
                    }
                    .frame(width: 240, alignment: .trailing)
                }
                .padding(.horizontal, 24)
                .frame(height: 72)
                .background(.regularMaterial)
            }
        }
    }
}
