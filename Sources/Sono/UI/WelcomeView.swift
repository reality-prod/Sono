import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) var state
    @State private var logoPulse = false
    
    var body: some View {
        ZStack {
            Ambient(intensity: 1.1)
            
            ScrollView {
                VStack(spacing: 36) {
                    // Hero Section
                    VStack(spacing: 20) {
                        SonoLogo(size: 96)
                            .scaleEffect(logoPulse ? 1.05 : 0.98)
                            .shadow(color: Theme.purple.opacity(logoPulse ? 0.8 : 0.4), radius: logoPulse ? 32 : 16)
                            .padding(.top, 24)
                        
                        VStack(spacing: 10) {
                            Text("Welcome to Sono")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, Color.white.opacity(0.85)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            Text("The modern, high-fidelity Navidrome & Subsonic client for macOS.")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 500)
                        }
                    }
                    
                    // Features Grid (clean & minimal)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        FeatureCard(
                            icon: "sparkles",
                            color: Theme.purple,
                            title: "Bit-Perfect Audio",
                            description: "Lossless, original streams directly from your personal music server."
                        )
                        FeatureCard(
                            icon: "bolt.fill",
                            color: Theme.violet,
                            title: "Instant Search",
                            description: "Find tracks, albums, and artists in milliseconds with local caching."
                        )
                        FeatureCard(
                            icon: "quote.bubble.fill",
                            color: Theme.infoBlue,
                            title: "Synced Lyrics",
                            description: "Karaoke-style synchronized lyrics rendered in real-time."
                        )
                        FeatureCard(
                            icon: "arrow.down.circle.fill",
                            color: Theme.successGreen,
                            title: "Offline Library",
                            description: "Original audio downloaded to ~/Music/Sono with zero DRM."
                        )
                    }
                    .frame(maxWidth: 620)
                    
                    // Call to Action
                    VStack(spacing: 14) {
                        Button {
                            state.showAddServerSheet = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Connect to Server")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .frame(minWidth: 220)
                            .padding(.vertical, 13)
                            .padding(.horizontal, 26)
                            .background(
                                LinearGradient(
                                    colors: [Theme.purple, Theme.violet],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .shadow(color: Theme.purple.opacity(0.4), radius: 12, y: 3)
                        }
                        .buttonStyle(.plain)
                        
                        if !state.servers.isEmpty {
                            Button {
                                state.showWelcome = false
                                state.page = .listenNow
                            } label: {
                                Text("Continue to Library")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                logoPulse = true
            }
        }
        .sheet(isPresented: Bindable(state).showAddServerSheet) {
            ServerSetupSheet(editingServer: nil)
        }
    }
}

struct FeatureCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
