import AVFAudio
import CryptoKit
import Foundation

public enum NotificationSoundError: Error, Equatable, Sendable, LocalizedError {
  case invalidIdentity, unsupportedAudio, capacityReached, cleanupFailed
  public var errorDescription: String? {
    switch self {
    case .invalidIdentity: "Choose an available alert sound."
    case .unsupportedAudio:
      "Notification sounds must contain 1 to 30 seconds of mono or stereo audio."
    case .capacityReached: "The notification sound cache is full."
    case .cleanupFailed: "Could not clean up temporary notification audio."
    }
  }
}

public enum AlertSoundIdentity {
  public static func sourceURL(name: String, importedDirectory: URL? = nil) throws -> URL {
    guard !name.isEmpty, name.count <= 128, !name.contains("/"), !name.contains("\\"), name != ".",
      name != ".."
    else { throw NotificationSoundError.invalidIdentity }
    if (name as NSString).pathExtension.isEmpty {
      return URL(fileURLWithPath: "/System/Library/Sounds").appendingPathComponent(name + ".aiff")
    }
    let base =
      try importedDirectory
      ?? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
      ).appendingPathComponent("TopTimer/Sounds")
    return base.appendingPathComponent(name)
  }
}

/// Stages immutable PCM CAF files where UserNotifications actually searches.
/// Input is copied through the existing no-follow, exclusive, 20 MB file boundary.
public actor LocalNotificationSoundPreparer {
  private let importedDirectory: URL?
  private let notificationDirectory: URL?
  private var preparationsInProgress = 0
  public init(importedDirectory: URL? = nil, notificationDirectory: URL? = nil) {
    self.importedDirectory = importedDirectory
    self.notificationDirectory = notificationDirectory
  }
  public func prepare(name: String?) async throws -> String? {
    guard let name else { return nil }
    let source = try AlertSoundIdentity.sourceURL(name: name, importedDirectory: importedDirectory)
    let directory =
      try notificationDirectory
      ?? FileManager.default.url(
        for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("Sounds")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let identity = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
    let destination = directory.appendingPathComponent("TopTimer-\(identity).caf")
    if FileManager.default.fileExists(atPath: destination.path) {
      let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true else {
        throw AlertSoundError.unsafeInput
      }
      return destination.lastPathComponent
    }
    try checkCapacity(directory)
    preparationsInProgress += 1
    defer { preparationsInProgress -= 1 }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopTimer-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    do {
      let input = temporary.appendingPathComponent("input").appendingPathExtension(
        source.pathExtension)
      try await LocalSoundFileStore().importRegularFile(
        from: source, to: input, maximumBytes: AlertSoundController.maximumBytes)
      let output = temporary.appendingPathComponent("output.caf")
      try Self.convert(input: input, output: output)
      try FileManager.default.moveItem(at: output, to: destination)
    } catch {
      do { try FileManager.default.removeItem(at: temporary) } catch {
        throw NotificationSoundError.cleanupFailed
      }
      throw error
    }
    do { try FileManager.default.removeItem(at: temporary) } catch {
      throw NotificationSoundError.cleanupFailed
    }
    return destination.lastPathComponent
  }
  private func checkCapacity(_ directory: URL) throws {
    guard
      let items = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
    else { throw NotificationSoundError.capacityReached }
    var count = preparationsInProgress
    guard count < 100 else { throw NotificationSoundError.capacityReached }
    for _ in 0..<1_000 {
      guard let item = items.nextObject() as? URL else { return }
      if item.lastPathComponent.hasPrefix("TopTimer-") { count += 1 }
      guard count < 100 else { throw NotificationSoundError.capacityReached }
    }
    throw NotificationSoundError.capacityReached
  }
  private static func convert(input: URL, output: URL) throws {
    let reader = try AVAudioFile(forReading: input)
    let format = reader.processingFormat
    guard reader.length > 0, format.sampleRate > 0, format.sampleRate <= 192_000,
      format.channelCount >= 1, format.channelCount <= 2,
      Double(reader.length) / format.sampleRate <= 30,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096)
    else { throw NotificationSoundError.unsupportedAudio }
    var settings = format.settings
    settings[AVLinearPCMIsNonInterleaved] = false
    let writer = try AVAudioFile(forWriting: output, settings: settings)
    let chunks = Int((reader.length + 4_095) / 4_096)
    for _ in 0..<chunks {
      try reader.read(into: buffer)
      try writer.write(from: buffer)
    }
  }
}
