import Foundation
import Testing
@testable import FocusedDayPlanner

struct BackgroundAudioControllerTests {
    @Test
    func backgroundAudioVolumeNormalizationClampsValues() {
        #expect(AppSettings.normalizeBackgroundAudioVolume(-0.4) == 0)
        #expect(AppSettings.normalizeBackgroundAudioVolume(0.45) == 0.45)
        #expect(AppSettings.normalizeBackgroundAudioVolume(1.8) == 1)
    }

    @Test
    func soundEffectsCatalogHasUniqueIDsAndPixabayPages() {
        let effects = BackgroundAudioController.soundEffectsCatalog
        let ids = effects.map(\.id)

        #expect(Set(ids).count == ids.count)
        #expect(effects.count == 8)
        #expect(effects.allSatisfy { ["http", "https"].contains($0.pageURL.scheme?.lowercased() ?? "") })
        #expect(effects.allSatisfy { $0.sourceLabel == "Pixabay" })
    }

    @Test
    func scanUserTracksFiltersUnsupportedFiles() throws {
        let root = makeTemporaryDirectory()
        let userDirectory = root.appendingPathComponent("User", isDirectory: true)
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)

        let supported = userDirectory.appendingPathComponent("focus-loop.mp3")
        let unsupported = userDirectory.appendingPathComponent("notes.txt")
        try Data("test".utf8).write(to: supported)
        try Data("ignore".utf8).write(to: unsupported)

        let tracks = BackgroundAudioController.scanUserTracks(in: userDirectory)

        #expect(tracks.count == 1)
        #expect(tracks.first?.title == "focus-loop")
        #expect(tracks.first?.kind == .localTrack)
    }

    @Test
    func duplicateImportsGetDeterministicNames() throws {
        let root = makeTemporaryDirectory()
        let userDirectory = root.appendingPathComponent("User", isDirectory: true)
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)

        let original = userDirectory.appendingPathComponent("session.mp3")
        let existingDuplicate = userDirectory.appendingPathComponent("session-2.mp3")
        try Data("existing".utf8).write(to: original)
        try Data("existing-2".utf8).write(to: existingDuplicate)

        let duplicateSource = root.appendingPathComponent("session.mp3")
        let secondDuplicateSource = root.appendingPathComponent("session.mp3")
        let duplicateURL = BackgroundAudioController.uniqueImportDestination(for: duplicateSource, in: userDirectory)
        let secondURL = BackgroundAudioController.uniqueImportDestination(for: secondDuplicateSource, in: userDirectory)

        #expect(duplicateURL.lastPathComponent == "session-3.mp3")
        #expect(secondURL.lastPathComponent == "session-3.mp3")
    }

    private func makeTemporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
