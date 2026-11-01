import SwiftUI
#if os(macOS)
import AppKit

final class CloseHider: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        false
    }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        app.windows.first?.makeKeyAndOrderFront(nil)
        return true
    }
}

struct WindowHook: NSViewRepresentable {
    static let hider = CloseHider()
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            v.window?.delegate = Self.hider
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}
#endif

@main
struct SonoApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    #endif
    @State private var state = AppState()

    var body: some Scene {
        Window("Sono", id: "main") {
            ZStack {
                if state.ready {
                    RootView()
                } else {
                    SplashView()
                }
            }
            .environment(state)
            #if os(macOS)
            .background(WindowHook())
            #endif
            .frame(minWidth: 1060, minHeight: 700)
            .preferredColorScheme(.dark)
            .task { await state.boot() }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands {
            CommandMenu("Playback") {
                Button(state.player.isPlaying ? "Pause" : "Play") {
                    state.player.toggle()
                }
                .keyboardShortcut("p", modifiers: [])
                
                Button("Next") {
                    state.player.next()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                
                Button("Previous") {
                    state.player.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                Button("Shuffle") {
                    state.player.shuffle.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                
                Button("Repeat") {
                    state.player.cycleRepeat()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                
                Divider()
                
                Button("Lyrics") {
                    withAnimation { state.showLyrics.toggle() }
                }
                .keyboardShortcut("l", modifiers: [])
                
                Button("Queue") {
                    state.showQueue.toggle()
                }
                .keyboardShortcut("u", modifiers: [])
                
                Button("Search") {
                    state.page = .search
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
            
            CommandMenu("Server") {
                Button("Connect to Server…") {
                    state.showAddServerSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Button("Server Control & Admin") {
                    state.page = .serverControl
                }
                
                Button("Manage Servers") {
                    state.page = .servers
                }
                
                Button("Refresh Library") {
                    Task { await state.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                
                Button("Rescan Library") {
                    Task { await state.startLibraryScan(fullScan: false) }
                }
                
                Divider()
                
                Button("Welcome to Sono") {
                    state.showWelcome = true
                }
            }
            
            #if os(macOS)
            CommandGroup(replacing: .help) {
                Button("Sono Help") {
                    NSApp.showHelp(nil)
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
            #endif
        }

        #if os(macOS)
        MenuBarExtra("Sono", systemImage: state.player.isPlaying ? "waveform" : "waveform.slash") {
            if let cur = state.player.current {
                Text("\(cur.title) — \(cur.artist ?? "Unknown")")
            } else {
                Text("Nothing playing")
            }
            
            Divider()
            
            Button(state.player.isPlaying ? "Pause" : "Play") {
                state.player.toggle()
            }
            Button("Next") {
                state.player.next()
            }
            Button("Previous") {
                state.player.previous()
            }
            
            Divider()
            
            if let active = state.active {
                Text("Server: \(active.name)")
                    .font(.caption)
            }
            
            Button("Show Sono") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            
            Divider()
            
            Button("Quit Sono") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        #endif
    }
}
