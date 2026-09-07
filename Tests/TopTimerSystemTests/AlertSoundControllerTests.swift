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
}

actor SoundFileStoreSpy: SoundFileStore {
    let files: [String: SoundFileKind]; let sizes: [String: Int]
    var copies: [(URL, URL)] = []
    init(files: [String: SoundFileKind], sizes: [String: Int] = [:]) { self.files = files; self.sizes = sizes }
    func kind(at url: URL) async throws -> SoundFileKind { files[url.lastPathComponent] ?? .missing }
    func size(at url: URL) async throws -> Int { sizes[url.lastPathComponent] ?? (files[url.lastPathComponent]?.data?.count ?? 0) }
    func applicationSupportSoundsDirectory() async throws -> URL { URL(fileURLWithPath: "/sounds") }
    func copy(_ source: URL, to destination: URL) async throws { copies.append((source, destination)) }
}
actor SoundPlayerSpy: SoundPlayer {
    let customResult: Bool; var volumes: [Double] = []; var played: [URL?] = []
    init(customResult: Bool = true) { self.customResult = customResult }
    func play(url: URL?, volume: Double) async -> Bool { volumes.append(volume); played.append(url); return url == nil || customResult }
}
func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure @escaping () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async { do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) } catch {} }
