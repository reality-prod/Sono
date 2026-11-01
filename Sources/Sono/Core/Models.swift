import Foundation

struct Server: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var user: String
    var lastTested: Date?
    var lastPingMs: Int?
}

struct Song: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let duration: Int?
    let coverArt: String?
    let suffix: String?
    let track: Int?
    let year: Int?
    
    init(id: String, title: String, artist: String? = nil, album: String? = nil, duration: Int? = nil, coverArt: String? = nil, suffix: String? = nil, track: Int? = nil, year: Int? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.coverArt = coverArt
        self.suffix = suffix
        self.track = track
        self.year = year
    }
}

struct Album: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let artist: String?
    let coverArt: String?
    let year: Int?
    let songCount: Int?
    let duration: Int?
}

struct Playlist: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let songCount: Int?
    let duration: Int?
    let comment: String?
}

struct SubsonicError: Codable, Hashable {
    let code: Int
    let message: String
}

enum NavidromeError: LocalizedError, Hashable {
    case invalidURL(String)
    case unreachable(String)
    case unauthorized(String)
    case serverError(code: Int, message: String)
    case invalidResponse(String)
    case notConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let raw):
            return "Invalid server address: \"\(raw)\". Please provide a valid URL like http://192.168.1.10:4533"
        case .unreachable(let reason):
            return "Cannot reach server: \(reason)"
        case .unauthorized(let message):
            return "Authentication failed: \(message)"
        case .serverError(let code, let message):
            switch code {
            case 40:
                return "Incorrect username or password (Subsonic Error 40)."
            case 41:
                return "Token authentication not supported for this user account (Subsonic Error 41)."
            case 50:
                return "User is not authorized for this operation (Subsonic Error 50)."
            default:
                return "Subsonic Server Error \(code): \(message)"
            }
        case .invalidResponse(let reason):
            return "Invalid response from server: \(reason)"
        case .notConfigured:
            return "No server configured"
        }
    }
    
    var recoverySuggestion: String {
        switch self {
        case .invalidURL:
            return "Check the URL format. Ensure it starts with http:// or https:// and contains the correct port (default is 4533)."
        case .unreachable:
            return "Ensure your Navidrome server is running and accessible on your local network or internet. Check firewall settings."
        case .unauthorized, .serverError(code: 40, _):
            return "Verify that your username and password are correct. Note that passwords are case-sensitive."
        case .invalidResponse:
            return "Check if the URL points to a Navidrome or Subsonic-compatible server. If using a reverse proxy, ensure headers and paths are passed correctly."
        default:
            return "Check your server configuration and network connection, then try again."
        }
    }
}

struct ConnectionResult: Hashable {
    let success: Bool
    let serverVersion: String?
    let latencyMs: Int
    let error: NavidromeError?
    let diagnosticDetails: String?
}

// MARK: - Admin & Server Control Models

struct ScanStatus: Codable, Hashable {
    let scanning: Bool
    let count: Int?
    let folderCount: Int?
    let lastScan: String?
    
    enum CodingKeys: String, CodingKey {
        case scanning, count, folderCount, lastScan
    }
    
    init(scanning: Bool, count: Int? = nil, folderCount: Int? = nil, lastScan: String? = nil) {
        self.scanning = scanning
        self.count = count
        self.folderCount = folderCount
        self.lastScan = lastScan
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let boolVal = try? container.decode(Bool.self, forKey: .scanning) {
            self.scanning = boolVal
        } else if let strVal = try? container.decode(String.self, forKey: .scanning) {
            self.scanning = (strVal.lowercased() == "true")
        } else {
            self.scanning = false
        }
        self.count = try? container.decode(Int.self, forKey: .count)
        self.folderCount = try? container.decode(Int.self, forKey: .folderCount)
        self.lastScan = try? container.decode(String.self, forKey: .lastScan)
    }
}

struct MusicFolder: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id, name
    }
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = String(intId)
        } else if let strId = try? container.decode(String.self, forKey: .id) {
            self.id = strId
        } else {
            self.id = UUID().uuidString
        }
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Media Folder"
    }
}

struct MusicFoldersResponse: Decodable {
    let musicFolder: [MusicFolder]?
    
    enum CodingKeys: String, CodingKey {
        case musicFolder
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decode([MusicFolder].self, forKey: .musicFolder) {
            self.musicFolder = list
        } else if let single = try? container.decode(MusicFolder.self, forKey: .musicFolder) {
            self.musicFolder = [single]
        } else {
            self.musicFolder = []
        }
    }
}

