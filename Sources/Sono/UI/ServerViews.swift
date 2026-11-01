import SwiftUI

// MARK: - Server Setup & Edit Sheet

struct ServerSetupSheet: View {
    @Environment(AppState.self) var state
    @Environment(\.dismiss) var dismiss
    
    var editingServer: Server?
    
    @State private var name = ""
    @State private var url = "http://"
    @State private var user = ""
    @State private var pass = ""
    @State private var showPassword = false
    
    @State private var isConnecting = false
    @State private var errorMessage: String? = nil
    
    var isEditing: Bool { editingServer != nil }
    var isValid: Bool {
        !user.trimmingCharacters(in: .whitespaces).isEmpty &&
        url.trimmingCharacters(in: .whitespaces).count >= 8
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(isEditing ? "Edit Server" : "Connect to Server")
                    .font(.title2.bold())
                Text("Enter your Navidrome or Subsonic server details.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Form Fields
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Server Address")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("http://localhost:4533 or https://music.example.com", text: $url)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("Server Name")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("Optional (defaults to address)", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("Username")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("Username", text: $user)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(isEditing ? "Password (leave blank to keep current)" : "Password")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack {
                        if showPassword {
                            TextField(isEditing ? "Unchanged" : "Password", text: $pass)
                        } else {
                            SecureField(isEditing ? "Unchanged" : "Password", text: $pass)
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            
            // Inline Error Banner (clean & focused)
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.errorRed)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.errorRed)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .transition(.opacity)
            }
            
            Spacer()
            
            Divider()
            
            // Actions
            HStack(spacing: 12) {
                if errorMessage != nil {
                    Button("Save Anyway") {
                        saveWithoutTesting()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                
                Button {
                    connectAndSave()
                } label: {
                    HStack(spacing: 6) {
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isEditing ? "Save" : "Connect")
                    }
                    .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.purple)
                .disabled(!isValid || isConnecting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
        }
        .frame(width: 440, height: 420)
        .onAppear {
            if let s = editingServer {
                name = s.name
                url = s.url
                user = s.user
                pass = Keychain.get(s.id.uuidString) ?? ""
            }
        }
    }
    
    private func connectAndSave() {
        isConnecting = true
        errorMessage = nil
        
        Task {
            let passwordToUse: String
            if pass.isEmpty, let s = editingServer {
                passwordToUse = Keychain.get(s.id.uuidString) ?? ""
            } else {
                passwordToUse = pass
            }
            
            if let s = editingServer {
                let updated = Server(
                    id: s.id,
                    name: name.trimmingCharacters(in: .whitespaces).isEmpty ? (URL(string: NavidromeClient.sanitize(url: url))?.host ?? "Navidrome") : name,
                    url: url,
                    user: user
                )
                let res = await state.update(server: updated, password: pass.isEmpty ? nil : pass)
                if !res.success {
                    errorMessage = res.error?.localizedDescription ?? "Could not connect to server."
                    isConnecting = false
                    return
                }
            } else {
                let newServer = Server(
                    name: name.trimmingCharacters(in: .whitespaces).isEmpty ? (URL(string: NavidromeClient.sanitize(url: url))?.host ?? "Navidrome") : name,
                    url: url,
                    user: user
                )
                let res = await state.add(server: newServer, password: passwordToUse, force: false)
                if !res.success {
                    errorMessage = res.error?.localizedDescription ?? "Could not connect to server."
                    isConnecting = false
                    return
                }
            }
            isConnecting = false
            dismiss()
        }
    }
    
    private func saveWithoutTesting() {
        Task {
            let cleanURL = NavidromeClient.sanitize(url: url)
            let serverName = name.trimmingCharacters(in: .whitespaces).isEmpty ? (URL(string: cleanURL)?.host ?? "Navidrome") : name
            
            if let s = editingServer {
                let updated = Server(id: s.id, name: serverName, url: cleanURL, user: user)
                if !pass.isEmpty { Keychain.set(pass, for: s.id.uuidString) }
                if let idx = state.servers.firstIndex(where: { $0.id == s.id }) {
                    state.servers[idx] = updated
                }
                if state.activeID == s.id {
                    await state.refresh()
                }
            } else {
                let newServer = Server(name: serverName, url: cleanURL, user: user)
                await state.add(server: newServer, password: pass, force: true)
            }
            dismiss()
        }
    }
}

// MARK: - Server Card (Spotify / Apple Music Style)

struct ServerCard: View {
    @Environment(AppState.self) var state
    let server: Server
    let isActive: Bool
    
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Theme.purple.opacity(0.18) : Color.white.opacity(0.05))
                    .frame(width: 40, height: 40)
                Image(systemName: "server.rack")
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? Theme.purple : .secondary)
            }
            
            // Name & Address
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(server.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    if isActive {
                        HStack(spacing: 5) {
                            StatusDot(status: state.serverStatus)
                            Text(state.serverStatus.isConnected ? "Connected" : state.serverStatus.isConnecting ? "Connecting" : "Offline")
                                .font(.caption2.bold())
                                .foregroundStyle(state.serverStatus.isConnected ? Theme.successGreen : state.serverStatus.isConnecting ? Theme.warningOrange : Theme.errorRed)
                        }
                    }
                }
                
                Text("\(server.url)  •  \(server.user)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 10) {
                if isActive {
                    Button {
                        state.page = .serverControl
                    } label: {
                        Label("Control", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Connect") {
                        state.select(server)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Menu {
                    if isActive {
                        Button("Server Control & Admin") {
                            state.page = .serverControl
                        }
                        Divider()
                    }
                    Button("Edit Server") {
                        showEditSheet = true
                    }
                    Divider()
                    Button("Remove Server", role: .destructive) {
                        showDeleteConfirm = true
                    }
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isActive ? Theme.purple.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showEditSheet) {
            ServerSetupSheet(editingServer: server)
        }
        .confirmationDialog("Remove Server", isPresented: $showDeleteConfirm) {
            Button("Remove \(server.name)", role: .destructive) {
                state.remove(server)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove \"\(server.name)\"?")
        }
    }
}

// MARK: - Servers Page (Minimal & Professional)

struct ServersPage: View {
    @Environment(AppState.self) var state
    @State private var showAddSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header (Spotify style)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Servers")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Manage your Navidrome and Subsonic endpoints.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add Server", systemImage: "plus")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.purple)
                }
                
                // Minimal Connection Error Notice (only if active server fails)
                if let err = state.activeServerError, let active = state.active {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.errorRed)
                            .font(.system(size: 14))
                        
                        Text("Cannot connect to \(active.name): \(err.localizedDescription)")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        Button("Retry") {
                            Task { await state.refresh() }
                        }
                        .font(.caption.bold())
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.purple)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.errorRed.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.errorRed.opacity(0.25), lineWidth: 1))
                    )
                }
                
                // Server list
                if state.servers.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .padding(.top, 40)
                        
                        VStack(spacing: 4) {
                            Text("No Servers Added")
                                .font(.headline)
                            Text("Connect your Navidrome server to start streaming.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button("Add Server") {
                            showAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.purple)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    VStack(spacing: 8) {
                        ForEach(state.servers) { sv in
                            ServerCard(server: sv, isActive: sv.id == state.active?.id)
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .sheet(isPresented: $showAddSheet) {
            ServerSetupSheet(editingServer: nil)
        }
    }
}
