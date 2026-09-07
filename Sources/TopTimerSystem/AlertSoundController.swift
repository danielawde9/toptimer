@preconcurrency import AppKit
import Foundation

public enum SoundFileKind: Sendable { case regular(data: Data), symbolicLink, directory, missing; var data: Data? { if case let .regular(data) = self { data } else { nil } } }
public enum AlertSoundError: Error, Sendable, Equatable, LocalizedError { case unsupportedFileType, unsafeInput, fileTooLarge, copyFailed
    public var errorDescription: String? { switch self { case .unsupportedFileType: "Choose an AIFF, WAV, CAF, or MP3 sound file."; case .unsafeInput: "Choose a regular file, not a folder or link."; case .fileTooLarge: "Sound files must be 20 MB or smaller."; case .copyFailed: "TopTimer could not import that sound." } }
}
public protocol SoundFileStore: Sendable { func kind(at url: URL) async throws -> SoundFileKind; func size(at url: URL) async throws -> Int; func applicationSupportSoundsDirectory() async throws -> URL; func copy(_ source: URL, to destination: URL) async throws }
public protocol SoundPlayer: Sendable { func play(url: URL?, volume: Double) async -> Bool }
public struct AlertSoundController: Sendable {
    public static let maximumBytes = 20_000_000
    private let files: any SoundFileStore; private let player: any SoundPlayer; private let nameGenerator: @Sendable () -> String
    public init(files: any SoundFileStore = LocalSoundFileStore(), player: any SoundPlayer = NSSoundPlayer(), nameGenerator: @escaping @Sendable () -> String = { UUID().uuidString }) { self.files = files; self.player = player; self.nameGenerator = nameGenerator }
    public func importSound(from source: URL) async throws -> URL {
        guard Self.extensions.contains(source.pathExtension.lowercased()) else { throw AlertSoundError.unsupportedFileType }
        guard case .regular = try await files.kind(at: source) else { throw AlertSoundError.unsafeInput }
        guard try await files.size(at: source) <= Self.maximumBytes else { throw AlertSoundError.fileTooLarge }
        let destination = try await files.applicationSupportSoundsDirectory().appendingPathComponent(nameGenerator()).appendingPathExtension(source.pathExtension.lowercased())
        do { try await files.copy(source, to: destination); return destination } catch { throw AlertSoundError.copyFailed }
    }
    public func play(customSound: URL?, volume: Double) async { let clamped = min(1, max(0, volume)); if let customSound, await player.play(url: customSound, volume: clamped) { return }; _ = await player.play(url: nil, volume: clamped) }
    private static let extensions: Set<String> = ["aiff", "wav", "caf", "mp3"]
}
public actor LocalSoundFileStore: SoundFileStore {
    public init() {}
    public func kind(at url: URL) async throws -> SoundFileKind { let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]); if values.isSymbolicLink == true { return .symbolicLink }; return values.isRegularFile == true ? .regular(data: Data()) : .missing }
    public func size(at url: URL) async throws -> Int { let values = try url.resourceValues(forKeys: [.fileSizeKey]); return values.fileSize ?? 0 }
    public func applicationSupportSoundsDirectory() async throws -> URL { let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true); let directory = base.appendingPathComponent("TopTimer/Sounds", isDirectory: true); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory }
    public func copy(_ source: URL, to destination: URL) async throws { try FileManager.default.copyItem(at: source, to: destination) }
}
public actor NSSoundPlayer: SoundPlayer {
    public init() {}
    public func play(url: URL?, volume: Double) async -> Bool {
        await MainActor.run {
            let customSound = url.flatMap { NSSound(contentsOf: $0, byReference: true) }
            let sound = customSound ?? (url == nil ? NSSound(named: "Glass") : nil)
            guard let sound else { return false }
            sound.volume = Float(volume)
            return sound.play()
        }
    }
}
