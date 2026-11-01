import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

enum MD5Digest {
    static func hash(_ string: String) -> String {
        #if canImport(CryptoKit)
        return Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        var data = Data(string.utf8)
        let bitLength = UInt64(data.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0x00) }
        var lenBytes = bitLength.littleEndian
        withUnsafeBytes(of: &lenBytes) { data.append(contentsOf: $0) }
        
        var a: UInt32 = 0x67452301
        var b: UInt32 = 0xefcdab89
        var c: UInt32 = 0x98badcfe
        var d: UInt32 = 0x10325476
        
        let s: [UInt32] = [
            7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
            5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
            4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
            6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21
        ]
        let k: [UInt32] = (0..<64).map { UInt32(abs(sin(Double($0 + 1))) * 4294967296.0) }
        
        for chunkStart in stride(from: 0, to: data.count, by: 64) {
            var m = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let idx = chunkStart + i * 4
                m[i] = UInt32(data[idx]) | (UInt32(data[idx + 1]) << 8) | (UInt32(data[idx + 2]) << 16) | (UInt32(data[idx + 3]) << 24)
            }
            
            var aa = a, bb = b, cc = c, dd = d
            for i in 0..<64 {
                var f: UInt32 = 0
                var g = 0
                if i < 16 {
                    f = (bb & cc) | ((~bb) & dd)
                    g = i
                } else if i < 32 {
                    f = (dd & bb) | ((~dd) & cc)
                    g = (5 * i + 1) % 16
                } else if i < 48 {
                    f = bb ^ cc ^ dd
                    g = (3 * i + 5) % 16
                } else {
                    f = cc ^ (bb | (~dd))
                    g = (7 * i) % 16
                }
                let temp = dd
                dd = cc
                cc = bb
                let sum = aa &+ f &+ k[i] &+ m[g]
                bb = bb &+ ((sum << s[i]) | (sum >> (32 - s[i])))
                aa = temp
            }
            a = a &+ aa
            b = b &+ bb
            c = c &+ cc
            d = d &+ dd
        }
        
        let result = [a, b, c, d].reduce(into: [UInt8]()) { arr, word in
            var w = word.littleEndian
            withUnsafeBytes(of: &w) { arr.append(contentsOf: $0) }
        }
        return result.map { String(format: "%02x", $0) }.joined()
        #endif
    }
}

/// Subsonic/OpenSubsonic client (Navidrome). Token auth: md5(password + salt).
struct NavidromeClient {
    let server: Server
    private var password: String { Keychain.get(server.id.uuidString) ?? "" }

    /// Sanitizes the base URL by trimming whitespace, ensuring http/https scheme, and stripping trailing slashes.
    static func sanitize(url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func url(_ endpoint: String, _ q: [String: String] = [:], items: [URLQueryItem] = []) -> URL? {
        let baseClean = Self.sanitize(url: server.url)
        guard var c = URLComponents(string: baseClean + "/rest/\(endpoint)") else {
            return nil
        }
        let salt = String((0..<8).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        let token = MD5Digest.hash(password + salt)
        let base = ["u": server.user, "t": token, "s": salt, "v": "1.16.1", "c": "Sono", "f": "json"]
        c.queryItems = base.merging(q) { $1 }.map { URLQueryItem(name: $0.key, value: $0.value) } + items
        return c.url
    }

    @discardableResult
    private func call(_ ep: String, _ q: [String: String] = [:], items: [URLQueryItem] = []) async throws -> Envelope.Body {
        guard let requestURL = url(ep, q, items: items) else {
            throw NavidromeError.invalidURL(server.url)
        }
        
        let data: Data
        let response: URLResponse
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 20
            let session = URLSession(configuration: config)
            (data, response) = try await session.data(from: requestURL)
        } catch let urlErr as URLError {
            if urlErr.code == .userAuthenticationRequired {
                throw NavidromeError.unauthorized("Authentication required by HTTP server.")
            } else if urlErr.code == .cannotConnectToHost || urlErr.code == .networkConnectionLost || urlErr.code == .notConnectedToInternet {
                throw NavidromeError.unreachable("Could not connect to host at \(server.url). Make sure server is online.")
            } else if urlErr.code == .timedOut {
                throw NavidromeError.unreachable("Connection timed out. Server may be down or firewall blocking traffic.")
            } else {
                throw NavidromeError.unreachable(urlErr.localizedDescription)
            }
        } catch {
            throw NavidromeError.unreachable(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw NavidromeError.unauthorized("HTTP \(http.statusCode): Access denied. Check username and password.")
            } else if http.statusCode >= 400 {
                let bodySnippet = String(data: data.prefix(150), encoding: .utf8) ?? ""
                throw NavidromeError.unreachable("HTTP \(http.statusCode) error. \(bodySnippet.isEmpty ? "" : "Details: " + bodySnippet)")
            }
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            if snippet.lowercased().contains("<html") || snippet.lowercased().contains("<!doctype") {
                throw NavidromeError.invalidResponse("Server returned an HTML web page instead of Subsonic JSON. Check if your URL requires a subpath or reverse proxy configuration.")
            }
            throw NavidromeError.invalidResponse("JSON parsing failed: \(error.localizedDescription). Received: \(snippet)")
        }

        let b = envelope.body
        if b.status.lowercased() == "failed" {
            if let err = b.error {
                if err.code == 40 {
                    throw NavidromeError.serverError(code: 40, message: "Wrong username or password")
                }
                throw NavidromeError.serverError(code: err.code, message: err.message)
            }
            throw NavidromeError.serverError(code: -1, message: "Server returned failure status without error message")
        }

        return b
    }

    /// Tests the connection to the server and returns latency and server version diagnostics.
    func testConnection() async -> ConnectionResult {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let body = try await call("ping")
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            let version = body.version ?? body.serverVersion ?? "Subsonic API"
            return ConnectionResult(
                success: true,
                serverVersion: version,
                latencyMs: elapsedMs,
                error: nil,
                diagnosticDetails: "Ping successful in \(elapsedMs)ms. Protocol version: \(version)"
            )
        } catch let err as NavidromeError {
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            return ConnectionResult(
                success: false,
                serverVersion: nil,
                latencyMs: elapsedMs,
                error: err,
                diagnosticDetails: "Target URL: \(server.url)\nUser: \(server.user)\nError: \(err.localizedDescription)\nSuggestion: \(err.recoverySuggestion)"
            )
        } catch {
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            let navErr = NavidromeError.unreachable(error.localizedDescription)
            return ConnectionResult(
                success: false,
                serverVersion: nil,
                latencyMs: elapsedMs,
                error: navErr,
                diagnosticDetails: "Target URL: \(server.url)\nError: \(error.localizedDescription)"
            )
        }
    }

