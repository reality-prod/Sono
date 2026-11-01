import SwiftUI
import AVKit

func format(_ t: Double) -> String {
    let seconds = Int(t)
    let m = seconds / 60
    let s = seconds % 60
    if m >= 60 {
        let h = m / 60
        let remM = m % 60
        return String(format: "%d:%02d:%02d", h, remM, s)
    }
    return String(format: "%d:%02d", m, s)
}

func formatDurationHuman(_ totalSeconds: Int) -> String {
    let m = totalSeconds / 60
    if m < 60 {
        return "\(m) min"
    }
    let h = m / 60
    let remM = m % 60
    return remM > 0 ? "\(h) hr \(remM) min" : "\(h) hr"
}

struct PlayingWaveform: View {
    @State private var phase = false
    var color: Color = Theme.purple
    
    var body: some View {
        HStack(spacing: 2) {
            Capsule()
                .fill(color)
                .frame(width: 3, height: phase ? 14 : 6)
            Capsule()
                .fill(color)
                .frame(width: 3, height: phase ? 8 : 16)
            Capsule()
                .fill(color)
                .frame(width: 3, height: phase ? 15 : 9)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                phase.toggle()
            }
        }
    }
}

struct Art: View {
    @Environment(AppState.self) var s
    let id: String?
    var size: CGFloat = 44
    var cornerRadius: CGFloat?
    
    var radius: CGFloat {
        cornerRadius ?? (size * 0.16)
    }
    
    var body: some View {
        Group {
            if let id, let url = s.client?.cover(id, size: Int(size * 2)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        fallbackView
                    @unknown default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
    }
    
    private var fallbackView: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.1), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.secondary.opacity(0.6))
        }
    }
}

struct SongRow: View {
    @Environment(AppState.self) var s
    let song: Song
    let list: [Song]
    var trackIndex: Int? = nil
    var showAlbum: Bool = false
    
    @State private var isHovered = false
    
    var isCurrent: Bool { s.player.current == song }
    var isPlaying: Bool { isCurrent && s.player.isPlaying }
    var isLiked: Bool { s.likedIDs.contains(song.id) }
    
