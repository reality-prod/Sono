import SwiftUI

// MARK: - Listen Now Page

struct ListenNowPage: View {
    @Environment(AppState.self) var s
    
    var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        let timeGreet = h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        if let user = s.active?.user, !user.isEmpty {
            return "\(timeGreet), \(user.capitalized)"
        }
        return timeGreet
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header with Greeting and Stats
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(greeting)
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Your personal sanctuary for high-fidelity music.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // Quick Action Buttons
                        if !s.library.isEmpty {
                            HStack(spacing: 10) {
                                Button {
                                    s.player.shuffle = true
                                    if let randomSong = s.library.randomElement() {
                                        s.player.play(randomSong, in: s.library)
                                    }
                                } label: {
                                    Label("Shuffle Library", systemImage: "shuffle")
                                }
                                .buttonStyle(.bordered)
                                
                                Button {
                                    if let f = s.recommended.first ?? s.library.first {
                                        s.player.play(f, in: s.recommended.isEmpty ? s.library : s.recommended)
                                    }
                                } label: {
                                    Label("Play All", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.purple)
                            }
                        }
                    }
                    
                    // Quick Library Status Pills
                    if !s.library.isEmpty {
                        HStack(spacing: 12) {
                            StatPill(icon: "music.note", count: s.library.count, label: "tracks")
                            StatPill(icon: "square.stack", count: s.albums.count, label: "albums")
                            StatPill(icon: "heart.fill", count: s.liked.count, label: "liked")
                            StatPill(icon: "arrow.down.circle.fill", count: s.downloads.songs.count, label: "offline")
                        }
                    }
                }
                
                // Active Server Offline Warning
                if let err = s.activeServerError {
                    HStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(Theme.errorRed)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Server Connection Error")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.errorRed)
                            Text(err.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        Button("Manage Servers") {
                            s.page = .servers
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.errorRed.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.errorRed.opacity(0.3), lineWidth: 1))
                    )
                }
                
                // Content Sections
                if s.library.isEmpty && s.serverStatus.isConnected {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.house")
                            .font(.system(size: 46))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.top, 20)
                        Text("Your library appears to be empty.")
                            .font(.headline)
                        Text("Add music files to your Navidrome music folder, or trigger a library scan.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    if !s.recommended.isEmpty {
                        section("Made For You", subtitle: "Curated tracks based on your taste", songs: s.recommended)
                    }
                    
                    if !s.player.history.isEmpty {
                        section("Jump Back In", subtitle: "Recently played tracks", songs: Array(s.player.history.prefix(8)))
                    }
                    
                    if !s.rediscover.isEmpty {
                        section("Rediscover Your Library", subtitle: "Hidden gems from your collection", songs: s.rediscover)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func section(_ title: String, subtitle: String, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let f = songs.first {
                        s.player.play(f, in: songs)
                    }
                } label: {
                    Label("Play Section", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.purple)
            }
            
            VStack(spacing: 2) {
                ForEach(songs.prefix(8)) { song in
                    SongRow(song: song, list: songs, showAlbum: true)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

struct StatPill: View {
    let icon: String
    let count: Int
    let label: String
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.purple)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05), in: Capsule())
    }
}

// MARK: - Search Page

struct SearchPage: View {
    @Environment(AppState.self) var s
    @State private var filterCategory: SearchCategory = .all
    
    enum SearchCategory: String, CaseIterable {
        case all = "All"
        case songs = "Songs"
        case albums = "Albums"
    }
    
    var matchingAlbums: [Album] {
        guard !s.query.isEmpty else { return [] }
        return s.albums.filter {
            $0.name.localizedCaseInsensitiveContains(s.query) ||
            ($0.artist ?? "").localizedCaseInsensitiveContains(s.query)
        }
    }
    
    var body: some View {
        @Bindable var s = s
        VStack(alignment: .leading, spacing: 0) {
            // Search Input Header
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.purple)
                    
                    TextField("Search songs, artists, and albums…", text: $s.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium))
                        .onSubmit { Task { await s.runSearch() } }
                        .onChange(of: s.query) { Task { await s.runSearch() } }
                    
                    if !s.query.isEmpty {
                        Button {
                            s.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Text("⌘F")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.purple.opacity(s.query.isEmpty ? 0.2 : 0.6), lineWidth: 1)
                )
                
