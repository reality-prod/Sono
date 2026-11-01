import Foundation
import CLyricsEngine

// MARK: - Lyric Line Model

struct LyricLine: Identifiable, Hashable, Codable {
    let id: Int
    let time: Double // in seconds (-1 for unsynced plain text)
    let text: String
    
    init(id: Int, time: Double, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

// MARK: - Lyrics Cache

struct LyricsCacheEntry: Codable {
    let songId: String
    let lines: [LyricLine]
    let timestamp: Date
    let source: String // "server", "lrc", "embedded"
    
    init(songId: String, lines: [LyricLine], source: String) {
        self.songId = songId
        self.lines = lines
        self.timestamp = Date()
        self.source = source
    }
}

private enum LyricsCache {
    private static let cacheKeyPrefix = "lyrics_cache_"
    private static let cacheExpiration: TimeInterval = 86400 * 7 // 7 days
    
    static func get(for songId: String) -> LyricsCacheEntry? {
        guard let data = UserDefaults.standard.data(forKey: cacheKeyPrefix + songId),
              let entry = try? JSONDecoder().decode(LyricsCacheEntry.self, from: data),
              entry.timestamp.timeIntervalSinceNow > -cacheExpiration else {
            return nil
        }
        return entry
    }
    
    static func set(_ entry: LyricsCacheEntry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: cacheKeyPrefix + entry.songId)
    }
    
    static func clear() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter({ $0.hasPrefix(cacheKeyPrefix) })
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    static func invalidate(for songId: String) {
        UserDefaults.standard.removeObject(forKey: cacheKeyPrefix + songId)
    }
}

// MARK: - Lyric Variant

struct LyricVariant: Identifiable, Hashable, Codable {
    var id: UUID
    let language: String?
    let isSynced: Bool
    let lines: [LyricLine]
    let source: String
    
    init(language: String? = nil, isSynced: Bool, lines: [LyricLine], source: String) {
        self.id = UUID()
        self.language = language
        self.isSynced = isSynced
        self.lines = lines
        self.source = source
    }
}

// MARK: - Lyrics Engine

/// High-performance lyrics engine backed by native C timing and parsing.
enum Lyrics {
    /// Fetches lyrics natively from the connected Subsonic / Navidrome server.
    static func fetch(_ s: Song, client: NavidromeClient?) async -> [LyricLine] {
        // Check cache first
        if let cached = LyricsCache.get(for: s.id) {
            return cached.lines
        }
        
        guard let client else { return [] }
        let lines = await client.lyrics(for: s)
        
        // Cache the result
        if !lines.isEmpty {
            LyricsCache.set(LyricsCacheEntry(songId: s.id, lines: lines, source: "server"))
        }
        
        return lines
    }

    /// Fetches all available lyric variants for a song.
    static func getVariants(for song: Song, client: NavidromeClient?) async -> [LyricVariant] {
        guard let client else { return [] }
        return await client.getLyricVariants(for: song)
    }

    /// Gets available languages for a song's lyrics.
    static func availableLanguages(for song: Song, client: NavidromeClient?) async -> [String] {
        let variants = await getVariants(for: song, client: client)
        return variants.compactMap { $0.language }.unique
    }

    /// Parses LRC format lyrics text with support for metadata tags.
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