struct SubsonicUser: Identifiable, Hashable, Codable {
    var id: String { username }
    let username: String
    let email: String?
    let scrobblingEnabled: Bool?
    let adminRole: Bool?
    let settingsRole: Bool?
    let downloadRole: Bool?
    let uploadRole: Bool?
    let playlistRole: Bool?
    let coverArtRole: Bool?
    let commentRole: Bool?
    let podcastRole: Bool?
    let streamRole: Bool?
    let jukeboxRole: Bool?
    let shareRole: Bool?
    let videoConversionRole: Bool?
    let maxBitRate: Int?
    
    var isAdmin: Bool { adminRole == true }
    var canDownload: Bool { downloadRole != false }
    var canUpload: Bool { uploadRole == true }
    var canStream: Bool { streamRole != false }
    var canManagePlaylists: Bool { playlistRole != false }
    var canShare: Bool { shareRole == true }
}

struct UsersResponse: Decodable {
    let user: [SubsonicUser]?
    
    enum CodingKeys: String, CodingKey {
        case user
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decode([SubsonicUser].self, forKey: .user) {
            self.user = list
        } else if let single = try? container.decode(SubsonicUser.self, forKey: .user) {
            self.user = [single]
        } else {
            self.user = []
        }
    }
}

struct InternetRadioStation: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let streamUrl: String
    let homepageUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, streamUrl, homepageUrl
    }
    
    init(id: String, name: String, streamUrl: String, homepageUrl: String? = nil) {
        self.id = id
        self.name = name
        self.streamUrl = streamUrl
        self.homepageUrl = homepageUrl
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let strId = try? container.decode(String.self, forKey: .id) {
            self.id = strId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = String(intId)
        } else {
            self.id = UUID().uuidString
        }
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Radio Station"
        self.streamUrl = (try? container.decode(String.self, forKey: .streamUrl)) ?? ""
        self.homepageUrl = try? container.decode(String.self, forKey: .homepageUrl)
    }
}

struct RadioStationsResponse: Decodable {
    let internetRadioStation: [InternetRadioStation]?
    
    enum CodingKeys: String, CodingKey {
        case internetRadioStation
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decode([InternetRadioStation].self, forKey: .internetRadioStation) {
            self.internetRadioStation = list
        } else if let single = try? container.decode(InternetRadioStation.self, forKey: .internetRadioStation) {
            self.internetRadioStation = [single]
        } else {
            self.internetRadioStation = []
        }
    }
}

struct OpenSubsonicExtension: Identifiable, Hashable, Codable {
    var id: String { name }
    let name: String
    let versions: [Int]?
}

struct ServerLicense: Codable, Hashable {
    let valid: Bool?
    let email: String?
    let licenseExpires: String?
}

struct Genre: Identifiable, Hashable, Codable {
    var id: String { value }
    let value: String
    let songCount: Int?
    let albumCount: Int?
}

struct GenresResponse: Decodable {
    let genre: [Genre]?
    
    enum CodingKeys: String, CodingKey {
        case genre
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decode([Genre].self, forKey: .genre) {
            self.genre = list
        } else if let single = try? container.decode(Genre.self, forKey: .genre) {
            self.genre = [single]
        } else {
            self.genre = []
        }
    }
}

struct SubsonicLyrics: Decodable {
    let artist: String?
    let title: String?
    let content: String?
}

struct OpenSubsonicLyricsList: Decodable {
    struct StructuredLyrics: Decodable {
        struct Line: Decodable {
            let start: Int? // Start time in milliseconds
            let value: String?
        }
        let lang: String?
        let synced: Bool?
        let line: [Line]?
    }
    let structuredLyrics: [StructuredLyrics]?
}

struct Envelope: Decodable {
    struct Body: Decodable {
        struct SongList: Decodable { let song: [Song]? }
        struct AlbumList: Decodable { let album: [Album]? }
        struct Playlists: Decodable { let playlist: [Playlist]? }
        struct PlaylistDetail: Decodable { let entry: [Song]? }
        
        let status: String
        let version: String?
        let type: String?
        let serverVersion: String?
        let error: SubsonicError?
        
        let randomSongs: SongList?
        let similarSongs2: SongList?
        let searchResult3: SongList?
        let starred2: SongList?
        let albumList2: AlbumList?
        let album: SongList?
        let playlists: Playlists?
        let playlist: PlaylistDetail?
        let lyrics: SubsonicLyrics?
        let lyricsList: OpenSubsonicLyricsList?
        
        // Admin & Controls
        let scanStatus: ScanStatus?
        let musicFolders: MusicFoldersResponse?
        let users: UsersResponse?
        let user: SubsonicUser?
        let internetRadioStations: RadioStationsResponse?
        let openSubsonicExtensions: [OpenSubsonicExtension]?
        let license: ServerLicense?
        let genres: GenresResponse?
        
