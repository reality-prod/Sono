import SwiftUI
import UniformTypeIdentifiers

/// Folder browser for selecting music directories on the server
struct FolderBrowserView: View {
    @Environment(AppState.self) var state
    @Binding var isPresented: Bool
    
    @State private var currentPath: String = "/"
    @State private var folders: [FolderItem] = []
    @State private var selectedFolders: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var newFolderName = ""
    @State private var showNewFolderSheet = false
    @State private var newFolderPath = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Music Folder Manager")
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .foregroundStyle(.white)
                    Text("Add and manage music directories on your server")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Close button
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            
            Divider().overlay(Color.white.opacity(0.06))
            
            // Path navigation
            HStack(spacing: 8) {
                Button {
                    currentPath = "/"
                    Task { await loadFolders() }
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Text(currentPath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Add folder button
                if state.isAdmin {
                    Button {
                        showNewFolderSheet = true
                    } label: {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.purple)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.03))
            
            Divider().overlay(Color.white.opacity(0.06))
            
            // Error message
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.errorRed)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.errorRed)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Theme.errorRed.opacity(0.1))
            }
            
            // Folder list
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Parent folder
                    if currentPath != "/" {
                        Button {
                            let parentPath = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
                            currentPath = parentPath.isEmpty ? "/" : parentPath
                            Task { await loadFolders() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Theme.purple)
                                Text(".. (Parent)")
                                    .font(.system(size: 13, weight: .medium, design: .default))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        
                        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 40)
                    }
                    
                    // Folders
                    ForEach(folders) { folder in
                        Button {
                            if folder.isDirectory {
                                currentPath = folder.path
                                Task { await loadFolders() }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: folder.isDirectory ? "folder.fill" : "doc.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(folder.isSelected ? Theme.purple : .secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.name)
                                        .font(.system(size: 13, weight: .medium, design: .default))
                                        .foregroundStyle(folder.isSelected ? .white : .primary)
                                    
                                    if let size = folder.size {
                                        Text(size)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if folder.isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Theme.purple)
                                } else if folder.isConfigured {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if state.isAdmin {
                                Button {
                                    addFolder(folder.path)
                                } label: {
                                    Label("Add to Music Library", systemImage: "plus.circle")
                                }
                                
                                if folder.isConfigured {
                                    Button {
                                        removeFolder(folder.id)
                                    } label: {
                                        Label("Remove from Library", systemImage: "minus.circle")
                                    }
                                }
                                
                                Divider()
                                
                                Button {
                                    scanFolder(folder.id)
                                } label: {
                                    Label("Scan This Folder", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                        
                        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 40)
                    }
                }
            }
            
            // Bottom actions
            if state.isAdmin {
                Divider().overlay(Color.white.opacity(0.06))
                
                HStack(spacing: 12) {
                    Button {
                        Task { await refreshMusicFolders() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button {
                        isPresented = false
                    } label: {
                        Text("Done")
                            .frame(width: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.purple)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .frame(width: 500, height: 500)
        .background(Theme.black)
        .onAppear {
            Task { await loadFolders() }
        }
        .sheet(isPresented: $showNewFolderSheet) {
            VStack(spacing: 16) {
                Text("Add New Folder")
                    .font(.headline)
                    .padding(.top, 20)
                
                TextField("Folder Name", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)
                
                TextField("Path (optional)", text: $newFolderPath)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)
                
                HStack {
                    Button("Cancel") { showNewFolderSheet = false }
                        .buttonStyle(.plain)
                    Spacer()
                    Button {
                        Task { await createNewFolder() }
                    } label: {
                        Text("Create")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.purple)
                    .disabled(newFolderName.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(width: 360, height: 200)
        }
    }
    
    private func loadFolders() async {
        isLoading = true
        errorMessage = nil
        
        // This is a placeholder - in a real implementation, we would need
        // a server endpoint that lists directory contents
        // For now, we'll simulate a basic file browser
        
        do {
            // Try to get configured folders first
            let configured = try await state.client?.getMusicFolders() ?? []
            let configuredPaths = Set(configured.map(\.id))
            
            // Simulate browsing - in reality, Navidrome doesn't expose a full
            // filesystem browser API, so we'd need to use a different approach
            // For now, show configured folders
            
            folders = configured.map { folder in
                FolderItem(
                    id: folder.id,
                    name: folder.name,
                    path: "/music/" + folder.name,
                    isDirectory: true,
                    isSelected: selectedFolders.contains(folder.id),
                    isConfigured: true,
                    size: nil
                )
            }
            
            // Add some placeholder folders for demonstration
            // In a real implementation, this would come from the server
            if folders.isEmpty {
                folders = [
                    FolderItem(id: "1", name: "Music", path: "/music", isDirectory: true, isSelected: false, isConfigured: false),
                    FolderItem(id: "2", name: "Podcasts", path: "/podcasts", isDirectory: true, isSelected: false, isConfigured: false),
                    FolderItem(id: "3", name: "Audiobooks", path: "/audiobooks", isDirectory: true, isSelected: false, isConfigured: false)
                ]
            }
            
        } catch {
            errorMessage = "Failed to load folders: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func addFolder(_ path: String) async {
        guard let client = state.client else { return }
        
        do {
            // Extract just the folder name from the path
            let folderName = URL(fileURLWithPath: path).lastPathComponent
            try await client.createMusicFolder(path: path, name: folderName)
            await refreshMusicFolders()
            state.showToast("Added folder to music library", kind: .success)
        } catch {
            errorMessage = "Failed to add folder: \(error.localizedDescription)"
        }
    }
    
    private func removeFolder(_ id: String) async {
        guard let client = state.client else { return }
        
        do {
            try await client.removeMusicFolder(id: id)
            await refreshMusicFolders()
            state.showToast("Removed folder from music library", kind: .info)
        } catch {
            errorMessage = "Failed to remove folder: \(error.localizedDescription)"
        }
    }
    
    private func scanFolder(_ id: String) async {
        guard let client = state.client else { return }
        
        do {
            try await client.scanMusicFolder(id: id)
            state.showToast("Started scanning folder", kind: .info)
        } catch {
            errorMessage = "Failed to scan folder: \(error.localizedDescription)"
        }
    }
    
    private func refreshMusicFolders() async {
        do {
            state.musicFolders = try await state.client?.getMusicFolders() ?? []
        } catch {
            errorMessage = "Failed to refresh folders: \(error.localizedDescription)"
        }
    }
    
    private func createNewFolder() async {
        guard let client = state.client else { return }
        
        let path = newFolderPath.isEmpty ? currentPath + "/" + newFolderName : newFolderPath
        
        do {
            try await client.createMusicFolder(path: path, name: newFolderName)
            showNewFolderSheet = false
            newFolderName = ""
            newFolderPath = ""
            await loadFolders()
            state.showToast("Created new folder", kind: .success)
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
        }
    }
}

// MARK: - Folder Item Model

struct FolderItem: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    var isSelected: Bool
    var isConfigured: Bool
    let size: String?
    
    init(id: String, name: String, path: String, isDirectory: Bool, isSelected: Bool, isConfigured: Bool, size: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isSelected = isSelected
        self.isConfigured = isConfigured
        self.size = size
    }
}