    var body: some View {
        HStack(spacing: 12) {
            // Track number or playing equalizer
            if let index = trackIndex {
                ZStack {
                    if isPlaying {
                        PlayingWaveform()
                    } else if isHovered {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.purple)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, alignment: .center)
            }
            
            // Artwork
            ZStack {
                Art(id: song.coverArt, size: 40)
                if trackIndex == nil && isPlaying {
                    RoundedRectangle(cornerRadius: 40 * 0.16)
                        .fill(Color.black.opacity(0.45))
                    PlayingWaveform(color: .white)
                }
            }
            .frame(width: 40, height: 40)
            
            // Title & Artist
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.purple : .white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(song.artist ?? "Unknown Artist")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    if showAlbum, let alb = song.album, !alb.isEmpty {
                        Text("•").foregroundStyle(.secondary.opacity(0.4))
                        Text(alb)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Like Button (shown on hover or if liked)
            if isLiked || isHovered {
                Button {
                    Task { await s.toggleLike(song) }
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 13))
                        .foregroundStyle(isLiked ? Theme.purple : .secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
            
            // Download indicator
            DownloadButton(song: song)
            
            // Duration
            Text(format(Double(song.duration ?? 0)))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
            
            // Context Menu button
            Menu {
                contextMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(isHovered ? 1.0 : 0.4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? Theme.purple.opacity(0.18) : isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            s.player.play(song, in: list)
        }
        .onTapGesture(count: 1) {
            s.player.play(song, in: list)
        }
        .contextMenu {
            contextMenuItems
        }
    }
    
    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            s.player.play(song, in: list)
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        
        Button {
            s.player.playNext(song)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        
        Button {
            s.player.enqueue(song)
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        
        Divider()
        
        Button {
            Task { await s.toggleLike(song) }
        } label: {
            Label(isLiked ? "Unlike" : "Love Song", systemImage: isLiked ? "heart.slash" : "heart.fill")
        }
        
        Menu("Add to Playlist") {
            ForEach(s.playlists) { p in
                Button(p.name) {
                    Task { await s.add(song, to: p) }
                }
            }
            Divider()
            Button("New Playlist…") {
                Task { await s.createPlaylist(song.title, with: song) }
            }
        }
        
        Divider()
        
        if s.downloads.has(song.id) {
            Button("Remove Offline File") {
                s.downloads.remove(song)
                s.showToast("Removed offline file", kind: .info)
            }
        } else {
            Button("Download for Offline") {
                s.download([song])
            }
        }
        
        Button("Copy Song Info") {
            let info = "\(song.title) - \(song.artist ?? "Unknown")"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(info, forType: .string)
            s.showToast("Copied to clipboard", kind: .info)
        }
    }
}

struct DownloadButton: View {
    @Environment(AppState.self) var s
    let song: Song
    
    var body: some View {
        if s.downloads.active.contains(song.id) {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 18, height: 18)
        } else if s.downloads.has(song.id) {
            Button {
                s.downloads.remove(song)
                s.showToast("Removed offline download", kind: .info)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.successGreen)
            }
            .buttonStyle(.plain)
            .help("Downloaded offline. Click to remove.")
        } else {
            Button {
                s.download([song])
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Download for offline listening")
        }
    }
}

enum SortMode: String, CaseIterable {
    case none = "Default"
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case duration = "Duration"
}

struct SongList: View {
    @Environment(AppState.self) var s
    let title: String
    let subtitle: String
    let songs: [Song]
    var showFolder = false
    var showTrackIndex = false
    
    @State private var filter = ""
    @State private var sort: SortMode = .none
    
    var shown: [Song] {
        var r = filter.isEmpty ? songs : songs.filter {
            ($0.title + " " + ($0.artist ?? "") + " " + ($0.album ?? "")).localizedCaseInsensitiveContains(filter)
        }
        switch sort {
        case .none: break
        case .title:
            r.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .artist:
            r.sort { ($0.artist ?? "").localizedCompare($1.artist ?? "") == .orderedAscending }
        case .album:
            r.sort { ($0.album ?? "").localizedCompare($1.album ?? "") == .orderedAscending }
        case .duration:
            r.sort { ($0.duration ?? 0) < ($1.duration ?? 0) }
        }
        return r
    }
    
    var totalSeconds: Int {
        songs.compactMap(\.duration).reduce(0, +)
    }
    
    var body: some View {
        let list = shown
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Page Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 8) {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        
                        if totalSeconds > 0 {
                            Text("•").foregroundStyle(.secondary.opacity(0.4))
                            Text(formatDurationHuman(totalSeconds))
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Controls Toolbar
                HStack(spacing: 10) {
                    Button {
                        if let f = list.first {
                            s.player.play(f, in: list)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.purple)
                    .disabled(list.isEmpty)
                    
                    Button {
                        s.player.shuffle = true
                        if let f = list.randomElement() {
                            s.player.play(f, in: list)
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(list.isEmpty)
                    
                    Button {
                        s.download(list)
                    } label: {
                        Label("Download All", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(list.isEmpty)
                    
                    Menu {
                        Button("Playlist (.m3u8)") {
                            Exporter.m3u(list, title: title, downloads: s.downloads)
                            s.showToast("Exported .m3u8 playlist", kind: .success)
                        }
                        Button("Spreadsheet (.csv)") {
                            Exporter.csv(list, title: title)
                            s.showToast("Exported .csv file", kind: .success)
                        }
                        Button("Data (.json)") {
                            Exporter.json(list, title: title)
                            s.showToast("Exported .json file", kind: .success)
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .disabled(list.isEmpty)
                    
                    if showFolder {
                        Button {
                            s.downloads.reveal()
                        } label: {
                            Label("Open Folder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    // Filter input
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("Filter list…", text: $filter)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        if !filter.isEmpty {
                            Button {
                                filter = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .frame(width: 170)
                    
                    // Sort picker
                    Picker("Sort", selection: $sort) {
                        ForEach(SortMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .frame(width: 130)
                }
                
                // Track table header
                HStack(spacing: 12) {
                    if showTrackIndex {
                        Text("#")
                            .frame(width: 24, alignment: .center)
                    }
                    Text("TITLE")
                        .padding(.leading, 40 + 12)
                    Spacer()
                    Text("DURATION")
                        .frame(width: 60, alignment: .trailing)
                    Color.clear.frame(width: 50)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.top, 4)
                
                Divider().overlay(Color.white.opacity(0.06))
                
                // Song Rows
                if list.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: filter.isEmpty ? "music.note" : "magnifyingglass")
                            .font(.system(size: 38))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.top, 30)
                        
                        Text(filter.isEmpty ? "No tracks found" : "No matches for \"\(filter)\"")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { idx, song in
                            SongRow(
                                song: song,
                                list: list,
                                trackIndex: showTrackIndex ? (song.track ?? (idx + 1)) : nil,
                                showAlbum: true
                            )
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if canImport(AVKit) && os(macOS)
import AVKit

struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .none
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {}
}
#else
struct VideoSurface: View {
    let player: Any?
    var body: some View {
        Color.black
    }
}
#endif
