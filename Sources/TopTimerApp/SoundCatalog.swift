import Combine
import Foundation

@MainActor public final class SoundCatalogState: ObservableObject {
  @Published public private(set) var catalog: SoundCatalog = .builtIn
  @Published public private(set) var error: String?
  public init() {}
  public func refresh(load: () throws -> SoundCatalog = { try SoundCatalog.local() }) {
    do {
      catalog = try load()
      error = nil
    } catch { self.error = "Could not load alert sounds. Your previous selection is unchanged." }
  }
}

public struct SoundCatalog: Equatable, Sendable {
  public let names: [String]
  public init(names: [String]) {
    self.names = Array(Set(names.filter { !$0.isEmpty }.prefix(100)).sorted())
  }
  public static let builtIn = SoundCatalog(names: [
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr",
    "Sosumi", "Submarine", "Tink",
  ])

  /// Enumerates at most 200 direct children; identities are the imported file
  /// basenames already used by the sound importer, never arbitrary paths.
  public static func local(importedDirectory: URL? = nil) throws -> SoundCatalog {
    let base =
      try importedDirectory
      ?? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
      ).appendingPathComponent("TopTimer/Sounds")
    guard FileManager.default.fileExists(atPath: base.path) else { return .builtIn }
    guard
      let enumerator = FileManager.default.enumerator(
        at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
    else { throw CocoaError(.fileReadUnknown) }
    var names = builtIn.names
    for _ in 0..<200 {
      guard names.count < 100, let url = enumerator.nextObject() as? URL else { break }
      let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard metadata.isRegularFile == true, metadata.isSymbolicLink != true,
        ["aiff", "wav", "caf", "mp3"].contains(url.pathExtension.lowercased())
      else { continue }
      names.append(url.lastPathComponent)
    }
    return SoundCatalog(names: names)
  }
}