        // Active sessions
        let activeSessions: ActiveSessionsResponse?
    }
    let body: Body
    enum CodingKeys: String, CodingKey { case body = "subsonic-response" }
}

// MARK: - Server Info Models

struct ServerInfo: Codable, Hashable {
    let serverVersion: String
    let apiVersion: String
    let extensions: [OpenSubsonicExtension]
    let user: String?
    let latencyMs: Int?
    
    init(serverVersion: String, apiVersion: String, extensions: [OpenSubsonicExtension], user: String? = nil, latencyMs: Int? = nil) {
        self.serverVersion = serverVersion
        self.apiVersion = apiVersion
        self.extensions = extensions
        self.user = user
        self.latencyMs = latencyMs
    }
}

struct ServerCapabilities: Codable, Hashable {
    let canScan: Bool
    let canAdmin: Bool
    let canUpload: Bool
    let canDownload: Bool
    let canStream: Bool
    let canGetLyrics: Bool
    let canGetCoverArt: Bool
    let supportsOpenSubsonic: Bool
    let openSubsonicExtensions: [String]
    
    init(canScan: Bool = false, canAdmin: Bool = false, canUpload: Bool = false, 
         canDownload: Bool = false, canStream: Bool = true, canGetLyrics: Bool = false,
         canGetCoverArt: Bool = true, supportsOpenSubsonic: Bool = false,
         openSubsonicExtensions: [String] = []) {
        self.canScan = canScan
        self.canAdmin = canAdmin
        self.canUpload = canUpload
        self.canDownload = canDownload
        self.canStream = canStream
        self.canGetLyrics = canGetLyrics
        self.canGetCoverArt = canGetCoverArt
        self.supportsOpenSubsonic = supportsOpenSubsonic
        self.openSubsonicExtensions = openSubsonicExtensions
    }
}

// MARK: - Listening Session Model

struct ListeningSession: Identifiable, Hashable, Codable {
    let id: String
    let user: String
    let playerId: String?
    let client: String?
    let trackId: String?
    let trackTitle: String?
    let trackArtist: String?
    let trackAlbum: String?
    let isPlaying: Bool
    let positionMs: Int?
    let startedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id = "playerId"
        case user = "username"
        case playerId
        case client
        case trackId
        case trackTitle
        case trackArtist
        case trackAlbum
        case isPlaying
        case positionMs
        case startedAt
    }
    
    init(id: String, user: String, playerId: String? = nil, client: String? = nil,
         trackId: String? = nil, trackTitle: String? = nil, trackArtist: String? = nil,
         trackAlbum: String? = nil, isPlaying: Bool, positionMs: Int? = nil, startedAt: Date? = nil) {
        self.id = id
        self.user = user
        self.playerId = playerId
        self.client = client
        self.trackId = trackId
        self.trackTitle = trackTitle
        self.trackArtist = trackArtist
        self.trackAlbum = trackAlbum
        self.isPlaying = isPlaying
        self.positionMs = positionMs
        self.startedAt = startedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.user = try container.decode(String.self, forKey: .user)
        self.playerId = try? container.decode(String.self, forKey: .playerId)
        self.client = try? container.decode(String.self, forKey: .client)
        self.trackId = try? container.decode(String.self, forKey: .trackId)
        self.trackTitle = try? container.decode(String.self, forKey: .trackTitle)
        self.trackArtist = try? container.decode(String.self, forKey: .trackArtist)
        self.trackAlbum = try? container.decode(String.self, forKey: .trackAlbum)
        
        // Handle isPlaying - can be Bool or String
        if let boolVal = try? container.decode(Bool.self, forKey: .isPlaying) {
            self.isPlaying = boolVal
        } else if let strVal = try? container.decode(String.self, forKey: .isPlaying) {
            self.isPlaying = strVal.lowercased() == "true"
        } else {
            self.isPlaying = false
        }
        
        self.positionMs = try? container.decode(Int.self, forKey: .positionMs)
        
        // Handle startedAt - can be Date or String
        if let dateVal = try? container.decode(Date.self, forKey: .startedAt) {
            self.startedAt = dateVal
        } else if let strVal = try? container.decode(String.self, forKey: .startedAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.startedAt = formatter.date(from: strVal)
        } else {
            self.startedAt = nil
        }
    }
}

struct ActiveSessionsResponse: Decodable {
    let session: [ListeningSession]?
    
    enum CodingKeys: String, CodingKey {
        case session
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decode([ListeningSession].self, forKey: .session) {
            self.session = list
        } else if let single = try? container.decode(ListeningSession.self, forKey: .session) {
            self.session = [single]
        } else {
            self.session = []
        }
    }
}
