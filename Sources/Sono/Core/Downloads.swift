import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Observation

/// Offline library: original files (no DRM, no re-encoding) saved to ~/Music/Sono. Downloaded tracks are always played locally first.
@Observable @MainActor
final class Downloads {
    struct Entry: Codable { let song: Song; let file: String }
    let dir: URL = {
        let base = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sono")
    }()
    var active: Set<String> = []
    var index: [String: Entry] = (try? JSONDecoder().decode([String: Entry].self, from: UserDefaults.standard.data(forKey: "downloads") ?? Data())) ?? [:] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(index), forKey: "downloads") }
    }
    var songs: [Song] { index.values.map(\.song).sorted { $0.title < $1.title } }

    func has(_ id: String) -> Bool { index[id] != nil }
    func url(for id: String) -> URL? {
        guard let e = index[id] else { return nil }
        let u = dir.appendingPathComponent(e.file)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    func download(_ s: Song, client: NavidromeClient) async {
        guard index[s.id] == nil, !active.contains(s.id) else { return }
        active.insert(s.id); defer { active.remove(s.id) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let (tmp, _) = try await URLSession.shared.download(from: client.original(s.id))
            let base = "\(s.artist ?? "Unknown") - \(s.title)".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let name = base + "." + (s.suffix ?? "mp3")
            let dest = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            index[s.id] = Entry(song: s, file: name)
        } catch {}
    }
    func downloadAll(_ songs: [Song], client: NavidromeClient) async {
        await withTaskGroup(of: Void.self) { g in
            var it = songs.makeIterator(); var running = 0
            while running < 3, let s = it.next() { g.addTask { await self.download(s, client: client) }; running += 1 }
            while await g.next() != nil { if let s = it.next() { g.addTask { await self.download(s, client: client) } } }
        }
    }
    func remove(_ s: Song) {
        if let u = url(for: s.id) { try? FileManager.default.removeItem(at: u) }
        index[s.id] = nil
    }
    func reveal() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #if os(macOS)
        NSWorkspace.shared.open(dir)
        #elseif os(Windows)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "C:\\Windows\\explorer.exe")
        process.arguments = [dir.path]
        try? process.run()
        #endif
    }
}

/// One-click exports Spotify doesn't offer.
@MainActor enum Exporter {
    static func save(_ name: String, _ text: String) {
        #if os(macOS)
        let p = NSSavePanel(); p.nameFieldStringValue = name
        if p.runModal() == .OK, let u = p.url { try? text.write(to: u, atomically: true, encoding: .utf8) }
        #else
        let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try? text.write(to: dest, atomically: true, encoding: .utf8)
        #endif
    }
    static func m3u(_ songs: [Song], title: String, downloads d: Downloads) {
        var t = "#EXTM3U\n"
        for s in songs {
            t += "#EXTINF:\(s.duration ?? -1),\(s.artist ?? "") - \(s.title)\n"
            t += (d.url(for: s.id)?.path ?? "# not downloaded: \(s.artist ?? "") - \(s.title)") + "\n"
        }
        save("\(title).m3u8", t)
    }
    static func csv(_ songs: [Song], title: String) {
        func q(_ s: String?) -> String { "\"" + (s ?? "").replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        save("\(title).csv", "title,artist,album,duration\n" + songs.map { [q($0.title), q($0.artist), q($0.album), "\($0.duration ?? 0)"].joined(separator: ",") }.joined(separator: "\n"))
    }
    static func json(_ songs: [Song], title: String) {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        save("\(title).json", String(decoding: (try? e.encode(songs)) ?? Data(), as: UTF8.self))
    }
    static func lrc(_ lines: [LyricLine], title: String) { save("\(title).lrc", lrcText(lines)) }
    static func lrcText(_ lines: [LyricLine]) -> String {
        lines.map { l in l.time < 0 ? l.text : String(format: "[%02d:%05.2f]%@", Int(l.time) / 60, l.time.truncatingRemainder(dividingBy: 60), l.text) }.joined(separator: "\n")
    }
}
