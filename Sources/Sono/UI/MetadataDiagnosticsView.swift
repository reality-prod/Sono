import SwiftUI

/// Library metadata inspection interface that identifies tracks and albums with missing artwork, incomplete metadata, or inconsistent information.
struct MetadataDiagnosticsView: View {
    @Environment(AppState.self) var s
    @State private var tracksWithIssues: [TrackIssue] = []
    @State private var albumsWithIssues: [AlbumIssue] = []
    @State private var isLoading = false
    @State private var selectedFilter: IssueType = .all
    
    enum IssueType: String, CaseIterable, Identifiable {
        case all = "All Issues"
        case missingArtwork = "Missing Artwork"
        case missingMetadata = "Missing Metadata"
        case incompleteInfo = "Incomplete Info"
        
        var id: String { rawValue }
    }
    
    struct TrackIssue: Identifiable {
        let id: String
        let song: Song
        let issues: [Issue]
        
        enum Issue: String {
            case missingArtwork = "Missing artwork"
            case missingArtist = "Missing artist"
            case missingAlbum = "Missing album"
            case missingDuration = "Missing duration"
            case missingYear = "Missing year"
            case missingTrackNumber = "Missing track number"
        }
    }
    
    struct AlbumIssue: Identifiable {
        let id: String
        let album: Album
        let issues: [Issue]
        
        enum Issue: String {
            case missingArtwork = "Missing artwork"
            case missingArtist = "Missing artist"
            case missingYear = "Missing year"
            case emptyAlbum = "No tracks"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Library Diagnostics")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Identify and fix metadata issues in your library")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    // Refresh button
                    Button {
                        Task { await analyzeLibrary() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                    .help("Refresh diagnostics")
                }
                
                // Summary Cards
                HStack(spacing: 16) {
                    SummaryCard(
                        title: "Tracks with Issues",
                        count: tracksWithIssues.count,
                        icon: "music.note",
                        color: .orange
                    )
                    SummaryCard(
                        title: "Albums with Issues",
                        count: albumsWithIssues.count,
                        icon: "square.stack",
                        color: .purple
                    )
                    SummaryCard(
                        title: "Total Issues",
                        count: totalIssueCount,
                        icon: "exclamationmark.triangle",
                        color: .red
                    )
                }
                
                // Filter
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(IssueType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 8)
                
                // Track Issues
                if !filteredTrackIssues.isEmpty {
                    Text("Tracks with Issues")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                    
                    VStack(spacing: 12) {
                        ForEach(filteredTrackIssues) { issue in
                            TrackIssueRow(issue: issue, client: s.client)
                        }
                    }
                }
                
                // Album Issues
                if !filteredAlbumIssues.isEmpty {
                    Text("Albums with Issues")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                    
                    VStack(spacing: 12) {
                        ForEach(filteredAlbumIssues) { issue in
                            AlbumIssueRow(issue: issue, client: s.client)
                        }
                    }
                }
                
                // Empty state
                if filteredTrackIssues.isEmpty && filteredAlbumIssues.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.successGreen)
                        Text("No Issues Found")
                            .font(.title2)
                            .foregroundStyle(.white)
                        Text("Your library metadata looks good!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 60)
                }
                
                Spacer()
            }
            .padding()
        }
        .background(Theme.black)
        .onAppear {
            Task { await analyzeLibrary() }
        }
        .navigationTitle("Diagnostics")
    }
    
    private var totalIssueCount: Int {
        tracksWithIssues.reduce(0) { $0 + $1.issues.count } + 
        albumsWithIssues.reduce(0) { $0 + $1.issues.count }
    }
    
    private var filteredTrackIssues: [TrackIssue] {
        guard selectedFilter != .all else { return tracksWithIssues }
        return tracksWithIssues.filter { issue in
            issue.issues.contains { issueType in
                switch selectedFilter {
                case .missingArtwork: issueType == .missingArtwork
                case .missingMetadata: 
                    issueType == .missingArtist || issueType == .missingAlbum || issueType == .missingDuration
                case .incompleteInfo:
                    issueType == .missingYear || issueType == .missingTrackNumber
                case .all: true
                }
            }
        }
    }
    
    private var filteredAlbumIssues: [AlbumIssue] {
        guard selectedFilter != .all else { return albumsWithIssues }
        return albumsWithIssues.filter { issue in
            issue.issues.contains { issueType in
                switch selectedFilter {
                case .missingArtwork: issueType == .missingArtwork
                case .missingMetadata: 
                    issueType == .missingArtist
                case .incompleteInfo:
                    issueType == .missingYear || issueType == .emptyAlbum
                case .all: true
                }
            }
        }
    }
    
    private func analyzeLibrary() async {
        isLoading = true
        defer { isLoading = false }
        
        // Analyze tracks
        let allTracks = s.library + s.liked
        var trackIssues: [TrackIssue] = []
        
        for track in allTracks {
            var issues: [TrackIssue.Issue] = []
            
            if track.coverArt == nil || track.coverArt?.isEmpty == true {
                issues.append(.missingArtwork)
            }
            if track.artist == nil || track.artist?.isEmpty == true {
                issues.append(.missingArtist)
            }
            if track.album == nil || track.album?.isEmpty == true {
                issues.append(.missingAlbum)
            }
            if track.duration == nil || track.duration == 0 {
                issues.append(.missingDuration)
            }
            if track.year == nil {
                issues.append(.missingYear)
            }
            if track.track == nil {
                issues.append(.missingTrackNumber)
            }
            
            if !issues.isEmpty {
                trackIssues.append(TrackIssue(id: track.id, song: track, issues: issues))
            }
        }
        
        // Analyze albums
        var albumIssues: [AlbumIssue] = []
        
        for album in s.albums {
            var issues: [AlbumIssue.Issue] = []
            
            if album.coverArt == nil || album.coverArt?.isEmpty == true {
                issues.append(.missingArtwork)
            }
            if album.artist == nil || album.artist?.isEmpty == true {
                issues.append(.missingArtist)
            }
            if album.year == nil {
                issues.append(.missingYear)
            }
            if album.songCount == 0 {
                issues.append(.emptyAlbum)
            }
            
            if !issues.isEmpty {
                albumIssues.append(AlbumIssue(id: album.id, album: album, issues: issues))
            }
        }
        
        tracksWithIssues = trackIssues
        albumsWithIssues = albumIssues
    }
}

// MARK: - Subviews

private struct SummaryCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct TrackIssueRow: View {
    let issue: MetadataDiagnosticsView.TrackIssue
    let client: NavidromeClient?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Album art placeholder
            Art(id: issue.song.coverArt, size: 40, cornerRadius: 8)
                .opacity(issue.song.coverArt == nil ? 0.5 : 1.0)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.song.title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                if let artist = issue.song.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                // Issue badges
                HStack(spacing: 6) {
                    ForEach(issue.issues, id: \.self) { issueType in
                        Text(issueType.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                            )
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Action button
            Button {
                // Could open a detail view or actions menu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
    }
}

private struct AlbumIssueRow: View {
    let issue: MetadataDiagnosticsView.AlbumIssue
    let client: NavidromeClient?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Album art placeholder
            Art(id: issue.album.coverArt, size: 40, cornerRadius: 8)
                .opacity(issue.album.coverArt == nil ? 0.5 : 1.0)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.album.name)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                if let artist = issue.album.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                // Issue badges
                HStack(spacing: 6) {
                    ForEach(issue.issues, id: \.self) { issueType in
                        Text(issueType.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                            )
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Action button
            Button {
                // Could open a detail view or actions menu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
    }
}
