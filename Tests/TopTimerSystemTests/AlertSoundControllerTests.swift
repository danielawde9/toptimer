import XCTest
@testable import TopTimerSystem

final class AlertSoundControllerTests: XCTestCase {
    func testImportRejectsUnsafeExtensionAndLargeFiles() async throws {
        let files = SoundFileStoreSpy(files: ["bad.txt": .regular(data: Data()), "large.wav": .regular(data: Data(repeating: 0, count: 1))], sizes: ["large.wav": 20_000_001])
        let controller = AlertSoundController(files: files, player: SoundPlayerSpy())
        await XCTAssertThrowsErrorAsync(try await controller.importSound(from: URL(fileURLWithPath: "/bad.txt")))
        await XCTAssertThrowsErrorAsync(try await controller.importSound(from: URL(fileURLWithPath: "/large.wav")))
    }
    func testImportUsesGeneratedNameAndPlaybackFallsBackWithClampedVolume() async throws {
        let files = SoundFileStoreSpy(files: ["ok.WAV": .regular(data: Data([1]))])
        let player = SoundPlayerSpy(customResult: false)
        let controller = AlertSoundController(files: files, player: player, nameGenerator: { "stable" })
        let imported = try await controller.importSound(from: URL(fileURLWithPath: "/ok.WAV"))
        XCTAssertEqual(imported.lastPathComponent, "stable.wav")
        await controller.play(customSound: imported, volume: 4)
        let volumes = await player.volumes
        let played = await player.played
        XCTAssertEqual(volumes, [1, 1])
        XCTAssertEqual(played, [imported, nil])
    }
    func testFilesystemFailuresBecomeTypedErrors() async throws {
        let source = URL(fileURLWithPath: "/ok.wav")
        for failure in ["directory", "copy"] {
            let files = SoundFileStoreSpy(files: ["ok.wav": .regular(data: Data())], failure: failure)
            let controller = AlertSoundController(files: files, player: SoundPlayerSpy())
            do { _ = try await controller.importSound(from: source); XCTFail("Expected typed error") }
            catch let error as AlertSoundError { XCTAssertFalse(error.localizedDescription.isEmpty) }
            catch { XCTFail("Expected AlertSoundError") }
        }
    }
    func testLocalStoreRejectsSymlinkAndNeverOverwritesDestination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.wav")
        let link = directory.appendingPathComponent("link.wav")
        let destination = directory.appendingPathComponent("destination.wav")
        try Data([1, 2, 3]).write(to: source)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let store = LocalSoundFileStore()
        await XCTAssertThrowsErrorAsync(try await store.importRegularFile(from: link, to: destination, maximumBytes: 20_000_000))
        try Data([9]).write(to: destination)
        await XCTAssertThrowsErrorAsync(try await store.importRegularFile(from: source, to: destination, maximumBytes: 20_000_000))
        XCTAssertEqual(try Data(contentsOf: destination), Data([9]))
    }

    func testLocalStoreAcceptsExactLimitAndRejectsOverLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exact = directory.appendingPathComponent("exact.wav")
        let over = directory.appendingPathComponent("over.wav")
        try Data(repeating: 1, count: 20_000_000).write(to: exact)
        try Data(repeating: 1, count: 20_000_001).write(to: over)
        let store = LocalSoundFileStore()
        try await store.importRegularFile(from: exact, to: directory.appendingPathComponent("copied.wav"), maximumBytes: 20_000_000)
        await XCTAssertThrowsErrorAsync(try await store.importRegularFile(from: over, to: directory.appendingPathComponent("too-big.wav"), maximumBytes: 20_000_000))
    }
}

actor SoundFileStoreSpy: SoundFileStore {
    let files: [String: SoundFileKind]; let sizes: [String: Int]
    var copies: [(URL, URL)] = []
    let failure: String?
    init(files: [String: SoundFileKind], sizes: [String: Int] = [:], failure: String? = nil) { self.files = files; self.sizes = sizes; self.failure = failure }
    func applicationSupportSoundsDirectory() async throws -> URL { if failure == "directory" { throw CocoaError(.fileNoSuchFile) }; return URL(fileURLWithPath: "/sounds") }
    func importRegularFile(from source: URL, to destination: URL, maximumBytes: Int) async throws {
        if failure == "copy" { throw CocoaError(.fileWriteUnknown) }
        guard case .regular = files[source.lastPathComponent] ?? .missing else { throw AlertSoundError.unsafeInput }
        guard sizes[source.lastPathComponent] ?? 0 <= maximumBytes else { throw AlertSoundError.fileTooLarge }
        copies.append((source, destination))
    }
}
actor SoundPlayerSpy: SoundPlayer {
    let customResult: Bool; var volumes: [Double] = []; var played: [URL?] = []
    init(customResult: Bool = true) { self.customResult = customResult }
    func play(url: URL?, volume: Double) async -> Bool { volumes.append(volume); played.append(url); return url == nil || customResult }
}
func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure @escaping () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async { do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) } catch {} }