                // Category Filter Pills
                HStack(spacing: 8) {
                    ForEach(SearchCategory.allCases, id: \.self) { cat in
                        Button {
                            filterCategory = cat
                        } label: {
                            Text(cat.rawValue)
                                .font(.system(size: 12, weight: filterCategory == cat ? .bold : .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(filterCategory == cat ? Theme.purple : Color.white.opacity(0.06))
                                )
                                .foregroundStyle(filterCategory == cat ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    if !s.query.isEmpty {
                        Text("\(s.results.count) song\(s.results.count == 1 ? "" : "s") • \(matchingAlbums.count) album\(matchingAlbums.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding([.horizontal, .top], 28)
            .padding(.bottom, 12)
            
            // Results Content
            if s.query.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .padding(.top, 60)
                    Text("Search Your Music")
                        .font(.title2.bold())
                    Text("Type a song title, artist, or album name to explore your Navidrome library.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Matching Albums Section (if showing All or Albums)
                        if (filterCategory == .all || filterCategory == .albums) && !matchingAlbums.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Albums")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(matchingAlbums) { album in
                                            AlbumGridItem(album: album)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Matching Songs Section (if showing All or Songs)
                        if filterCategory == .all || filterCategory == .songs {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Songs")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                
                                if s.results.isEmpty {
                                    Text("No songs match \"\(s.query)\"")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 10)
                                } else {
                                    LazyVStack(spacing: 2) {
                                        ForEach(s.results) { song in
                                            SongRow(song: song, list: s.results, showAlbum: true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(28)
                }
            }
        }
    }
}

// MARK: - Albums Page

struct AlbumsPage: View {
    @Environment(AppState.self) var s
    @State private var open: Album?
    @State private var albumSongs: [Song] = []
    @State private var isGridView = true
    @State private var filter = ""
    
    var shownAlbums: [Album] {
        if filter.isEmpty { return s.albums }
        return s.albums.filter {
            $0.name.localizedCaseInsensitiveContains(filter) ||
            ($0.artist ?? "").localizedCaseInsensitiveContains(filter)
        }
    }
    
    var body: some View {
        if let a = open {
            AlbumDetailView(album: a, songs: albumSongs) {
                open = nil
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Albums")
                                .font(.system(size: 38, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("\(s.albums.count) albums in your collection")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // Filter
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Filter albums…", text: $filter)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .frame(width: 170)
                        
                        // View mode toggle
                        Picker("View", selection: $isGridView) {
                            Image(systemName: "square.grid.2x2").tag(true)
                            Image(systemName: "list.bullet").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                    }
                    
                    if shownAlbums.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.stack")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .padding(.top, 40)
                            Text(filter.isEmpty ? "No albums found" : "No albums matching \"\(filter)\"")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    } else if isGridView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)], spacing: 24) {
                            ForEach(shownAlbums) { album in
                                Button {
                                    open = album
                                    Task { albumSongs = (try? await s.client?.album(album.id)) ?? [] }
                                } label: {
                                    AlbumGridItem(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(shownAlbums) { a in
                                Button {
                                    open = a
                                    Task { albumSongs = (try? await s.client?.album(a.id)) ?? [] }
                                } label: {
                                    HStack(spacing: 14) {
                                        Art(id: a.coverArt, size: 52)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(a.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.white)
                                            Text(a.artist ?? "Unknown Artist")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if let y = a.year {
                                            Text("\(y)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct AlbumGridItem: View {
    let album: Album
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Art(id: album.coverArt, size: 160, cornerRadius: 12)
                
                if isHovered {
                    Circle()
                        .fill(Theme.purple)
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 14)).foregroundStyle(.white))
                        .shadow(color: Color.black.opacity(0.4), radius: 6)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 160, height: 160)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(album.artist ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 160, alignment: .leading)
        }
        .onHover { isHovered = $0 }
    }
}

struct AlbumDetailView: View {
    @Environment(AppState.self) var s
    let album: Album
    let songs: [Song]
    let onBack: () -> Void
    
    var totalDuration: Int {
        songs.compactMap(\.duration).reduce(0, +)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Back Button
                Button {
                    onBack()
                } label: {
                    Label("All Albums", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.purple)
                }
                .buttonStyle(.plain)
                
                // Album Banner Hero
                HStack(spacing: 24) {
                    Art(id: album.coverArt, size: 180, cornerRadius: 16)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ALBUM")
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.purple)
                        
                        Text(album.name)
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text(album.artist ?? "Unknown Artist")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            if let year = album.year {
                                Text("\(year)")
                                Text("•")
                            }
                            Text("\(songs.count) tracks")
                            if totalDuration > 0 {
                                Text("•")
                                Text(formatDurationHuman(totalDuration))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        
                        // Action buttons
                        HStack(spacing: 12) {
                            Button {
                                if let f = songs.first {
                                    s.player.play(f, in: songs)
                                }
                            } label: {
                                Label("Play Album", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.purple)
                            .disabled(songs.isEmpty)
                            
                            Button {
                                s.player.shuffle = true
                                if let f = songs.randomElement() {
                                    s.player.play(f, in: songs)
                                }
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                            }
                            .buttonStyle(.bordered)
                            .disabled(songs.isEmpty)
                            
                            Button {
                                s.download(songs)
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.bordered)
                            .disabled(songs.isEmpty)
                        }
                        .padding(.top, 6)
                    }
                    Spacer()
                }
                
                Divider().overlay(Color.white.opacity(0.08))
                
                // Track list
                LazyVStack(spacing: 2) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                        SongRow(
                            song: song,
                            list: songs,
                            trackIndex: song.track ?? (idx + 1),
                            showAlbum: false
                        )
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Playlists Page

struct PlaylistsPage: View {
    @Environment(AppState.self) var s
    @State private var open: Playlist?
    @State private var playlistSongs: [Song] = []
    @State private var showCreateSheet = false
    @State private var newPlaylistName = ""
    @State private var showDeleteConfirm = false
    
    var body: some View {
        if let p = open {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Back & Actions header
                    HStack {
                        Button {
                            open = nil
                        } label: {
                            Label("All Playlists", systemImage: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.purple)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Playlist Hero
                    HStack(spacing: 20) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [Theme.purple, Theme.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 140, height: 140)
                            Image(systemName: "music.note.list")
                                .font(.system(size: 44))
                                .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PLAYLIST")
                                .font(.caption2.bold())
                                .foregroundStyle(Theme.purple)
                            
                            Text(p.name)
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            
                            Text("\(playlistSongs.count) songs")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 10) {
                                Button {
                                    if let f = playlistSongs.first {
                                        s.player.play(f, in: playlistSongs)
                                    }
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.purple)
                                .disabled(playlistSongs.isEmpty)
                                
                                Button {
                                    s.player.shuffle = true
                                    if let f = playlistSongs.randomElement() {
                                        s.player.play(f, in: playlistSongs)
                                    }
                                } label: {
                                    Label("Shuffle", systemImage: "shuffle")
                                }
                                .buttonStyle(.bordered)
                                .disabled(playlistSongs.isEmpty)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    Divider().overlay(Color.white.opacity(0.08))
                    
                    // Tracks
                    if playlistSongs.isEmpty {
                        Text("This playlist has no tracks.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(playlistSongs.enumerated()), id: \.element.id) { idx, song in
                                SongRow(song: song, list: playlistSongs, trackIndex: idx + 1, showAlbum: true)
                            }
                        }
                    }
                }
                .padding(28)
            }
            .confirmationDialog("Delete Playlist", isPresented: $showDeleteConfirm) {
                Button("Delete \"\(p.name)\"", role: .destructive) {
                    Task {
                        await s.deletePlaylist(p)
                        open = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this playlist from your server?")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Page Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Playlists")
                                .font(.system(size: 38, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("\(s.playlists.count) personal playlists")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            showCreateSheet = true
                        } label: {
                            Label("New Playlist", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.purple)
                    }
                    
                    // Playlist Cards
                    if s.playlists.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .padding(.top, 40)
                            
                            VStack(spacing: 4) {
                                Text("No Playlists Yet")
                                    .font(.headline)
                                Text("Create your first playlist to organize your favorite music.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Button("Create Playlist") {
                                showCreateSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.purple)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)], spacing: 20) {
                            ForEach(s.playlists) { p in
                                Button {
                                    open = p
                                    Task { playlistSongs = (try? await s.client?.playlist(p.id)) ?? [] }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 14)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Theme.purple.opacity(0.7), Theme.deep],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 160, height: 160)
                                            Image(systemName: "music.note.list")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.white)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(p.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Text("\(p.songCount ?? 0) songs")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 160, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sheet(isPresented: $showCreateSheet) {
                VStack(spacing: 20) {
                    Text("New Playlist")
                        .font(.title2.bold())
                    
                    TextField("Playlist Name", text: $newPlaylistName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            newPlaylistName = ""
                            showCreateSheet = false
                        }
                        .buttonStyle(.plain)
                        
                        Button("Create") {
                            let name = newPlaylistName
                            newPlaylistName = ""
                            showCreateSheet = false
                            Task { await s.createPlaylist(name) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.purple)
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(28)
                .frame(width: 340)
            }
        }
    }
}
