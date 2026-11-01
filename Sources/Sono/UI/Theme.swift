import SwiftUI

enum Theme {
    static let purple = Color(red: 0.58, green: 0.32, blue: 1.0)
    static let violet = Color(red: 0.72, green: 0.40, blue: 1.0)
    static let deep = Color(red: 0.16, green: 0.05, blue: 0.38)
    static let black = Color(red: 0.035, green: 0.025, blue: 0.065)
    static let panel = Color.white.opacity(0.06)
    static let panelBorder = Color.white.opacity(0.09)
    static let panelHover = Color.white.opacity(0.10)
    static let cardBackground = Color(red: 0.09, green: 0.07, blue: 0.14).opacity(0.72)
    static let cardBorder = Color.white.opacity(0.12)
    
    // Status colors
    static let successGreen = Color(red: 0.22, green: 0.85, blue: 0.52)
    static let warningOrange = Color(red: 1.0, green: 0.65, blue: 0.18)
    static let errorRed = Color(red: 1.0, green: 0.32, blue: 0.36)
    static let infoBlue = Color(red: 0.32, green: 0.68, blue: 1.0)
}

struct SonoLogo: View {
    var size: CGFloat = 96
    var animated: Bool = false
    private let h: [CGFloat] = [0.35, 0.62, 0.95, 0.52, 0.78]
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.purple, Theme.deep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: max(1, size * 0.015))
                )
            
            HStack(spacing: size * 0.05) {
                ForEach(0..<h.count, id: \.self) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [.white, .white.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                        .frame(width: size * 0.082, height: size * 0.58 * h[i])
                        .shadow(color: .white.opacity(0.3), radius: 3)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct StatusDot: View {
    let status: ServerStatus
    @State private var pulse = false
    
    var color: Color {
        switch status {
        case .connected: return Theme.successGreen
        case .connecting: return Theme.warningOrange
        case .failed: return Theme.errorRed
        case .disconnected: return Color.secondary.opacity(0.5)
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(pulse && status.isConnecting ? 0.35 : 0.2))
                .frame(width: 14, height: 14)
                .scaleEffect(pulse && status.isConnecting ? 1.5 : 1.0)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.8), radius: 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct ToastBannerView: View {
    let toast: Toast
    
    var iconName: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    var iconColor: Color {
        switch toast.kind {
        case .success: return Theme.successGreen
        case .error: return Theme.errorRed
        case .info: return Theme.purple
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.system(size: 14, weight: .bold))
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(iconColor.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 12, y: 4)
        )
    }
}

struct SplashView: View {
    @Environment(AppState.self) var state
    @State private var pulse = false
    
    var body: some View {
        ZStack {
            Ambient(intensity: 1.2)
            VStack(spacing: 24) {
                SonoLogo(size: 110)
                    .scaleEffect(pulse ? 1.04 : 0.98)
                    .shadow(color: Theme.purple.opacity(pulse ? 0.7 : 0.35), radius: pulse ? 35 : 18)
                
                VStack(spacing: 6) {
                    Text("Sono")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(state.status)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                ProgressView()
                    .controlSize(.regular)
                    .tint(Theme.purple)
                    .padding(.top, 4)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Pulsing, drifting gradient tinted by the current album art. Pauses (no CPU) when music is paused.
struct Ambient: View {
    @Environment(AppState.self) var s
    var intensity = 0.6
    
    var body: some View {
        let p = s.player
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !p.isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.black
                RadialGradient(
                    colors: [p.accent.opacity(0.55 * intensity), .clear],
                    center: UnitPoint(x: 0.25 + 0.15 * sin(t * 0.35), y: 0.2 + 0.12 * cos(t * 0.27)),
                    startRadius: 0,
                    endRadius: 480 + 70 * sin(t * 1.7)
                )
                RadialGradient(
                    colors: [Theme.purple.opacity(0.42 * intensity), .clear],
                    center: UnitPoint(x: 0.8 + 0.12 * cos(t * 0.3), y: 0.85 + 0.1 * sin(t * 0.4)),
                    startRadius: 0,
                    endRadius: 440 + 60 * sin(t * 1.3 + 1)
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.06 * intensity), .clear],
                    center: UnitPoint(x: 0.6 + 0.2 * sin(t * 0.2), y: 0.4),
                    startRadius: 0,
                    endRadius: 320
                )
            }
            .animation(.easeInOut(duration: 1.2), value: p.accent)
        }
        .ignoresSafeArea()
    }
}
