import Foundation
import CLyricsEngine

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: Double // in seconds (-1 for unsynced plain text)
    let text: String
}

/// High-performance lyrics engine backed by native C timing and parsing.
enum Lyrics {
    /// Fetches lyrics natively from the connected Subsonic / Navidrome server.
    static func fetch(_ s: Song, client: NavidromeClient?) async -> [LyricLine] {
        guard let client else { return [] }
        return await client.lyrics(for: s)
    }

    /// Fast C-powered LRC parser.
    static func parse(_ text: String) -> [LyricLine] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let utf8 = trimmed.utf8CString
        let estimatedMax = max(64, trimmed.components(separatedBy: "\n").count * 2)
        var entries = [CLyricEntry](repeating: CLyricEntry(time_sec: -1, text_offset: 0, text_length: 0), count: estimatedMax)

        let count = utf8.withUnsafeBufferPointer { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return 0 }
            return Int32(c_lyrics_parse_lrc(base, &entries, Int32(estimatedMax)))
        }

        guard count > 0 else {
            return trimmed.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map {
                LyricLine(id: $0.offset, time: -1, text: String($0.element))
            }
        }

        let rawData = trimmed.data(using: .utf8) ?? Data()
        var lines: [LyricLine] = []
        lines.reserveCapacity(Int(count))

        for i in 0..<Int(count) {
            let entry = entries[i]
            let offset = Int(entry.text_offset)
            let length = Int(entry.text_length)

            var lineString = ""
            if offset >= 0 && length >= 0 && (offset + length) <= rawData.count {
                let subdata = rawData.subdata(in: offset..<(offset + length))
                lineString = String(data: subdata, encoding: .utf8) ?? ""
            }
            lines.append(LyricLine(id: i, time: entry.time_sec, text: lineString))
        }

        return lines
    }

    /// High-performance C binary search for the active lyric index with audio lead compensation.
    /// Runs in O(log N) in C with zero heap allocations per frame.
    static func index(_ timestamps: [Double], at t: Double, leadOffset: Double = 0.40) -> Int? {
        guard !timestamps.isEmpty else { return nil }
        let idx = timestamps.withUnsafeBufferPointer { ptr in
            c_lyrics_find_active_index(ptr.baseAddress, Int32(ptr.count), t, leadOffset)
        }
        return idx >= 0 ? Int(idx) : nil
    }

    /// High-performance C calculation for active line progress ratio (0.0 to 1.0).
    static func progress(_ timestamps: [Double], activeIndex: Int, at t: Double, leadOffset: Double = 0.40) -> Double {
        guard !timestamps.isEmpty, activeIndex >= 0 else { return 0.0 }
        return timestamps.withUnsafeBufferPointer { ptr in
            c_lyrics_get_line_progress(ptr.baseAddress, Int32(ptr.count), Int32(activeIndex), t, leadOffset)
        }
    }
}
