import AVFoundation
import AppKit
import Foundation

enum AudioLibraryItemKind: String {
    case soundEffect
    case localTrack
}

struct AudioLibraryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let kind: AudioLibraryItemKind
    let localFileURL: URL?
}

struct SoundEffectDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let pageURL: URL
    let sourceLabel: String
}

@MainActor
final class BackgroundAudioController: NSObject, ObservableObject {
    @Published private(set) var localTracks: [AudioLibraryItem] = []
    @Published private(set) var soundEffects: [SoundEffectDefinition] = BackgroundAudioController.soundEffectsCatalog
    @Published private(set) var soundEffectLevels: [String: Double] = [:]
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var masterVolume: Double
    @Published var statusMessage = "Mix rain, wind, leaves, waves, and restaurant ambience."

    private let fileManager: FileManager
    private let session: URLSession
    private let rootDirectoryURL: URL
    private var hasLoadedLibrary = false
    private var playersByID: [String: AVAudioPlayer] = [:]
    private var preparationTasks: [String: Task<Void, Never>] = [:]
    private var resolvedDownloadURLs: [String: URL] = [:]

    nonisolated static let supportedAudioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif"]

    init(
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        rootDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.session = session
        self.rootDirectoryURL = rootDirectoryURL ?? Self.defaultRootDirectory(fileManager: fileManager)
        self.masterVolume = AppSettings.backgroundAudioMasterVolume
        super.init()
    }

    var audioLibraryDirectoryURL: URL {
        rootDirectoryURL
    }

