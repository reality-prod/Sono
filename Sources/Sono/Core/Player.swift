import AVFoundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif
import SwiftUI
import Observation

enum RepeatMode { case off, all, one }

@Observable @MainActor
final class Player {
    @ObservationIgnored let av = AVPlayer()
    @ObservationIgnored var downloads: Downloads?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    var queue: [Song] = []
    var current: Song?
    var isPlaying = false
    var hasVideo = false
    var lyrics: [LyricLine] = [] {
        didSet {
            lyricTimestamps = lyrics.map(\.time)
        }
    }
    var lyricTimestamps: [Double] = []
    var lyricsOffset: Double = 0.40
    var shuffle = false
    var repeatMode: RepeatMode = .off
    var accent: Color = Theme.purple
    var sleepAt: Date?
    var client: NavidromeClient?
    var history: [Song] = (try? JSONDecoder().decode([Song].self, from: UserDefaults.standard.data(forKey: "history") ?? Data())) ?? []
    var volume: Double = 0.8 { didSet { av.volume = Float(volume) } }
    var speed: Float = 1 { didSet { av.defaultRate = speed; if isPlaying { av.rate = speed } } }
    var maxBitRate: Int = UserDefaults.standard.integer(forKey: "streamingBitrate") {
        didSet { UserDefaults.standard.set(maxBitRate, forKey: "streamingBitrate") }
    }
    var currentRadio: InternetRadioStation?

    init() { setupRemote() }

    /// Playhead read straight from AVPlayer; the lyrics view samples it every display frame.
    var time: Double { let t = av.currentTime().seconds; return t.isFinite ? t : 0 }

    func play(_ s: Song, in list: [Song]) {
        currentRadio = nil
        let url: URL
        if let l = downloads?.url(for: s.id) {
            url = l
        } else if let c = client {
            url = c.stream(s.id, maxBitRate: maxBitRate > 0 ? maxBitRate : nil)
        } else {
            return
        }
        queue = list; current = s; lyrics = []
        let item = AVPlayerItem(url: url)
        av.replaceCurrentItem(with: item); av.volume = Float(volume); av.defaultRate = speed; av.play(); isPlaying = true
        Task { hasVideo = ((try? await item.asset.loadTracks(withMediaType: .video)) ?? []).isEmpty == false }
        Task { lyrics = await Lyrics.fetch(s, client: self.client) }
        Task { accent = await ArtColor.accent(client?.cover(s.coverArt, size: 64)) ?? Theme.purple }
        Task { await client?.scrobble(s.id) }
        history = Array(([s] + history.filter { $0 != s }).prefix(100))
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "history")
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.next(auto: true) }
        }
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: s.title, MPMediaItemPropertyArtist: s.artist ?? "",
                                                           MPMediaItemPropertyPlaybackDuration: Double(s.duration ?? 0)]
        #endif
    }

    /// Streams an Internet Radio Station directly through AVPlayer.
    func playRadio(_ station: InternetRadioStation) {
        guard let url = URL(string: station.streamUrl) else { return }
        currentRadio = station
        let song = Song(
            id: "radio_\(station.id)",
            title: station.name,
            artist: "Live Internet Radio",
            album: station.homepageUrl ?? "Navidrome Radio",
            duration: 0,
            coverArt: nil,
            suffix: "stream",
            track: nil,
            year: nil
        )
        queue = [song]
        current = song
        lyrics = []
        let item = AVPlayerItem(url: url)
        av.replaceCurrentItem(with: item)
        av.volume = Float(volume)
        av.defaultRate = 1.0
        av.play()
        isPlaying = true
        accent = Theme.purple
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: station.name,
            MPMediaItemPropertyArtist: "Live Internet Radio"
        ]
        #endif
    }
    func toggle() { if isPlaying { av.pause() } else { av.play() }; isPlaying.toggle() }
    func seek(_ t: Double) { av.seek(to: CMTime(seconds: t, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) }
    func next(auto: Bool = false) {
        guard let c = current, !queue.isEmpty else { return }
        if auto && repeatMode == .one { play(c, in: queue); return }
        if shuffle, queue.count > 1, let r = queue.filter({ $0 != c }).randomElement() { play(r, in: queue); return }
        guard let i = queue.firstIndex(of: c) else { return }
        if queue.indices.contains(i + 1) { play(queue[i + 1], in: queue) }
        else if repeatMode == .all { play(queue[0], in: queue) }
        else if auto { isPlaying = false }
    }
    func previous() {
        if time > 3 { seek(0); return }
        guard let c = current, let i = queue.firstIndex(of: c), i > 0 else { return }
        play(queue[i - 1], in: queue)
    }
    func playNext(_ s: Song) {
        guard let c = current, let i = queue.firstIndex(of: c) else { play(s, in: [s]); return }
        queue.insert(s, at: i + 1)
    }
    func enqueue(_ s: Song) { if current == nil { play(s, in: [s]) } else { queue.append(s) } }
    func cycleRepeat() { repeatMode = repeatMode == .off ? .all : repeatMode == .all ? .one : .off }
    func setSleep(minutes: Int?) {
        sleepTask?.cancel(); sleepAt = nil
        guard let m = minutes else { return }
        sleepAt = Date().addingTimeInterval(Double(m) * 60)
        sleepTask = Task { try? await Task.sleep(for: .seconds(m * 60)); if !Task.isCancelled { av.pause(); isPlaying = false; sleepAt = nil } }
    }
    private func setupRemote() {
        #if canImport(MediaPlayer)
        let c = MPRemoteCommandCenter.shared()
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        #endif
    }
}
