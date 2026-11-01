import Foundation
import Observation
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case listenNow = "Listen Now"
    case search = "Search"
    case library = "Your Library"
    case albums = "Albums"
    case playlists = "Playlists"
    case liked = "Liked Songs"
    case downloads = "Downloads"
    case history = "Recently Played"
    case radio = "Internet Radio"
    case serverControl = "Server Control"
    case servers = "Servers"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .listenNow: "house.fill"
        case .search: "magnifyingglass"
        case .library: "books.vertical.fill"
        case .albums: "square.stack.fill"
        case .playlists: "music.note.list"
        case .liked: "heart.fill"
        case .downloads: "arrow.down.circle.fill"
        case .history: "clock.fill"
        case .radio: "dot.radiowaves.left.and.right"
        case .serverControl: "slider.horizontal.3"
        case .servers: "server.rack"
        }
    }
}

enum ServerStatus: Equatable {
    case disconnected
    case connecting
    case connected(serverVersion: String?, pingMs: Int)
    case failed(NavidromeError)
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    enum Kind { case success, error, info }
    let kind: Kind
    let message: String
}

@Observable @MainActor
final class AppState {
    var servers: [Server] = (try? JSONDecoder().decode([Server].self, from: UserDefaults.standard.data(forKey: "servers") ?? Data())) ?? []
    var activeID: UUID? = UserDefaults.standard.string(forKey: "active").flatMap(UUID.init)
    var page: Page = .listenNow
    var showLyrics = false
    var showQueue = false
    var ready = false
    var status = "Starting"
    
    // Server & Connection State
    var serverStatus: ServerStatus = .disconnected
    var activeServerError: NavidromeError?
    var activeServerDiagnostic: String?
    var showWelcome = false
    var showAddServerSheet = false
    var editingServer: Server? = nil
    var isRefreshing = false
    
    // Toast Notification
    var toast: Toast? = nil
    private var toastTask: Task<Void, Never>?
    
    // Server Control & Navidrome Admin State
    var currentUserInfo: SubsonicUser? = nil
    var scanStatus: ScanStatus? = nil
    var musicFolders: [MusicFolder] = []
    var serverUsers: [SubsonicUser] = []
    var radioStations: [InternetRadioStation] = []
    var serverExtensions: [OpenSubsonicExtension] = []
    var serverLicense: ServerLicense? = nil
    var genres: [Genre] = []
    var serverCapabilities: ServerCapabilities? = nil
    var activeSessions: [ListeningSession] = []
    var sessionsPollingTask: Task<Void, Never>? = nil
    var streamingBitrate: Int = UserDefaults.standard.integer(forKey: "streamingBitrate") {
        didSet {
            UserDefaults.standard.set(streamingBitrate, forKey: "streamingBitrate")
            player.maxBitRate = streamingBitrate
        }
    }
    
    var isScanning: Bool { scanStatus?.scanning == true }
    var isAdmin: Bool { currentUserInfo?.adminRole == true }
    private var scanPollingTask: Task<Void, Never>? = nil
    
    // Music Content
    var recommended: [Song] = []
    var rediscover: [Song] = []
    var results: [Song] = []
    var library: [Song] = []
    var liked: [Song] = []
    var albums: [Album] = []
    var playlists: [Playlist] = []
    var likedIDs: Set<String> = []
    var query = ""
    var error: String? {
        activeServerError?.localizedDescription
    }
    
    let player = Player()
    let downloads = Downloads()

    init() {
        player.downloads = downloads
    }

    var active: Server? {
        servers.first { $0.id == activeID } ?? servers.first
    }
    
    var client: NavidromeClient? {
        player.client
    }