    /// Parses LRC lyrics from text with enhanced metadata support.
    /// Handles [lang:xx] tags, [offset:xxx] tags, and other LRC metadata.
    static func parseEnhanced(_ text: String) -> (lines: [LyricLine], language: String?, offset: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], nil, 0) }

        var detectedLanguage: String? = nil
        var detectedOffset: Double = 0
        var lines: [LyricLine] = []
        
        let linesText = trimmed.components(separatedBy: .newlines)
        
        for line in linesText {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check for metadata tags
            if trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]") {
                let tagContent = String(trimmedLine.dropFirst().dropLast())
                
                // Parse [lang:xx] tag
                if tagContent.lowercased().hasPrefix("lang:") {
                    let langPattern = #"lang:([^\]]+)"#
                    if let regex = try? NSRegularExpression(pattern: langPattern) {
                        let range = NSRange(tagContent.startIndex..., in: tagContent)
                        if let match = regex.firstMatch(in: tagContent, range: range) {
                            let langRange = match.range(at: 1)
                            if let swiftRange = Range(langRange, in: tagContent) {
                                detectedLanguage = String(tagContent[swiftRange])
                            }
                        }
                    }
                }
                // Parse [offset:xxx] tag (in milliseconds)
                else if tagContent.lowercased().hasPrefix("offset:") {
                    let offsetStr = tagContent.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    if let offsetMs = Double(offsetStr) {
                        detectedOffset = offsetMs / 1000.0
                    }
                }
                continue
            }
            
            // Parse lyric line with timestamp
            let result = parseLyricLine(trimmedLine)
            if let (time, text) = result {
                lines.append(LyricLine(id: lines.count, time: time + detectedOffset, text: text))
            }
        }
        
        return (lines, detectedLanguage, detectedOffset)
    }

    /// Parses a single lyric line with timestamp.
    private static func parseLyricLine(_ line: String) -> (time: Double, text: String)? {
        // Pattern 1: [mm:ss.ff] text
        let pattern1 = #"^\\[(\d+):(\d{2})\\.(\d{2,3})\\](.*)"#
        if let regex = try? NSRegularExpression(pattern: pattern1) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 5 {
                let minRange = match.range(at: 1)
                let secRange = match.range(at: 2)
                let msRange = match.range(at: 3)
                let textRange = match.range(at: 4)
                
                if let swiftMin = Range(minRange, in: line),
                   let swiftSec = Range(secRange, in: line),
                   let swiftMs = Range(msRange, in: line) {
                    let minutes = Int(String(line[swiftMin])) ?? 0
                    let seconds = Int(String(line[swiftSec])) ?? 0
                    var milliseconds = Int(String(line[swiftMs])) ?? 0
                    
                    // Normalize milliseconds to 3 digits
                    while milliseconds >= 1000 {
                        milliseconds /= 10
                    }
                    
                    let time = Double(minutes * 60 + seconds) + Double(milliseconds) / 1000.0
                    let textStart = textRange.location < line.count ? line.index(line.startIndex, offsetBy: textRange.location) : line.endIndex
                    let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
                    return (time, text)
                }
            }
        }
        
        // Pattern 2: [mm:ss] text
        let pattern2 = #"^\\[(\d+):(\d{2})\\](.*)"#
        if let regex = try? NSRegularExpression(pattern: pattern2) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 4 {
                let minRange = match.range(at: 1)
                let secRange = match.range(at: 2)
                let textRange = match.range(at: 3)
                
                if let swiftMin = Range(minRange, in: line),
                   let swiftSec = Range(secRange, in: line) {
                    let minutes = Int(String(line[swiftMin])) ?? 0
                    let seconds = Int(String(line[swiftSec])) ?? 0
                    let time = Double(minutes * 60 + seconds)
                    let textStart = textRange.location < line.count ? line.index(line.startIndex, offsetBy: textRange.location) : line.endIndex
                    let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
                    return (time, text)
                }
            }
        }
        
        // Pattern 3: [ss.ff] text (seconds only)
        let pattern3 = #"^\\[(\d+)\\ .(\d{2,3})\\](.*)"#
        if let regex = try? NSRegularExpression(pattern: pattern3) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 4 {
                let secRange = match.range(at: 1)
                let msRange = match.range(at: 2)
                let textRange = match.range(at: 3)
                
                if let swiftSec = Range(secRange, in: line),
                   let swiftMs = Range(msRange, in: line) {
                    let seconds = Int(String(line[swiftSec])) ?? 0
                    var milliseconds = Int(String(line[swiftMs])) ?? 0
                    
                    while milliseconds >= 1000 {
                        milliseconds /= 10
                    }
                    
                    let time = Double(seconds) + Double(milliseconds) / 1000.0
                    let textStart = textRange.location < line.count ? line.index(line.startIndex, offsetBy: textRange.location) : line.endIndex
                    let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
                    return (time, text)
                }
            }
        }
        
        // No timestamp found, treat as plain text
        if !line.isEmpty {
            return (-1, line)
        }
        
        return nil
    }

    /// Parses a timestamp string directly (without brackets).
    static func parseTimestamp(_ timestamp: String) -> Double? {
        // Try mm:ss.ff
        let pattern1 = #"^(\d+):(\d{2})\\.(\d{2,3})$"#
        if let regex = try? NSRegularExpression(pattern: pattern1) {
            let range = NSRange(timestamp.startIndex..., in: timestamp)
            if let match = regex.firstMatch(in: timestamp, range: range), match.numberOfRanges >= 4 {
                let minRange = match.range(at: 1)
                let secRange = match.range(at: 2)
                let msRange = match.range(at: 3)
                
                if let swiftMin = Range(minRange, in: timestamp),
                   let swiftSec = Range(secRange, in: timestamp),
                   let swiftMs = Range(msRange, in: timestamp) {
                    let minutes = Int(String(timestamp[swiftMin])) ?? 0
                    let seconds = Int(String(timestamp[swiftSec])) ?? 0
                    var milliseconds = Int(String(timestamp[swiftMs])) ?? 0
                    
                    while milliseconds >= 1000 {
                        milliseconds /= 10
                    }
                    
                    return Double(minutes * 60 + seconds) + Double(milliseconds) / 1000.0
                }
            }
        }
        
        // Try mm:ss
        let pattern2 = #"^(\d+):(\d{2})$"#
        if let regex = try? NSRegularExpression(pattern: pattern2) {
            let range = NSRange(timestamp.startIndex..., in: timestamp)
            if let match = regex.firstMatch(in: timestamp, range: range), match.numberOfRanges >= 3 {
                let minRange = match.range(at: 1)
                let secRange = match.range(at: 2)
                
                if let swiftMin = Range(minRange, in: timestamp),
                   let swiftSec = Range(secRange, in: timestamp) {
                    let minutes = Int(String(timestamp[swiftMin])) ?? 0
                    let seconds = Int(String(timestamp[swiftSec])) ?? 0
                    return Double(minutes * 60 + seconds)
                }
            }
        }
        
        // Try ss.ff (seconds only)
        let pattern3 = #"^(\d+)\\ .(\d{2,3})$"#
        if let regex = try? NSRegularExpression(pattern: pattern3) {
            let range = NSRange(timestamp.startIndex..., in: timestamp)
            if let match = regex.firstMatch(in: timestamp, range: range), match.numberOfRanges >= 3 {
                let secRange = match.range(at: 1)
                let msRange = match.range(at: 2)
                
                if let swiftSec = Range(secRange, in: timestamp),
                   let swiftMs = Range(msRange, in: timestamp) {
                    let seconds = Int(String(timestamp[swiftSec])) ?? 0
                    var milliseconds = Int(String(timestamp[swiftMs])) ?? 0
                    
                    while milliseconds >= 1000 {
                        milliseconds /= 10
                    }
                    
                    return Double(seconds) + Double(milliseconds) / 1000.0
                }
            }
        }
        
        // Try plain seconds
        if let seconds = Double(timestamp) {
            return seconds
        }
        
        return nil
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

// MARK: - Collection Extensions

private extension Array where Element: Hashable {
    var unique: [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
