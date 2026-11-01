import SwiftUI

// MARK: - Internet Radio Page

struct RadioPage: View {
    @Environment(AppState.self) var state
    @State private var showAddStationSheet = false
    @State private var editingStation: InternetRadioStation? = nil
    @State private var stationToDelete: InternetRadioStation? = nil
    @State private var searchText = ""
    
    var filteredStations: [InternetRadioStation] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return state.radioStations
        }
        return state.radioStations.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.streamUrl.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Internet Radio")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Stream live internet radio stations configured on your Navidrome server.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        showAddStationSheet = true
                    } label: {
                        Label("Add Station", systemImage: "plus")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.purple)
                }
                
                // Currently Playing Radio Station Hero Banner (if radio is playing)
                if let curRadio = state.player.currentRadio, state.player.isPlaying {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Theme.purple, Theme.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 52, height: 52)
                            
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("NOW TUNED IN")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Theme.purple)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.purple.opacity(0.18), in: Capsule())
                                
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Theme.errorRed)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.errorRed.opacity(0.18), in: Capsule())
                            }
                            
                            Text(curRadio.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                            
                            Text(curRadio.streamUrl)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button {
                            state.player.toggle()
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Theme.purple, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Theme.purple.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.purple.opacity(0.3), lineWidth: 1))
                    )
                }
                
                // Search Bar
                if !state.radioStations.isEmpty {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search radio stations…", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                
                // Station Cards Grid
                if state.radioStations.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .padding(.top, 40)
                        
                        VStack(spacing: 4) {
                            Text("No Radio Stations")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Register internet radio streams to listen live within Sono.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button("Add Station") {
                            showAddStationSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.purple)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                        ForEach(filteredStations) { station in
                            RadioCard(
                                station: station,
                                isPlaying: state.player.currentRadio?.id == station.id && state.player.isPlaying,
                                onPlay: { state.playRadio(station) },
                                onEdit: { editingStation = station },
                                onDelete: { stationToDelete = station }
                            )
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showAddStationSheet) {
            RadioStationSheet(stationToEdit: nil)
        }
        .sheet(item: $editingStation) { station in
            RadioStationSheet(stationToEdit: station)
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

struct RadioCard: View {
    let station: InternetRadioStation
    let isPlaying: Bool
    let onPlay: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Radio antenna icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isPlaying ? Theme.purple.opacity(0.2) : Color.white.opacity(0.05))
                        .frame(width: 48, height: 48)
                    Image(systemName: "radio.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isPlaying ? Theme.purple : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(station.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(station.streamUrl)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Menu {
                    Button(isPlaying ? "Pause Stream" : "Play Stream") { onPlay() }
                    Button("Edit Station") { onEdit() }
                    Divider()
                    Button("Delete Station", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            
            HStack {
                Button {
                    onPlay()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        Text(isPlaying ? "Playing" : "Play")
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(isPlaying ? Theme.purple : Color.white.opacity(0.1))
                .controlSize(.small)
                
                Spacer()
                
                if let home = station.homepageUrl, let url = URL(string: home) {
                    Link(destination: url) {
                        Image(systemName: "safari")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open station website")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isPlaying ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isPlaying ? Theme.purple.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
