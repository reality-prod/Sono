import AVFoundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif
import SwiftUI
import Observation

// MARK: - Repeat Mode

enum RepeatMode: Int, Codable {
    case off
    case all
    case one
}

// MARK: - Player Class

@Observable @MainActor
final class Player {
    @ObservationIgnored let av = AVPlayer()
    @ObservationIgnored var downloads: Downloads?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryAttempts: Int = 0
    @ObservationIgnored private var lastRecoveryTime: Date? = nil
    @ObservationIgnored private var currentItemURL: URL? = nil
    
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
    
    // Audio format info
    var currentBitRate: Int? = nil
    var currentAudioFormat: String? = nil
    
    // MARK: - Persistent Playback State
    
    struct PlaybackState: Codable {
        let currentSongId: String?
        let queueIds: [String]
        let currentTime: Double
        let isPlaying: Bool
        let shuffle: Bool
        let repeatMode: RepeatMode
        let volume: Double
        let speed: Float
    }
    
    private static let playbackStateKey = "playbackState"
    
    init() { 
        setupRemote()
        setupNotifications()
        restorePlaybackState()
    }
    
    deinit {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let timeObs = timeObserver {
            av.removeTimeObserver(timeObs)
        }
    }

    /// Playhead read straight from AVPlayer; the lyrics view samples it every display frame.
    var time: Double { 
        let t = av.currentTime().seconds
        return t.isFinite ? t : 0 
    }

    // MARK: - Playback State Persistence
    
