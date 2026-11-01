import SwiftUI

// MARK: - Server Admin & Controls Page

struct ServerAdminPage: View {
    @Environment(AppState.self) var state
    
    enum AdminTab: String, CaseIterable, Identifiable {
        case rescan = "Library & Scan"
        case users = "Users & Access"
        case radio = "Internet Radio"
        case system = "System & Telemetry"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .rescan: "arrow.clockwise.icloud.fill"
            case .users: "person.3.fill"
            case .radio: "dot.radiowaves.left.and.right"
            case .system: "server.rack"
            }
        }
    }
    
    @State private var selectedTab: AdminTab = .rescan
    @State private var showCreateUserSheet = false
    @State private var editingUser: SubsonicUser? = nil
    @State private var passwordUser: SubsonicUser? = nil
    @State private var showAddRadioSheet = false
    @State private var editingRadio: InternetRadioStation? = nil
    @State private var isPingTesting = false
    @State private var pingLatency: Int? = nil
    @State private var showFolderBrowser = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text("Server Control")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            
                            if state.isAdmin {
                                Text("ADMIN")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Theme.purple)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Theme.purple.opacity(0.18), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.purple.opacity(0.4), lineWidth: 1))
                            }
                        }
                        
                        if let s = state.active {
                            Text("Navidrome control plane for \(s.name) (\(s.url))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Quick Rescan Action Button in Header
                    Button {
                        Task { await state.startLibraryScan(fullScan: false) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .rotationEffect(.degrees(state.isScanning ? 360 : 0))
                                .animation(state.isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: state.isScanning)
                            Text(state.isScanning ? "Scanning…" : "Quick Rescan")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(state.isScanning ? Theme.warningOrange : Theme.purple)
                }
                
                // Active Scan Live Radar Banner (if scanning)
                if state.isScanning {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(Theme.purple.opacity(0.3), lineWidth: 2)
                                .frame(width: 32, height: 32)
                            ProgressView()
                                .controlSize(.small)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Media Library Scan in Progress")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Navidrome is indexing files and metadata. Processed \(state.scanStatus?.count ?? 0) items so far.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.purple.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.purple.opacity(0.3), lineWidth: 1))
                    )
                }
                
                // Segmented Tab Picker
                HStack(spacing: 8) {
                    ForEach(AdminTab.allCases) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTab == tab ? Color.white.opacity(0.12) : Color.white.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selectedTab == tab ? Theme.purple.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                            )
                            .foregroundStyle(selectedTab == tab ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Tab Content
                Group {
                    switch selectedTab {
                    case .rescan:
                        RescanAndFoldersView()
                    case .users:
                        UsersAndAccessView(
                            showCreateUserSheet: $showCreateUserSheet,
                            editingUser: $editingUser,
                            passwordUser: $passwordUser
                        )
                    case .radio:
                        RadioStationsAdminView(
                            showAddRadioSheet: $showAddRadioSheet,
                            editingRadio: $editingRadio
                        )
                    case .system:
                        SystemAndTelemetryView(
                            isPingTesting: $isPingTesting,
                            pingLatency: $pingLatency
                        )
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .sheet(isPresented: $showCreateUserSheet) {
            CreateUserSheet()
        }
        .sheet(item: $editingUser) { user in
            EditUserSheet(user: user)
        }
        .sheet(item: $passwordUser) { user in
            ChangePasswordSheet(username: user.username)
        }
        .sheet(isPresented: $showAddRadioSheet) {
            RadioStationSheet(stationToEdit: nil)
        }
        .sheet(item: $editingRadio) { station in
            RadioStationSheet(stationToEdit: station)
        }
        .sheet(isPresented: $showFolderBrowser) {
            FolderBrowserView(isPresented: $showFolderBrowser)
        }
        .task {
            await state.loadServerControlData()
        }
    }
}

// MARK: - Tab 1: Rescan & Folders View

struct RescanAndFoldersView: View {
    @Environment(AppState.self) var state
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Rescan Trigger Cards
            VStack(alignment: .leading, spacing: 12) {
                Text("MEDIA LIBRARY RESCAN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 16) {
                    // Quick Rescan Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                                .foregroundStyle(Theme.purple)
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quick Rescan")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Checks configured folders for newly added, modified, or removed files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        Button {
                            Task { await state.startLibraryScan(fullScan: false) }
                        } label: {
                            Text("Start Quick Scan")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.purple)
                        .disabled(state.isScanning)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    
                    // Full Deep Scan Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.violet)
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Full Library Rescan")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Deeply inspects every audio file, re-reading all metadata, embedded tags, and artwork.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        Button {
                            Task { await state.startLibraryScan(fullScan: true) }
                        } label: {
                            Text("Start Full Scan")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.isScanning)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
            }
            
            // Configured Media Folders List
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CONFIGURED MEDIA DIRECTORIES")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    
                    if state.isAdmin {
                        Button {
                            showFolderBrowser = true
                        } label: {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                Text("\(state.musicFolders.count) folder\(state.musicFolders.count == 1 ? "" : "s") configured")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                if state.musicFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("No Music Folders Configured")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Add folders from your server to start indexing music.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(spacing: 8) {
                        ForEach(state.musicFolders) { folder in
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .font(.title3)
                                    .foregroundStyle(Theme.purple)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.name)
                                        .font(.system(size: 13, weight: .semibold, design: .default))
                                        .foregroundStyle(.white)
                                    Text("ID: \(folder.id)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if state.isAdmin {
                                    Menu {
                                        Button {
                                            Task { await scanSpecificFolder(folder.id) }
                                        } label: {
                                            Label("Scan This Folder", systemImage: "arrow.clockwise")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            Task { await removeFolder(folder.id) }
                                        } label: {
                                            Label("Remove Folder", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                }
                                
                                Text("Online")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.successGreen)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.successGreen.opacity(0.15), in: Capsule())
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                        }
                    }
                }
            }
            
            // Server Library Metrics Grid
            VStack(alignment: .leading, spacing: 12) {
                Text("LIBRARY METRICS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    MetricStatCard(title: "Songs", count: state.library.count, icon: "music.note")
                    MetricStatCard(title: "Albums", count: state.albums.count, icon: "square.stack.fill")
                    MetricStatCard(title: "Playlists", count: state.playlists.count, icon: "music.note.list")
                    MetricStatCard(title: "Genres", count: state.genres.count, icon: "guitars.fill")
                    MetricStatCard(title: "Liked Songs", count: state.liked.count, icon: "heart.fill")
                    MetricStatCard(title: "Offline", count: state.downloads.songs.count, icon: "arrow.down.circle.fill")
                }
            }
        }
    }
    
    private func scanSpecificFolder(_ id: String) async {
        guard let client = state.client else { return }
        do {
            try await client.scanMusicFolder(id: id)
            state.showToast("Started scanning folder", kind: .info)
        } catch {
            state.showToast("Failed to scan folder: \(error.localizedDescription)", kind: .error)
        }
    }
    
    private func removeFolder(_ id: String) async {
        guard let client = state.client else { return }
        do {
            try await client.removeMusicFolder(id: id)
            state.musicFolders.removeAll { $0.id == id }
            state.showToast("Removed folder from music library", kind: .info)
        } catch {
            state.showToast("Failed to remove folder: \(error.localizedDescription)", kind: .error)
        }
    }
}