    func showToast(_ message: String, kind: Toast.Kind = .info) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            self.toast = Toast(kind: kind, message: message)
        }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.25)) {
                    if self.toast?.message == message {
                        self.toast = nil
                    }
                }
            }
        }
    }

    func boot() async {
        status = "Loading servers"
        try? await Task.sleep(for: .milliseconds(250))
        
        if servers.isEmpty {
            ready = true
            showWelcome = true
            page = .servers
            status = "Ready"
            return
        }
        
        status = "Connecting"
        await refresh()
        status = "Ready"
        ready = true
    }

    /// Tests connection parameters without altering saved server list.
    func testServer(name: String, url: String, user: String, pass: String) async -> ConnectionResult {
        let cleanURL = NavidromeClient.sanitize(url: url)
        let tempID = UUID()
        let tempServer = Server(id: tempID, name: name.isEmpty ? (URL(string: cleanURL)?.host ?? "Navidrome") : name, url: cleanURL, user: user)
        Keychain.set(pass, for: tempID.uuidString)
        defer {
            Keychain.delete(tempID.uuidString)
        }
        let testClient = NavidromeClient(server: tempServer)
        return await testClient.testConnection()
    }

    /// Adds a server and optionally tests connection first.
    @discardableResult
    func add(server: Server, password: String, force: Bool = false) async -> ConnectionResult {
        var sanitized = server
        sanitized.url = NavidromeClient.sanitize(url: server.url)
        if sanitized.name.trimmingCharacters(in: .whitespaces).isEmpty {
            sanitized.name = URL(string: sanitized.url)?.host ?? "Navidrome"
        }
        
        // Save credentials
        Keychain.set(password, for: sanitized.id.uuidString)
        
        if !force {
            let client = NavidromeClient(server: sanitized)
            let result = await client.testConnection()
            if !result.success {
                // If test failed and not forced, don't persist yet; let caller handle error screen
                return result
            }
            sanitized.lastTested = Date()
            sanitized.lastPingMs = result.latencyMs
        }
        
        servers.append(sanitized)
        activeID = sanitized.id
        persist()
        showWelcome = false
        showToast("Connected to \"\(sanitized.name)\"", kind: .success)
        page = .listenNow
        await refresh()
        
        return ConnectionResult(
            success: true,
            serverVersion: nil,
            latencyMs: 0,
            error: nil,
            diagnosticDetails: "Server added successfully"
        )
    }

    /// Legacy compatibility
    func add(_ s: Server, password: String) async {
        await add(server: s, password: password, force: true)
    }

    @discardableResult
    func update(server: Server, password: String?) async -> ConnectionResult {
        var sanitized = server
        sanitized.url = NavidromeClient.sanitize(url: server.url)
        if sanitized.name.trimmingCharacters(in: .whitespaces).isEmpty {
            sanitized.name = URL(string: sanitized.url)?.host ?? "Navidrome"
        }
        
        if let pass = password, !pass.isEmpty {
            Keychain.set(pass, for: sanitized.id.uuidString)
        }
        
        let client = NavidromeClient(server: sanitized)
        let result = await client.testConnection()
        
        if result.success {
            sanitized.lastTested = Date()
            sanitized.lastPingMs = result.latencyMs
        }
        
        if let idx = servers.firstIndex(where: { $0.id == sanitized.id }) {
            servers[idx] = sanitized
        }
        persist()
        
        if activeID == sanitized.id {
            await refresh()
        }
        
        return result
    }

    func remove(_ s: Server) {
        servers.removeAll { $0.id == s.id }
        if activeID == s.id {
            activeID = servers.first?.id
        }
        persist()
        showToast("Removed server \"\(s.name)\"", kind: .info)
        
        if servers.isEmpty {
            showWelcome = true
            page = .servers
            serverStatus = .disconnected
            recommended = []
            library = []
            liked = []
            albums = []
            playlists = []
        } else {
            Task { await refresh() }
        }
    }

    func select(_ s: Server) {
        guard activeID != s.id else { return }
        activeID = s.id
        persist()
        showToast("Switching to \"\(s.name)\"…", kind: .info)
        Task { await refresh() }
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(servers), forKey: "servers")
        UserDefaults.standard.set(activeID?.uuidString, forKey: "active")
    }

    func refresh() async {
        guard let s = active else {
            serverStatus = .disconnected
            activeServerError = nil
            return
        }
        
        isRefreshing = true
        serverStatus = .connecting
        activeServerError = nil
        activeServerDiagnostic = nil
        
        let c = NavidromeClient(server: s)
        player.client = c
        
        let testResult = await c.testConnection()
        if !testResult.success, let err = testResult.error {
            serverStatus = .failed(err)
            activeServerError = err
            activeServerDiagnostic = testResult.diagnosticDetails
            isRefreshing = false
            return
        }
        
        serverStatus = .connected(serverVersion: testResult.serverVersion, pingMs: testResult.latencyMs)
        
        // Update server ping metadata
        if let idx = servers.firstIndex(where: { $0.id == s.id }) {
            servers[idx].lastTested = Date()
            servers[idx].lastPingMs = testResult.latencyMs
            persist()
        }
        
        do {
            async let r = c.random(40)
            async let l = c.library()
            async let f = c.starred()
            async let a = c.albums()
            async let p = c.playlists()
            
            let (rec, lib, star, alb, play) = try await (r, l, f, a, p)
            self.recommended = rec
            self.library = lib
            self.liked = star
            self.albums = alb
            self.playlists = play
            self.likedIDs = Set(star.map(\.id))
            self.rediscover = Array(lib.shuffled().prefix(24))
            
            if let seed = player.history.first ?? liked.first, let sim = try? await c.similar(to: seed.id), !sim.isEmpty {
                self.recommended = sim
            }
            
            // Load admin and server control telemetry
            await loadServerControlData()
        } catch let err as NavidromeError {
            serverStatus = .failed(err)
            activeServerError = err
            activeServerDiagnostic = "\(err.localizedDescription)\n\(err.recoverySuggestion)"
        } catch {
            let navErr = NavidromeError.unreachable(error.localizedDescription)
            serverStatus = .failed(navErr)
            activeServerError = navErr
        }
        
        isRefreshing = false
    }

    // MARK: - Server Control & Admin Actions
    
    func startLibraryScan(fullScan: Bool = false) async {
        guard let c = client else { return }
        showToast(fullScan ? "Starting full library rescan…" : "Starting quick scan…", kind: .info)
        do {
            let status = try await c.startScan(fullScan: fullScan)
            self.scanStatus = status
            pollScanStatus()
        } catch {
            showToast("Scan failed: \(error.localizedDescription)", kind: .error)
        }
    }
    
    func pollScanStatus() {
        scanPollingTask?.cancel()
        scanPollingTask = Task {
            while !Task.isCancelled {
                guard let c = self.client else { break }
                do {
                    let st = try await c.getScanStatus()
                    self.scanStatus = st
                    if !st.scanning {
                        self.showToast("Library scan complete! (\(st.count ?? 0) files indexed)", kind: .success)
                        await self.refresh()
                        break
                    }
                } catch {
                    break
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    
    private func pollActiveSessions() {
        sessionsPollingTask?.cancel()
        sessionsPollingTask = Task {
            while !Task.isCancelled {
                guard let c = self.client else { break }
                do {
                    let sessions = try await c.getActiveSessions()
                    self.activeSessions = sessions
                } catch {
                    break
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
    
    func loadServerControlData() async {
        guard let c = client, let s = active else { return }
        
        // Scan status
        if let st = try? await c.getScanStatus() {
            self.scanStatus = st
            if st.scanning && (scanPollingTask == nil || scanPollingTask?.isCancelled == true) {
                pollScanStatus()
            }
        }
        
        // Music folders configured on server
        if let folders = try? await c.getMusicFolders() {
            self.musicFolders = folders
        }
        
        // Current user details & permissions
        if let user = try? await c.getUser(s.user) {
            self.currentUserInfo = user
        }
        
        // Server users list (if user has admin role or to detect admin)
        if let users = try? await c.getUsers(), !users.isEmpty {
            self.serverUsers = users
            if self.currentUserInfo == nil {
                self.currentUserInfo = users.first { $0.username.lowercased() == s.user.lowercased() }
            }
        }
        
        // Radio stations
        if let radios = try? await c.getInternetRadioStations() {
            self.radioStations = radios
        }
        
        // OpenSubsonic extensions, server license & genres
        self.serverExtensions = (try? await c.getOpenSubsonicExtensions()) ?? []
        self.serverLicense = try? await c.getLicense()
        self.genres = (try? await c.getGenres()) ?? []
        
        // Server capabilities
        self.serverCapabilities = try? await c.getCapabilities()
        
        // Active sessions
        self.activeSessions = (try? await c.getActiveSessions()) ?? []
        if !activeSessions.isEmpty {
            pollActiveSessions()
        }
    }
    
    @discardableResult
    func createUser(
        username: String,
        password: String,
        email: String?,
        ldap: Bool = false,
        roles: [String: Bool] = [:]
    ) async -> Bool {
        guard let c = client else { return false }
        do {
            try await c.createUser(username: username, password: password, email: email, ldap: ldap, roles: roles)
            showToast("Created user \"\(username)\"", kind: .success)
            serverUsers = (try? await c.getUsers()) ?? serverUsers
            return true
        } catch {
            showToast("Failed to create user: \(error.localizedDescription)", kind: .error)
            return false
        }
    }
    
    @discardableResult
    func updateUser(
        username: String,
        password: String? = nil,
        email: String? = nil,
        roles: [String: Bool] = [:],
        maxBitRate: Int? = nil
    ) async -> Bool {
        guard let c = client else { return false }
        do {
            try await c.updateUser(username: username, password: password, email: email, roles: roles, maxBitRate: maxBitRate)
            showToast("Updated user \"\(username)\"", kind: .success)
            serverUsers = (try? await c.getUsers()) ?? serverUsers
            if username.lowercased() == active?.user.lowercased() {
                currentUserInfo = try? await c.getUser(username)
            }
            return true
        } catch {
            showToast("Failed to update user: \(error.localizedDescription)", kind: .error)
            return false
        }
    }
    
    @discardableResult
    func deleteUser(_ username: String) async -> Bool {
        guard let c = client else { return false }
        do {
            try await c.deleteUser(username)
            serverUsers.removeAll { $0.username == username }
            showToast("Deleted user \"\(username)\"", kind: .info)
            return true
        } catch {
            showToast("Failed to delete user: \(error.localizedDescription)", kind: .error)
            return false
        }
    }
    
    @discardableResult
    func changePassword(username: String, password: String) async -> Bool {
        guard let c = client else { return false }
        do {
            try await c.changePassword(username: username, password: password)
            showToast("Password updated for \(username)", kind: .success)
            return true
        } catch {
            showToast("Failed to change password: \(error.localizedDescription)", kind: .error)
            return false
        }
    }
    
    @discardableResult
    func createRadioStation(name: String, streamUrl: String, homepageUrl: String?) async -> Bool {
        guard let c = client else { return false }
        do {
            try await c.createInternetRadioStation(name: name, streamUrl: streamUrl, homepageUrl: homepageUrl)
            showToast("Added radio station \"\(name)\"", kind: .success)
            radioStations = (try? await c.getInternetRadioStations()) ?? radioStations
            return true
        } catch {
            showToast("Failed to add radio station: \(error.localizedDescription)", kind: .error)
            return false
        }
    }
    
    @discardableResult
    func updateRadioStation(id: String, name: String, streamUrl: String, homepageUrl: String?) async -> Bool {
        guard let c = client else { return false }
        do {
            try await c.updateInternetRadioStation(id: id, name: name, streamUrl: streamUrl, homepageUrl: homepageUrl)
            showToast("Updated radio station \"\(name)\"", kind: .success)
            radioStations = (try? await c.getInternetRadioStations()) ?? radioStations
            return true
        } catch {
            showToast("Failed to update radio station: \(error.localizedDescription)", kind: .error)
            return false
        }
    }
    
    @discardableResult
    func deleteRadioStation(_ id: String) async -> Bool {
        guard let c = client else { return false }
        do {
            try await c.deleteInternetRadioStation(id)
            radioStations.removeAll { $0.id == id }
            showToast("Deleted radio station", kind: .info)
            return true
        } catch {
            showToast("Failed to delete radio station: \(error.localizedDescription)", kind: .error)
            return false
        }
    }
    
    func playRadio(_ station: InternetRadioStation) {
        player.playRadio(station)
        showToast("Playing \"\(station.name)\"", kind: .info)
    }

    func runSearch() async {
        guard let c = client, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        results = (try? await c.search(query)) ?? []
    }

    func toggleLike(_ s: Song) async {
        let on = !likedIDs.contains(s.id)
        if on {
            likedIDs.insert(s.id)
            liked.insert(s, at: 0)
            showToast("Added to Liked Songs", kind: .success)
        } else {
            likedIDs.remove(s.id)
            liked.removeAll { $0.id == s.id }
            showToast("Removed from Liked Songs", kind: .info)
        }
        try? await client?.setStar(s.id, on)
    }

    func createPlaylist(_ name: String, with s: Song? = nil) async {
        do {
            try await client?.createPlaylist(name, songs: s.map { [$0.id] } ?? [])
            playlists = (try? await client?.playlists()) ?? playlists
            showToast("Created playlist \"\(name)\"", kind: .success)
        } catch {
            showToast("Could not create playlist: \(error.localizedDescription)", kind: .error)
        }
    }

    func add(_ s: Song, to p: Playlist) async {
        do {
            try await client?.addToPlaylist(p.id, song: s.id)
            showToast("Added to \"\(p.name)\"", kind: .success)
        } catch {
            showToast("Failed to add to playlist", kind: .error)
        }
    }

    func deletePlaylist(_ p: Playlist) async {
        do {
            try await client?.deletePlaylist(p.id)
            playlists.removeAll { $0.id == p.id }
            showToast("Deleted playlist \"\(p.name)\"", kind: .info)
        } catch {
            showToast("Failed to delete playlist", kind: .error)
        }
    }

    func download(_ songs: [Song]) {
        guard let c = client, !songs.isEmpty else { return }
        showToast("Starting download of \(songs.count) song\(songs.count == 1 ? "" : "s")…", kind: .info)
        Task {
            await downloads.downloadAll(songs, client: c)
            showToast("Download complete!", kind: .success)
        }
    }
}