    private func savePlaybackState() {
        let state = PlaybackState(
            currentSongId: current?.id,
            queueIds: queue.map(\.id),
            currentTime: time,
            isPlaying: isPlaying,
            shuffle: shuffle,
            repeatMode: repeatMode,
            volume: volume,
            speed: speed
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Player.playbackStateKey)
        }
    }
    
    private func restorePlaybackState() {
        guard let data = UserDefaults.standard.data(forKey: Player.playbackStateKey),
              let state = try? JSONDecoder().decode(PlaybackState.self, from: data) else {
            return
        }
        
        // Restore basic state
        shuffle = state.shuffle
        repeatMode = state.repeatMode
        volume = state.volume
        speed = state.speed
        isPlaying = state.isPlaying
        
        // Restore queue and current track if possible
        if !state.queueIds.isEmpty {
            // We need the actual Song objects to restore properly
            // This will be handled by the app state when it loads the library
        }
    }
    
    func clearPlaybackState() {
        UserDefaults.standard.removeObject(forKey: Player.playbackStateKey)
    }
    
    // MARK: - Playback
    
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
        
        currentItemURL = url
        queue = list
        current = s
        lyrics = []
        
        let item = AVPlayerItem(url: url)
        av.replaceCurrentItem(with: item)
        av.volume = Float(volume)
        av.defaultRate = speed
        av.play()
        isPlaying = true
        
        Task { hasVideo = ((try? await item.asset.loadTracks(withMediaType: .video)) ?? []).isEmpty == false }
        Task { lyrics = await Lyrics.fetch(s, client: self.client) }
        Task { accent = await ArtColor.accent(client?.cover(s.coverArt, size: 64)) ?? Theme.purple }
        Task { await client?.scrobble(s.id) }
        
        // Update history
        history = Array(([s] + history.filter { $0 != s }).prefix(100))
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "history")
        
        // Setup end observer
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, 
            object: item, 
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next(auto: true) }
        }
        
        // Setup playback stall and failure observers
        setupPlayerItemObservers(item)
        
        // Update audio format info
        Task { await updateAudioFormatInfo() }
        
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: s.title, 
            MPMediaItemPropertyArtist: s.artist ?? "",
            MPMediaItemPropertyPlaybackDuration: Double(s.duration ?? 0)
        ]
        #endif
    }
    
    private func setupPlayerItemObservers(_ item: AVPlayerItem) {
        // Observe playback stall
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, 
            object: item, 
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handlePlaybackStall(notification) }
        }
        
        // Observe playback failure
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, 
            object: item, 
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handlePlaybackFailure(notification) }
        }
        
        // Observe new access log entry (for format detection)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry, 
            object: item, 
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.updateAudioFormatInfo()
            }
        }
    }
    
    private func handlePlaybackStall(_ notification: Notification) {
        guard let playerItem = notification.object as? AVPlayerItem else { return }
        
        // Check if we can recover
        if let error = playerItem.error {
            handlePlaybackError(error)
            return
        }
        
        // Try to recover by seeking to current time
        let currentTime = av.currentTime()
        if currentTime.isValid {
            av.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
            av.play()
        } else {
            // Try to recreate the player item
            recoverStream()
        }
    }
    
    private func handlePlaybackFailure(_ notification: Notification) {
        guard let _ = notification.object as? AVPlayerItem else { return }
        
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            handlePlaybackError(error)
        } else {
            // Try to recover
            recoverStream()
        }
    }
    
    private func handlePlaybackError(_ error: Error) {
        let nsError = error as NSError
        
        // Don't retry for certain errors
        let unrecoverableCodes: [Int] = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotConnectToHost
        ]
        
        if unrecoverableCodes.contains(nsError.code) {
            // Network-related error, try recovery
            recoverStream()
            return
        }
        
        // For other errors, log and try recovery
        recoverStream()
    }
    
    private func recoverStream() {
        // Rate limit recovery attempts
        let now = Date()
        if let last = lastRecoveryTime, now.timeIntervalSince(last) < 5.0 {
            return // Don't retry too quickly
        }
        
        lastRecoveryTime = now
        recoveryAttempts += 1
        
        // Limit total recovery attempts
        guard recoveryAttempts <= 3 else {
            recoveryAttempts = 0
            return
        }
        
        // Try to re-create the player item with the same URL
        guard let url = currentItemURL else { return }
        
        let newItem = AVPlayerItem(url: url)
        av.replaceCurrentItem(with: newItem)
        
        if isPlaying {
            av.play()
        }
        
        // Setup observers for the new item
        if let currentItem = av.currentItem {
            setupPlayerItemObservers(currentItem)
        }
        
        // Reset recovery counter after successful recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            self?.recoveryAttempts = 0
        }
    }
    
    private func updateAudioFormatInfo() async {
        guard let currentItem = av.currentItem else { return }
        
        // Get audio format from tracks
        if let audioTrack = currentItem.tracks.first(where: { $0.assetTrack?.mediaType == .audio }) {
            if #available(macOS 13.0, *) {
                // Use async loading for modern macOS
                if let assetTrack = audioTrack.assetTrack {
                    do {
                        let formatDescriptions = try await assetTrack.load(.formatDescriptions)
                        if let firstDesc = formatDescriptions.first {
                            let audioFormat = CMFormatDescriptionGetMediaSubType(firstDesc)
                            currentAudioFormat = FourCharCode(audioFormat).string
                        }
                    } catch {
                        // Fallback to string description
                        currentAudioFormat = assetTrack.debugDescription
                    }
                }
            } else {
                // Fallback for older macOS
                currentAudioFormat = audioTrack.debugDescription
            }
        }
        
        // Get bitrate from asset
        if let asset = currentItem.asset as? AVURLAsset {
            do {
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                if let firstAudioTrack = audioTracks.first {
                    let estimatedBitRate = try await firstAudioTrack.load(.estimatedDataRate)
                    currentBitRate = estimatedBitRate > 0 ? Int(estimatedBitRate / 1000) : nil
                }
            } catch {
                currentBitRate = nil
            }
        }
    }

    /// Streams an Internet Radio Station directly through AVPlayer.
    func playRadio(_ station: InternetRadioStation) {
        guard let url = URL(string: station.streamUrl) else { return }
        currentRadio = station
        currentItemURL = url
        
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
        
        setupPlayerItemObservers(item)
    }
    
    // MARK: - Transport Controls
    
    func toggle() { 
        if isPlaying { 
            av.pause() 
        } else { 
            av.play() 
        }
        isPlaying.toggle()
    }
    
    func seek(_ t: Double) { 
        av.seek(to: CMTime(seconds: t, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
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
    
    // MARK: - Queue Management
    
    func playNext(_ s: Song) {
        guard let c = current, let i = queue.firstIndex(of: c) else { play(s, in: [s]); return }
        queue.insert(s, at: i + 1)
    }
    
    func enqueue(_ s: Song) { 
        if current == nil { play(s, in: [s]) } else { queue.append(s) } 
    }
    
    func removeFromQueue(_ s: Song) {
        queue.removeAll { $0.id == s.id }
        if current?.id == s.id {
            // If current song was removed, play next
            if !queue.isEmpty {
                play(queue[0], in: queue)
            } else {
                current = nil
                isPlaying = false
                av.pause()
            }
        }
    }
    
    func clearQueue() {
        queue.removeAll()
        current = nil
        isPlaying = false
        av.pause()
        av.replaceCurrentItem(with: nil)
        currentItemURL = nil
    }
    
    func reorderQueue(from sourceIndices: Set<Int>, to destinationIndex: Int) {
        var newQueue = queue
        let itemsToMove = sourceIndices.map { queue[$0] }
        newQueue.remove(atOffsets: IndexSet(sourceIndices))
        newQueue.insert(contentsOf: itemsToMove, at: destinationIndex)
        queue = newQueue
    }
    
    func cycleRepeat() { 
        repeatMode = repeatMode == .off ? .all : repeatMode == .all ? .one : .off 
    }
    
    func setSleep(minutes: Int?) {
        sleepTask?.cancel()
        sleepAt = nil
        guard let m = minutes else { return }
        sleepAt = Date().addingTimeInterval(Double(m) * 60)
        sleepTask = Task { 
            try? await Task.sleep(for: .seconds(m * 60)) 
            if !Task.isCancelled { 
                av.pause() 
                isPlaying = false 
                sleepAt = nil 
            } 
        } 
    }
    
    private func setupRemote() {
        #if canImport(MediaPlayer)
        let c = MPRemoteCommandCenter.shared()
        c.togglePlayPauseCommand.addTarget { [weak self] _ in 
            Task { @MainActor in self?.toggle() } 
            return .success 
        }
        c.nextTrackCommand.addTarget { [weak self] _ in 
            Task { @MainActor in self?.next() } 
            return .success 
        }
        c.previousTrackCommand.addTarget { [weak self] _ in 
            Task { @MainActor in self?.previous() } 
            return .success 
        }
        #endif
    }
    
    private func setupNotifications() {
        // Observe when player finishes playing an item
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                // Only handle if it's our current item
                if notification.object as? AVPlayerItem == self?.av.currentItem {
                    self?.next(auto: true)
                }
            }
        }
        
        // Observe when playback starts
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Save state when user seeks
            Task { @MainActor in
                await self?.savePlaybackState()
            }
        }
    }
}

// MARK: - FourCharCode Extension

private extension FourCharCode {
    var string: String {
        let chars = String(format: "%c%c%c%c", 
                          (self >> 24) & 0xFF, 
                          (self >> 16) & 0xFF, 
                          (self >> 8) & 0xFF, 
                          self & 0xFF)
        return chars
    }
}