struct MetricStatCard: View {
    let title: String
    let count: Int
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.purple)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Tab 2: Users & Access View

struct UsersAndAccessView: View {
    @Environment(AppState.self) var state
    @Binding var showCreateUserSheet: Bool
    @Binding var editingUser: SubsonicUser?
    @Binding var passwordUser: SubsonicUser?
    
    @State private var userToDelete: SubsonicUser? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Current User Permissions Card
            if let current = state.currentUserInfo {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.title3)
                            .foregroundStyle(Theme.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in as \(current.username)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            Text(current.email ?? "No email associated")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Change Password") {
                            passwordUser = current
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    // Badges for active user
                    HStack(spacing: 6) {
                        RoleBadge(label: "Admin", active: current.isAdmin, color: Theme.purple)
                        RoleBadge(label: "Stream", active: current.canStream, color: Theme.successGreen)
                        RoleBadge(label: "Download", active: current.canDownload, color: Theme.infoBlue)
                        RoleBadge(label: "Upload", active: current.canUpload, color: Theme.warningOrange)
                        RoleBadge(label: "Playlists", active: current.canManagePlaylists, color: Theme.violet)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
            
            // User Management (Admin Only)
            if state.isAdmin {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SERVER ACCOUNTS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("Manage users, permissions, and roles on this Navidrome instance.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            showCreateUserSheet = true
                        } label: {
                            Label("New User", systemImage: "person.badge.plus")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.purple)
                    }
                    
                    if state.serverUsers.isEmpty {
                        Text("No users retrieved or restricted by server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(state.serverUsers) { user in
                                UserCardView(
                                    user: user,
                                    onEdit: { editingUser = user },
                                    onChangePassword: { passwordUser = user },
                                    onDelete: { userToDelete = user }
                                )
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.title2)
                        .foregroundStyle(Theme.warningOrange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Admin Privileges Required")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        Text("To add, modify, or delete user accounts, sign in with a user who has the Administrator role.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            }
        }
        .confirmationDialog(
            "Delete User",
            isPresented: Binding(
                get: { userToDelete != nil },
                set: { if !$0 { userToDelete = nil } }
            ),
            presenting: userToDelete
        ) { user in
            Button("Delete \"\(user.username)\"", role: .destructive) {
                Task { await state.deleteUser(user.username) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { user in
            Text("Are you sure you want to delete user \"\(user.username)\"? This operation cannot be undone.")
        }
    }
}

struct UserCardView: View {
    let user: SubsonicUser
    let onEdit: () -> Void
    let onChangePassword: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(user.isAdmin ? Theme.purple.opacity(0.2) : Color.white.opacity(0.06))
                    .frame(width: 40, height: 40)
                Image(systemName: user.isAdmin ? "shield.fill" : "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(user.isAdmin ? Theme.purple : .secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(user.username)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    if user.isAdmin {
                        Text("ADMIN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.purple.opacity(0.18), in: Capsule())
                    }
                }
                
                if let email = user.email, !email.isEmpty {
                    Text(email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // Role pills
                HStack(spacing: 4) {
                    if user.canStream { RoleMiniBadge(label: "Stream") }
                    if user.canDownload { RoleMiniBadge(label: "Download") }
                    if user.canUpload { RoleMiniBadge(label: "Upload") }
                    if user.canManagePlaylists { RoleMiniBadge(label: "Playlists") }
                    if user.canShare { RoleMiniBadge(label: "Share") }
                }
                .padding(.top, 2)
            }
            
            Spacer()
            
            Menu {
                Button("Edit Roles & Email") { onEdit() }
                Button("Reset Password") { onChangePassword() }
                Divider()
                Button("Delete User", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}

struct RoleBadge: View {
    let label: String
    let active: Bool
    let color: Color
    
    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(active ? color : .secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(active ? color.opacity(0.15) : Color.white.opacity(0.04), in: Capsule())
            .overlay(Capsule().strokeBorder(active ? color.opacity(0.3) : Color.clear, lineWidth: 1))
    }
}

struct RoleMiniBadge: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Tab 3: Radio Stations Admin View

struct RadioStationsAdminView: View {
    @Environment(AppState.self) var state
    @Binding var showAddRadioSheet: Bool
    @Binding var editingRadio: InternetRadioStation?
    
    @State private var stationToDelete: InternetRadioStation? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INTERNET RADIO STREAMS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Broadcast streams registered on this Subsonic server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    showAddRadioSheet = true
                } label: {
                    Label("Add Station", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.purple)
            }
            
            if state.radioStations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .padding(.top, 20)
                    Text("No Internet Radio Stations")
                        .font(.headline)
                    Text("Add streaming radio stations like SomaFM, BBC, or custom web audio streams.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add Station") { showAddRadioSheet = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.purple)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.radioStations) { st in
                        HStack(spacing: 14) {
                            Button {
                                state.playRadio(st)
                            } label: {
                                Image(systemName: (state.player.currentRadio?.id == st.id && state.player.isPlaying) ? "pause.fill" : "play.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Theme.purple, in: Circle())
                            }
                            .buttonStyle(.plain)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(st.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(st.streamUrl)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Menu {
                                Button("Play Station") { state.playRadio(st) }
                                Button("Edit Station") { editingRadio = st }
                                Divider()
                                Button("Delete Station", role: .destructive) { stationToDelete = st }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Radio Station",
            isPresented: Binding(
                get: { stationToDelete != nil },
                set: { if !$0 { stationToDelete = nil } }
            ),
            presenting: stationToDelete
        ) { st in
            Button("Delete \"\(st.name)\"", role: .destructive) {
                Task { await state.deleteRadioStation(st.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { st in
            Text("Are you sure you want to delete \"\(st.name)\"?")
        }
    }
}

// MARK: - Tab 4: System & Telemetry View

struct SystemAndTelemetryView: View {
    @Environment(AppState.self) var state
    @Binding var isPingTesting: Bool
    @Binding var pingLatency: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Server Telemetry Card
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("SERVER TELEMETRY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        testLatency()
                    } label: {
                        HStack(spacing: 5) {
                            if isPingTesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "waveform.path")
                            }
                            Text("Test Latency")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                VStack(spacing: 10) {
                    TelemetryRow(label: "Server Name", value: state.active?.name ?? "Unknown")
                    TelemetryRow(label: "Endpoint Address", value: state.active?.url ?? "None")
                    TelemetryRow(label: "Signed In User", value: state.active?.user ?? "None")
                    if case .connected(let ver, let ping) = state.serverStatus {
                        TelemetryRow(label: "Server Version", value: ver ?? "Subsonic API 1.16.1")
                        TelemetryRow(label: "Round-trip Latency", value: "\(pingLatency ?? ping) ms")
                    }
                    if let lic = state.serverLicense {
                        TelemetryRow(label: "License Status", value: lic.valid == true ? "Valid (Licensed)" : "Unregistered")
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
            
            // Audio Streaming & Transcoding Limit
            VStack(alignment: .leading, spacing: 12) {
                Text("STREAMING BITRATE LIMIT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Streaming Quality", selection: Bindable(state).streamingBitrate) {
                        Text("Original (Bit-perfect / No limit)").tag(0)
                        Text("320 kbps (High Quality MP3/AAC)").tag(320)
                        Text("256 kbps (Standard)").tag(256)
                        Text("192 kbps (Mobile Saving)").tag(192)
                        Text("128 kbps (Low Bandwidth)").tag(128)
                    }
                    .pickerStyle(.menu)
                    
                    Text("Navidrome server-side transcoding adapts high-resolution audio on the fly if a maximum bitrate is set.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
            
            // OpenSubsonic Supported Extensions
            if !state.serverExtensions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("OPEN SUBSONIC EXTENSIONS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                        ForEach(state.serverExtensions) { ext in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.purple)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ext.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                    if let versions = ext.versions, !versions.isEmpty {
                                        Text("v\(versions.map(String.init).joined(separator: ", v"))")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                        }
                    }
                }
            }
        }
    }
    
    private func testLatency() {
        guard let s = state.active else { return }
        isPingTesting = true
        Task {
            let res = await state.testServer(name: s.name, url: s.url, user: s.user, pass: Keychain.get(s.id.uuidString) ?? "")
            pingLatency = res.latencyMs
            isPingTesting = false
        }
    }
}

struct TelemetryRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Sheets: Create User, Edit User, Change Password, Radio Station

struct CreateUserSheet: View {
    @Environment(AppState.self) var state
    @Environment(\.dismiss) var dismiss
    
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var adminRole = false
    @State private var downloadRole = true
    @State private var uploadRole = false
    @State private var playlistRole = true
    @State private var coverArtRole = false
    @State private var streamRole = true
    @State private var shareRole = false
    @State private var isSubmitting = false
    
    var isValid: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Create New User")
                .font(.title2.bold())
                .padding(.top, 24)
                .padding(.bottom, 16)
            
            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                TextField("Email (optional)", text: $email)
                    .textFieldStyle(.roundedBorder)
                
                Divider().padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Permissions & Roles")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    
                    Toggle("Administrator Privileges", isOn: $adminRole)
                    Toggle("Stream Audio", isOn: $streamRole)
                    Toggle("Download Audio Files", isOn: $downloadRole)
                    Toggle("Manage Playlists", isOn: $playlistRole)
                    Toggle("Upload Media", isOn: $uploadRole)
                    Toggle("Share Music Links", isOn: $shareRole)
                }
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            
            Spacer()
            
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    createUser()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Create User")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.purple)
                .disabled(!isValid || isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .frame(width: 420, height: 480)
    }
    
    private func createUser() {
        isSubmitting = true
        Task {
            let roles: [String: Bool] = [
                "adminRole": adminRole,
                "streamRole": streamRole,
                "downloadRole": downloadRole,
                "playlistRole": playlistRole,
                "uploadRole": uploadRole,
                "coverArtRole": coverArtRole,
                "shareRole": shareRole
            ]
            let ok = await state.createUser(
                username: username,
                password: password,
                email: email.isEmpty ? nil : email,
                ldap: false,
                roles: roles
            )
            isSubmitting = false
            if ok { dismiss() }
        }
    }
}

struct EditUserSheet: View {
    @Environment(AppState.self) var state
    @Environment(\.dismiss) var dismiss
    
    let user: SubsonicUser
    
    @State private var email = ""
    @State private var newPassword = ""
    @State private var adminRole = false
    @State private var downloadRole = true
    @State private var uploadRole = false
    @State private var playlistRole = true
    @State private var streamRole = true
    @State private var shareRole = false
    @State private var isSubmitting = false
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Edit User: \(user.username)")
                .font(.title2.bold())
                .padding(.top, 24)
                .padding(.bottom, 16)
            
            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                SecureField("New Password (leave blank to keep current)", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                
                Divider().padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Permissions & Roles")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    
                    Toggle("Administrator Privileges", isOn: $adminRole)
                    Toggle("Stream Audio", isOn: $streamRole)
                    Toggle("Download Audio Files", isOn: $downloadRole)
                    Toggle("Manage Playlists", isOn: $playlistRole)
                    Toggle("Upload Media", isOn: $uploadRole)
                    Toggle("Share Music Links", isOn: $shareRole)
                }
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            
            Spacer()
            
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    saveUser()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save Changes")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.purple)
                .disabled(isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .frame(width: 420, height: 480)
        .onAppear {
            email = user.email ?? ""
            adminRole = user.isAdmin
            downloadRole = user.canDownload
            uploadRole = user.canUpload
            playlistRole = user.canManagePlaylists
            streamRole = user.canStream
            shareRole = user.canShare
        }
    }
    
    private func saveUser() {
        isSubmitting = true
        Task {
            let roles: [String: Bool] = [
                "adminRole": adminRole,
                "streamRole": streamRole,
                "downloadRole": downloadRole,
                "playlistRole": playlistRole,
                "uploadRole": uploadRole,
                "shareRole": shareRole
            ]
            let ok = await state.updateUser(
                username: user.username,
                password: newPassword.isEmpty ? nil : newPassword,
                email: email,
                roles: roles
            )
            isSubmitting = false
            if ok { dismiss() }
        }
    }
}

struct ChangePasswordSheet: View {
    @Environment(AppState.self) var state
    @Environment(\.dismiss) var dismiss
    
    let username: String
    @State private var password = ""
    @State private var isSubmitting = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Reset Password for \(username)")
                .font(.headline)
                .padding(.top, 20)
            
            SecureField("New Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 24)
            
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Spacer()
                Button("Update") {
                    isSubmitting = true
                    Task {
                        _ = await state.changePassword(username: username, password: password)
                        isSubmitting = false
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.purple)
                .disabled(password.isEmpty || isSubmitting)
            }
            .padding(16)
        }
        .frame(width: 320, height: 160)
    }
}

struct RadioStationSheet: View {
    @Environment(AppState.self) var state
    @Environment(\.dismiss) var dismiss
    
    let stationToEdit: InternetRadioStation?
    @State private var name = ""
    @State private var streamUrl = ""
    @State private var homepageUrl = ""
    @State private var isSubmitting = false
    
    var isEditing: Bool { stationToEdit != nil }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        streamUrl.trimmingCharacters(in: .whitespaces).count >= 8
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text(isEditing ? "Edit Radio Station" : "Add Radio Station")
                .font(.title2.bold())
                .padding(.top, 24)
                .padding(.bottom, 16)
            
            VStack(spacing: 12) {
                TextField("Station Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Stream URL (e.g. https://.../stream.mp3)", text: $streamUrl)
                    .textFieldStyle(.roundedBorder)
                TextField("Homepage URL (optional)", text: $homepageUrl)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            
            Spacer()
            
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    save()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(isEditing ? "Save" : "Add")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.purple)
                .disabled(!isValid || isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .frame(width: 400, height: 260)
        .onAppear {
            if let st = stationToEdit {
                name = st.name
                streamUrl = st.streamUrl
                homepageUrl = st.homepageUrl ?? ""
            }
        }
    }
    
    private func save() {
        isSubmitting = true
        Task {
            if let st = stationToEdit {
                let ok = await state.updateRadioStation(
                    id: st.id,
                    name: name,
                    streamUrl: streamUrl,
                    homepageUrl: homepageUrl.isEmpty ? nil : homepageUrl
                )
                if ok { dismiss() }
            } else {
                let ok = await state.createRadioStation(
                    name: name,
                    streamUrl: streamUrl,
                    homepageUrl: homepageUrl.isEmpty ? nil : homepageUrl
                )
                if ok { dismiss() }
            }
            isSubmitting = false
        }
    }
}

// MARK: - Folder Management Functions

extension ServerAdminPage {
    private func scanSpecificFolder(_ id: String) async {
        guard let c = state.client else { return }
        do {
            _ = try await c.scanMusicFolder(id: id)
            state.showToast("Started scanning folder", kind: .info)
        } catch {
            state.showToast("Failed to scan folder: \(error.localizedDescription)", kind: .error)
        }
    }
    
    private func removeFolder(_ folder: MusicFolder) {
        Task {
            do {
                try await state.client?.removeMusicFolder(id: folder.id)
                await state.loadServerControlData()
                state.showToast("Removed folder: \(folder.name)", kind: .info)
            } catch {
                state.showToast("Failed to remove folder: \(error.localizedDescription)", kind: .error)
            }
        }
    }
}