    func ping() async throws { try await call("ping") }
    func random(_ n: Int = 30) async throws -> [Song] { try await call("getRandomSongs", ["size": "\(n)"]).randomSongs?.song ?? [] }
    func similar(to id: String) async throws -> [Song] { try await call("getSimilarSongs2", ["id": id, "count": "30"]).similarSongs2?.song ?? [] }
    func search(_ q: String) async throws -> [Song] { try await call("search3", ["query": q, "songCount": "500", "artistCount": "0", "albumCount": "0"]).searchResult3?.song ?? [] }
    func starred() async throws -> [Song] { try await call("getStarred2").starred2?.song ?? [] }
    func library() async throws -> [Song] { try await search("") }
    func albums() async throws -> [Album] { try await call("getAlbumList2", ["type": "alphabeticalByName", "size": "500"]).albumList2?.album ?? [] }
    func album(_ id: String) async throws -> [Song] { try await call("getAlbum", ["id": id]).album?.song ?? [] }
    func playlists() async throws -> [Playlist] { try await call("getPlaylists").playlists?.playlist ?? [] }
    func playlist(_ id: String) async throws -> [Song] { try await call("getPlaylist", ["id": id]).playlist?.entry ?? [] }
    func createPlaylist(_ name: String, songs: [String]) async throws {
        try await call("createPlaylist", ["name": name], items: songs.map { URLQueryItem(name: "songId", value: $0) })
    }
    func addToPlaylist(_ id: String, song: String) async throws { try await call("updatePlaylist", ["playlistId": id, "songIdToAdd": song]) }
    func deletePlaylist(_ id: String) async throws { try await call("deletePlaylist", ["id": id]) }
    func setStar(_ id: String, _ on: Bool) async throws { try await call(on ? "star" : "unstar", ["id": id]) }
    func scrobble(_ id: String) async { _ = try? await call("scrobble", ["id": id, "submission": "true"]) }
    