    var userLibraryDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("User", isDirectory: true)
    }

    var curatedLibraryDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("Curated", isDirectory: true)
    }

    var activeEffects: [SoundEffectDefinition] {
        soundEffects.filter { mixLevel(for: $0.id) > 0.001 }
    }

    var activeSoundCount: Int {
        activeEffects.count
    }

    func loadLibrary() {
        try? ensureDirectories()
        localTracks = Self.scanUserTracks(in: userLibraryDirectoryURL, fileManager: fileManager)

        for effect in soundEffects where soundEffectLevels[effect.id] == nil {
            soundEffectLevels[effect.id] = 0
        }

        hasLoadedLibrary = true
        refreshPlaybackState()
    }

    func loadLibraryIfNeeded() {
        guard !hasLoadedLibrary else { return }
        loadLibrary()
    }

    func mixLevel(for effectID: String) -> Double {
        AppSettings.normalizeBackgroundAudioVolume(soundEffectLevels[effectID] ?? 0)
    }

    func setMixLevel(for effectID: String, value: Double) {
        loadLibraryIfNeeded()
        let normalized = AppSettings.normalizeBackgroundAudioVolume(value)
        soundEffectLevels[effectID] = normalized
        syncPlaybackForCurrentMix()
    }

    func toggleSoundEffect(_ effectID: String) {
        loadLibraryIfNeeded()

        if mixLevel(for: effectID) > 0.001 {
            soundEffectLevels[effectID] = 0
            syncPlaybackForCurrentMix()
            return
        }

        let currentlyActive = soundEffects.filter { mixLevel(for: $0.id) > 0.001 }
        let newShare = 1.0 / Double(currentlyActive.count + 1)

        for effect in currentlyActive {
            soundEffectLevels[effect.id] = newShare
        }
        soundEffectLevels[effectID] = newShare
        syncPlaybackForCurrentMix()
    }

    func togglePlayback() {
        loadLibraryIfNeeded()

        if isPlaying {
            stopPlaybackPreservingMix()
            statusMessage = "Paused the current sound mix."
            return
        }

        guard activeSoundCount > 0 else { return }
        syncPlaybackForCurrentMix()
        if activeSoundCount > 0 {
            statusMessage = "Resumed your sound mix."
        }
    }

    func pause() {
        guard isPlaying || !playersByID.isEmpty || !preparationTasks.isEmpty else { return }
        stopPlaybackPreservingMix()
        statusMessage = "Paused the current sound mix."
    }

    private func stopPlaybackPreservingMix() {
        for (_, task) in preparationTasks {
            task.cancel()
        }
        preparationTasks.removeAll()

        for (_, player) in playersByID {
            player.stop()
        }
        playersByID.removeAll()
        isLoading = false
        isPlaying = false
    }

    func setMasterVolume(_ value: Double) {
        masterVolume = AppSettings.normalizeBackgroundAudioVolume(value)
        AppSettings.backgroundAudioMasterVolume = masterVolume
        applyMasterVolume()
        refreshPlaybackState()
    }

    func importUserAudioFiles(from urls: [URL]) {
        guard !urls.isEmpty else { return }

        do {
            try ensureDirectories()
            var importedCount = 0
            for url in urls where Self.isSupportedAudioFile(url) {
                let destination = Self.uniqueImportDestination(
                    for: url,
                    in: userLibraryDirectoryURL,
                    fileManager: fileManager
                )
                try fileManager.copyItem(at: url, to: destination)
                importedCount += 1
            }

            loadLibrary()
            statusMessage = importedCount > 0
                ? "Imported \(importedCount) audio file\(importedCount == 1 ? "" : "s")."
                : "No supported audio files were imported."
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func openEffectsCacheFolder() {
        NSWorkspace.shared.open(curatedLibraryDirectoryURL)
    }

    func cachedFileURL(for effect: SoundEffectDefinition) -> URL {
        curatedLibraryDirectoryURL
            .appendingPathComponent(effect.id, isDirectory: false)
            .appendingPathExtension("mp3")
    }

    nonisolated static func scanUserTracks(in directory: URL, fileManager: FileManager = .default) -> [AudioLibraryItem] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter(isSupportedAudioFile)
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map {
                AudioLibraryItem(
                    id: "local:\($0.lastPathComponent.lowercased())",
                    title: $0.deletingPathExtension().lastPathComponent,
                    subtitle: $0.lastPathComponent,
                    kind: .localTrack,
                    localFileURL: $0
                )
            }
    }

    nonisolated static func isSupportedAudioFile(_ url: URL) -> Bool {
        supportedAudioExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static func uniqueImportDestination(for sourceURL: URL, in directory: URL, fileManager: FileManager = .default) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let updatedName = "\(baseName)-\(suffix)"
            candidate = directory.appendingPathComponent(updatedName).appendingPathExtension(ext)
            suffix += 1
        }

        return candidate
    }

    nonisolated static func defaultRootDirectory(fileManager: FileManager = .default) -> URL {
        if let storeDirectory = PersistenceController.storeDirectoryURL() {
            return storeDirectory.appendingPathComponent("AudioLibrary", isDirectory: true)
        }

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("FocusedDayPlanner", isDirectory: true)
            .appendingPathComponent("AudioLibrary", isDirectory: true)
    }

    nonisolated static let soundEffectsCatalog: [SoundEffectDefinition] = [
        SoundEffectDefinition(
            id: "walking-leaves",
            title: "Walking on Leaves",
            subtitle: "Crunchy footsteps through dry leaves.",
            pageURL: URL(string: "https://pixabay.com/sound-effects/nature-walking-on-leaves-260279/")!,
            sourceLabel: "Pixabay"
        ),
        SoundEffectDefinition(
            id: "wind-window-frame",
            title: "Whistling Wind",
            subtitle: "Wind whistling through a window frame.",
            pageURL: URL(string: "https://pixabay.com/sound-effects/nature-wind-whistling-window-frame-70595/")!,
            sourceLabel: "Pixabay"
        ),
        SoundEffectDefinition(
            id: "thunderstorm",
            title: "Thunderstorm",
            subtitle: "Distant storm energy and rolling thunder.",
            pageURL: URL(string: "https://pixabay.com/sound-effects/nature-thunderstorm-14708/")!,
            sourceLabel: "Pixabay"
        ),
        SoundEffectDefinition(
            id: "leaves-rustling",
            title: "Leaves Rustling",
            subtitle: "Soft leaves moving in the breeze.",
            pageURL: URL(string: "https://pixabay.com/sound-effects/nature-leaves-rustling-14633/")!,
            sourceLabel: "Pixabay"
        ),
        SoundEffectDefinition(
            id: "calming-rain",
            title: "Calming Rain",
            subtitle: "Steady rain for deep focus.",
            pageURL: URL(string: "https://pixabay.com/sound-effects/nature-calming-rain-257596/")!,
            sourceLabel: "Pixabay"
        ),
        SoundEffectDefinition(
            id: "ocean-waves",
            title: "Ocean Waves",
            subtitle: "Soothing waves rolling in and out.",
            pageURL: URL(string: "https://pixabay.com/sound-effects/nature-soothing-ocean-waves-372489/")!,
            sourceLabel: "Pixabay"
        ),
        SoundEffectDefinition(
            id: "restaurant-ambience",
            title: "Busy Restaurant",
            subtitle: "Dining room chatter and indoor restaurant energy.",
            pageURL: URL(string: "https://pixabay.com/sound-effects/city-busy-restaurant-dining-room-ambience-128466/")!,
            sourceLabel: "Pixabay"
        )
    ]

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: userLibraryDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: curatedLibraryDirectoryURL, withIntermediateDirectories: true)
    }

    private func syncPlaybackForCurrentMix() {
        let effectsToPlay = activeEffects
        let activeIDs = Set(effectsToPlay.map(\.id))

        for (id, player) in playersByID where !activeIDs.contains(id) {
            player.stop()
            playersByID[id] = nil
            preparationTasks[id]?.cancel()
            preparationTasks[id] = nil
        }

        for effect in effectsToPlay {
            if let player = playersByID[effect.id] {
                player.volume = Float(mixLevel(for: effect.id) * masterVolume)
                if !player.isPlaying {
                    player.play()
                }
            } else if preparationTasks[effect.id] == nil {
                preparationTasks[effect.id] = Task { [weak self] in
                    await self?.prepareAndStart(effect)
                }
            }
        }

        applyMasterVolume()
        refreshPlaybackState()
    }

    private func prepareAndStart(_ effect: SoundEffectDefinition) async {
        defer {
            preparationTasks[effect.id] = nil
            refreshPlaybackState()
        }

        do {
            let fileURL = try await preparedFileURL(for: effect)
            if Task.isCancelled { return }

            guard mixLevel(for: effect.id) > 0.001 else { return }

            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.numberOfLoops = -1
            player.prepareToPlay()
            player.volume = Float(mixLevel(for: effect.id) * masterVolume)
            playersByID[effect.id] = player
            player.play()
            statusMessage = "Mixing \(activeSoundCount) sound effect\(activeSoundCount == 1 ? "" : "s")."
        } catch {
            soundEffectLevels[effect.id] = 0
            statusMessage = "Unable to load \(effect.title): \(error.localizedDescription)"
        }
    }

    private func preparedFileURL(for effect: SoundEffectDefinition) async throws -> URL {
        let destination = cachedFileURL(for: effect)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        let downloadURL = try await resolveDownloadURL(for: effect)
        let request = URLRequest(url: downloadURL)
        let (temporaryURL, _) = try await session.download(for: request)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func resolveDownloadURL(for effect: SoundEffectDefinition) async throws -> URL {
        if let cached = resolvedDownloadURLs[effect.id] {
            return cached
        }

        var request = URLRequest(url: effect.pageURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard var html = String(data: data, encoding: .utf8) else {
            throw AudioDownloadError.unreadablePage
        }

        html = html.replacingOccurrences(of: "\\/", with: "/")

        let patterns = [
            #"https://cdn\.pixabay\.com/download/audio/[^"' <]+\.mp3(?:\?[^"' <]+)?"#,
            #"https://cdn\.pixabay\.com/audio/[^"' <]+\.mp3(?:\?[^"' <]+)?"#
        ]

        for pattern in patterns {
            if let match = html.range(of: pattern, options: .regularExpression) {
                let urlString = String(html[match])
                if let resolvedURL = URL(string: urlString) {
                    resolvedDownloadURLs[effect.id] = resolvedURL
                    return resolvedURL
                }
            }
        }

        throw AudioDownloadError.downloadURLNotFound
    }

    private func applyMasterVolume() {
        for effect in soundEffects {
            guard let player = playersByID[effect.id] else { continue }
            player.volume = Float(mixLevel(for: effect.id) * masterVolume)
        }
    }

    private func refreshPlaybackState() {
        let loadingNow = !preparationTasks.isEmpty
        let playingNow = !playersByID.isEmpty || loadingNow
        isLoading = loadingNow
        isPlaying = playingNow
        if loadingNow {
            statusMessage = "Loading \(activeSoundCount) sound effect\(activeSoundCount == 1 ? "" : "s")."
        } else if playingNow {
            statusMessage = "Mixing \(activeSoundCount) sound effect\(activeSoundCount == 1 ? "" : "s")."
        } else if activeSoundCount > 0 {
            statusMessage = "Mix paused. Your tile percentages are preserved."
        } else {
            statusMessage = "Choose a few tiles to build a background mix."
        }
    }
}

extension BackgroundAudioController {
    enum AudioDownloadError: LocalizedError {
        case unreadablePage
        case downloadURLNotFound

        var errorDescription: String? {
            switch self {
            case .unreadablePage:
                return "The Pixabay page could not be read."
            case .downloadURLNotFound:
                return "A downloadable audio file could not be found on the Pixabay page."
            }
        }
    }
}
