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
    }
    let body: Body
    enum CodingKeys: String, CodingKey { case body = "subsonic-response" }
}