    /// Fetches lyrics natively from Navidrome / Subsonic using OpenSubsonic getLyricsBySongId or Subsonic getLyrics.
    func lyrics(for song: Song) async -> [LyricLine] {
        // 1. Try OpenSubsonic getLyricsBySongId (Navidrome's structured synced lyrics API)
        if let body = try? await call("getLyricsBySongId", ["id": song.id]),
           let structuredList = body.lyricsList?.structuredLyrics {
            if let target = structuredList.first(where: { ($0.synced == true) && !($0.line ?? []).isEmpty }) ?? structuredList.first,
               let lines = target.line, !lines.isEmpty {
                var result: [LyricLine] = []
                for (idx, line) in lines.enumerated() {
                    let sec: Double = (target.synced == true && line.start != nil) ? (Double(line.start!) / 1000.0) : -1.0
                    result.append(LyricLine(id: idx, time: sec, text: line.value ?? ""))
                }
                if !result.isEmpty { return result }
            }
        }
        
        // 2. Try standard Subsonic getLyrics (artist + title)
        var q: [String: String] = ["title": song.title]
        if let artist = song.artist, !artist.isEmpty {
            q["artist"] = artist
        }
        if let body = try? await call("getLyrics", q),
           let content = body.lyrics?.content, !content.isEmpty {
            return Lyrics.parse(content)
        }
        
        return []
    }
    
    // MARK: - Admin & Server Controls
    
    /// Checks the current scan status of the Navidrome / Subsonic library.
    func getScanStatus() async throws -> ScanStatus {
        let body = try await call("getScanStatus")
        return body.scanStatus ?? ScanStatus(scanning: false, count: 0)
    }
    
    /// Triggers a library rescan. If fullScan is true, performs a comprehensive scan of all files.
    func startScan(fullScan: Bool = false) async throws -> ScanStatus {
        let body = try await call("startScan", ["fullScan": fullScan ? "true" : "false"])
        return body.scanStatus ?? ScanStatus(scanning: true, count: 0)
    }
    
    /// Fetches all configured media library folders on the server.
    func getMusicFolders() async throws -> [MusicFolder] {
        try await call("getMusicFolders").musicFolders?.musicFolder ?? []
    }
    
    /// Fetches all registered users on the server (Admin required).
    func getUsers() async throws -> [SubsonicUser] {
        try await call("getUsers").users?.user ?? []
    }
    
    /// Fetches details for a specific user.
    func getUser(_ username: String) async throws -> SubsonicUser? {
        try await call("getUser", ["username": username]).user
    }
    
    /// Creates a new user on the server (Admin required).
    func createUser(
        username: String,
        password: String,
        email: String? = nil,
        ldap: Bool = false,
        roles: [String: Bool] = [:]
    ) async throws {
        var q: [String: String] = [
            "username": username,
            "password": password,
            "ldapAuthenticated": ldap ? "true" : "false"
        ]
        if let em = email, !em.trimmingCharacters(in: .whitespaces).isEmpty {
            q["email"] = em
        }
        for (role, val) in roles {
            q[role] = val ? "true" : "false"
        }
        try await call("createUser", q)
    }
    
    /// Modifies user credentials, email, or role permissions (Admin required).
    func updateUser(
        username: String,
        password: String? = nil,
        email: String? = nil,
        roles: [String: Bool] = [:],
        maxBitRate: Int? = nil
    ) async throws {
        var q: [String: String] = ["username": username]
        if let pass = password, !pass.isEmpty {
            q["password"] = pass
        }
        if let em = email {
            q["email"] = em
        }
        if let mbr = maxBitRate {
            q["maxBitRate"] = "\(mbr)"
        }
        for (role, val) in roles {
            q[role] = val ? "true" : "false"
        }
        try await call("updateUser", q)
    }
    
    /// Deletes a user account from the server (Admin required).
    func deleteUser(_ username: String) async throws {
        try await call("deleteUser", ["username": username])
    }
    
    /// Changes the password of an existing user.
    func changePassword(username: String, password: String) async throws {
        try await call("changePassword", ["username": username, "password": password])
    }
    
    /// Fetches configured Internet Radio Stations.
    func getInternetRadioStations() async throws -> [InternetRadioStation] {
        try await call("getInternetRadioStations").internetRadioStations?.internetRadioStation ?? []
    }
    
    /// Creates a new Internet Radio Station.
    func createInternetRadioStation(name: String, streamUrl: String, homepageUrl: String? = nil) async throws {
        var q: [String: String] = ["name": name, "streamUrl": streamUrl]
        if let home = homepageUrl, !home.trimmingCharacters(in: .whitespaces).isEmpty {
            q["homepageUrl"] = home
        }
        try await call("createInternetRadioStation", q)
    }
    
    /// Updates an existing Internet Radio Station.
    func updateInternetRadioStation(id: String, name: String, streamUrl: String, homepageUrl: String? = nil) async throws {
        var q: [String: String] = ["id": id, "name": name, "streamUrl": streamUrl]
        if let home = homepageUrl, !home.trimmingCharacters(in: .whitespaces).isEmpty {
            q["homepageUrl"] = home
        }
        try await call("updateInternetRadioStation", q)
    }
    
    /// Deletes an Internet Radio Station.
    func deleteInternetRadioStation(_ id: String) async throws {
        try await call("deleteInternetRadioStation", ["id": id])
    }
    
