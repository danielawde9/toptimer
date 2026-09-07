@preconcurrency import AppKit
import Foundation
import Darwin

public enum SoundFileKind: Sendable { case regular(data: Data), symbolicLink, directory, missing; var data: Data? { if case let .regular(data) = self { data } else { nil } } }
public enum AlertSoundError: Error, Sendable, Equatable, LocalizedError { case unsupportedFileType, unsafeInput, fileTooLarge, inspectionFailed, soundsDirectoryUnavailable, copyFailed, cleanupFailed(original: String)
    public var errorDescription: String? { switch self { case .unsupportedFileType: "Choose an AIFF, WAV, CAF, or MP3 sound file."; case .unsafeInput: "Choose a regular file, not a folder or link."; case .fileTooLarge: "Sound files must be 20 MB or smaller."; case .inspectionFailed: "TopTimer could not inspect that sound file."; case .soundsDirectoryUnavailable: "TopTimer could not prepare its sounds folder."; case .copyFailed: "TopTimer could not import that sound."; case .cleanupFailed: "TopTimer could not remove an incomplete imported sound." } }
}
public protocol SoundFileStore: Sendable { func applicationSupportSoundsDirectory() async throws -> URL; func importRegularFile(from source: URL, to destination: URL, maximumBytes: Int) async throws }
public protocol SoundPlayer: Sendable { func play(url: URL?, volume: Double) async -> Bool }
public struct AlertSoundController: Sendable {
    public static let maximumBytes = 20_000_000
    private let files: any SoundFileStore; private let player: any SoundPlayer; private let nameGenerator: @Sendable () -> String
    public init(files: any SoundFileStore = LocalSoundFileStore(), player: any SoundPlayer = NSSoundPlayer(), nameGenerator: @escaping @Sendable () -> String = { UUID().uuidString }) { self.files = files; self.player = player; self.nameGenerator = nameGenerator }
    public func importSound(from source: URL) async throws -> URL {
        guard Self.extensions.contains(source.pathExtension.lowercased()) else { throw AlertSoundError.unsupportedFileType }
        let directory: URL
        do { directory = try await files.applicationSupportSoundsDirectory() } catch { throw AlertSoundError.soundsDirectoryUnavailable }
        let destination = directory.appendingPathComponent(nameGenerator()).appendingPathExtension(source.pathExtension.lowercased())
        do { try await files.importRegularFile(from: source, to: destination, maximumBytes: Self.maximumBytes); return destination } catch let error as AlertSoundError { throw error } catch { throw AlertSoundError.copyFailed }
    }
    public func play(customSound: URL?, volume: Double) async { let clamped = min(1, max(0, volume)); if let customSound, await player.play(url: customSound, volume: clamped) { return }; _ = await player.play(url: nil, volume: clamped) }
    private static let extensions: Set<String> = ["aiff", "wav", "caf", "mp3"]
}
public actor LocalSoundFileStore: SoundFileStore {
    private let readFailureAfterBytes: Int?
    public init() { self.readFailureAfterBytes = nil }
    init(readFailureAfterBytes: Int?) { self.readFailureAfterBytes = readFailureAfterBytes }
    public func applicationSupportSoundsDirectory() async throws -> URL { let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true); let directory = base.appendingPathComponent("TopTimer/Sounds", isDirectory: true); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory }
    public func importRegularFile(from source: URL, to destination: URL, maximumBytes: Int) async throws {
        let sourceFD = open(source.path, O_RDONLY | O_NOFOLLOW)
        guard sourceFD >= 0 else { throw AlertSoundError.unsafeInput }
        defer { close(sourceFD) }
        var metadata = stat()
        guard fstat(sourceFD, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG else { throw AlertSoundError.unsafeInput }
        guard metadata.st_size <= off_t(maximumBytes) else { throw AlertSoundError.fileTooLarge }
        var destinationFD = open(destination.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard destinationFD >= 0 else { throw AlertSoundError.copyFailed }
        do {
            let bufferSize = 65_536
            var total = 0
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while true {
                let count = read(sourceFD, &buffer, bufferSize)
                guard count >= 0 else { throw AlertSoundError.inspectionFailed }
                if count == 0 { break }
                guard total + count <= maximumBytes else { throw AlertSoundError.fileTooLarge }
                if let readFailureAfterBytes, total + count > readFailureAfterBytes { throw AlertSoundError.inspectionFailed }
                total += count
                var written = 0
                while written < count {
                    let result = buffer.withUnsafeBytes { write(destinationFD, $0.baseAddress!.advanced(by: written), count - written) }
                    guard result > 0 else { throw AlertSoundError.copyFailed }
                    written += result
                }
            }
            guard close(destinationFD) == 0 else { throw AlertSoundError.copyFailed }
            destinationFD = -1
        } catch {
            if destinationFD >= 0 { _ = close(destinationFD); destinationFD = -1 }
            guard unlink(destination.path) == 0 else { throw AlertSoundError.cleanupFailed(original: error.localizedDescription) }
            throw error
        }
    }
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
