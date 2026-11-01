import SwiftUI

/// Full-page lyrics. Redraws every display frame and reads the playhead directly, so sync is bounded by frame rate, not a timer.
struct LyricsView: View {
    @Environment(AppState.self) var s
    
    var body: some View {
        let p = s.player
        ZStack(alignment: .topTrailing) {
            Ambient(intensity: 1.4)
            
            HStack(spacing: 50) {
                // Left Column: Artwork & Track Meta
                VStack(alignment: .leading, spacing: 18) {
                    if let c = p.current {
                        Art(id: c.coverArt, size: 280, cornerRadius: 20)
                            .shadow(color: p.accent.opacity(0.6), radius: 40, y: 10)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.title)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            
                            Text(c.artist ?? "")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            
                            if let alb = c.album, !alb.isEmpty {
                                Text(alb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    // Transport controls
                    HStack(spacing: 16) {
                        Button {
                            p.previous()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            p.toggle()
                        } label: {
                            Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 46))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            p.next()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 6)
                    
                    // Lyrics utility buttons
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(p.lyrics.map(\.text).joined(separator: "\n"), forType: .string)
                                s.showToast("Lyrics copied to clipboard", kind: .info)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                Exporter.lrc(p.lyrics, title: p.current?.title ?? "lyrics")
                                s.showToast("Exported .lrc file", kind: .success)
                            } label: {
                                Label("Export .lrc", systemImage: "square.and.arrow.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        // Sync calibration (fine-tune lead offset)
                        HStack(spacing: 6) {
                            Text("Sync:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button("-") {
                                p.lyricsOffset = max(0.0, p.lyricsOffset - 0.1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            
                            Text("\(Int(p.lyricsOffset * 1000))ms")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .center)
                            
                            Button("+") {
                                p.lyricsOffset = min(1.5, p.lyricsOffset + 0.1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.top, 4)
                    }
                    .disabled(p.lyrics.isEmpty)
                }
                .frame(width: 290)
                
                // Right Column: Synchronized Lyrics (driven by high-speed C timing)
                TimelineView(.animation) { _ in
                    let cur = Lyrics.index(p.lyricTimestamps, at: p.time, leadOffset: p.lyricsOffset)
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 22) {
                                if p.lyrics.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("No Synced Lyrics Found")
                                            .font(.system(size: 32, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.8))
                                        Text("No lyrics found on server for \"\(p.current?.title ?? "")\".")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.top, 100)
                                } else {
                                    ForEach(p.lyrics) { l in
                                        let d = cur.map { abs(l.id - $0) } ?? 3
                                        Button {
                                            if l.time >= 0 {
                                                p.seek(l.time)
                                            }
                                        } label: {
                                            Text(l.text.isEmpty ? "♪" : l.text)
                                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                                .multilineTextAlignment(.leading)
                                                .foregroundStyle(
                                                    .white.opacity(d == 0 ? 1.0 : d == 1 ? 0.45 : d == 2 ? 0.28 : 0.16)
                                                )
                                                .scaleEffect(d == 0 ? 1.0 : 0.94, anchor: .leading)
                                                .animation(.easeOut(duration: 0.2), value: cur)
                                        }
                                        .buttonStyle(.plain)
                                        .id(l.id)
                                    }
                                }
                            }
                            .padding(.vertical, 240)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: cur) { _, n in
                            if let n {
                                withAnimation(.easeInOut(duration: 0.45)) {
                                    proxy.scrollTo(n, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
            
            // Close Button
            Button {
                withAnimation { s.showLyrics = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(28)
        }
    }
}