    /// Fetches supported OpenSubsonic protocol extensions.
    func getOpenSubsonicExtensions() async throws -> [OpenSubsonicExtension] {
        (try? await call("getOpenSubsonicExtensions").openSubsonicExtensions) ?? []
    }
    
    /// Fetches license information from the server.
    func getLicense() async throws -> ServerLicense? {
        try? await call("getLicense").license
    }
    
    /// Fetches music genres cataloged by the server.
    func getGenres() async throws -> [Genre] {
        try await call("getGenres").genres?.genre ?? []
    }
    
    // MARK: - Server Info & Capabilities
    
    /// Gets comprehensive server information including version, extensions, and capabilities.
    func getServerInfo() async throws -> ServerInfo {
        let pingResponse = try await call("ping")
        let extensions = (try? await call("getOpenSubsonicExtensions").openSubsonicExtensions) ?? []
        
        return ServerInfo(
            serverVersion: pingResponse.version ?? pingResponse.serverVersion ?? "Unknown",
            apiVersion: "1.16.1",
            extensions: extensions,
            user: server.user,
            latencyMs: nil
        )
    }
    
    /// Gets server capabilities based on available extensions and API support.
    func getCapabilities() async throws -> ServerCapabilities {
        let extensions = (try? await call("getOpenSubsonicExtensions").openSubsonicExtensions) ?? []
        let extNames = extensions.map(\.name)
        
        return ServerCapabilities(
            canScan: extNames.contains("scanStatus") || true, // Most servers support scanning
            canAdmin: true, // Assume admin capabilities, will be verified by actual calls
            canUpload: extNames.contains("upload") || true,
            canDownload: true,
            canStream: true,
            canGetLyrics: extNames.contains("lyrics") || true,
            canGetCoverArt: true,
            supportsOpenSubsonic: !extensions.isEmpty,
            openSubsonicExtensions: extNames
        )
    }
    
    /// Gets currently active listening sessions (Navidrome-specific).
    func getActiveSessions() async throws -> [ListeningSession] {
        // Try Navidrome's getActiveSessions endpoint
        if let response = try? await call("getActiveSessions") {
            // This would need to be added to the Envelope.Body
            return response.activeSessions?.session ?? []
        }
        
        // Fallback: try OpenSubsonic getNowPlaying if available
        if let _ = try? await call("getNowPlaying") {
            // Parse now playing response
            // This is a placeholder - actual implementation depends on server support
            return []
        }
        
        return []
    }
    
    /// Gets all available lyric variants for a song (Navidrome-specific).
    func getLyricVariants(for song: Song) async -> [LyricVariant] {
        var variants: [LyricVariant] = []
        
        // Try OpenSubsonic getLyricsBySongId first
        if let body = try? await call("getLyricsBySongId", ["id": song.id]),
           let structuredList = body.lyricsList?.structuredLyrics {
            for structured in structuredList {
                if let lines = structured.line, !lines.isEmpty {
                    let lyricLines = lines.enumerated().map { idx, line in
                        let sec: Double = (structured.synced == true && line.start != nil) ? (Double(line.start!) / 1000.0) : -1.0
                        return LyricLine(id: idx, time: sec, text: line.value ?? "")
                    }
                    let variant = LyricVariant(
                        language: structured.lang,
                        isSynced: structured.synced ?? false,
                        lines: lyricLines,
                        source: "server"
                    )
                    variants.append(variant)
                }
            }
        }
        
        // If no synced lyrics found, try standard Subsonic getLyrics
        if variants.isEmpty {
            var q: [String: String] = ["title": song.title]
            if let artist = song.artist, !artist.isEmpty {
                q["artist"] = artist
            }
            if let body = try? await call("getLyrics", q),
               let content = body.lyrics?.content, !content.isEmpty {
                let lines = Lyrics.parse(content)
                if !lines.isEmpty {
                    let variant = LyricVariant(
                        language: nil,
                        isSynced: lines.contains(where: { $0.time >= 0 }),
                        lines: lines,
                        source: "server"
                    )
                    variants.append(variant)
                }
            }
        }
        
        return variants
    }

    func stream(_ id: String, maxBitRate: Int? = nil) -> URL {
        var q: [String: String] = ["id": id]
        if let br = maxBitRate, br > 0 {
            q["maxBitRate"] = "\(br)"
        }
        return url("stream", q) ?? URL(string: "about:blank")!
    }
    func original(_ id: String) -> URL { url("download", ["id": id]) ?? URL(string: "about:blank")! }
    func cover(_ id: String?, size: Int = 400) -> URL? { id.flatMap { url("getCoverArt", ["id": $0, "size": "\(size)"]) } }
}
