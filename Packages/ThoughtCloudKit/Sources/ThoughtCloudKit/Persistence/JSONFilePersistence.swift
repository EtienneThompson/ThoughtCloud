import Foundation

/// Stores the whole library as one JSON document, written atomically.
/// The previous version is kept as `library-backup.json`.
public final class JSONFilePersistence: LibraryPersisting {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("library.json") }
    public var backupURL: URL { directory.appendingPathComponent("library-backup.json") }

    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/ThoughtCloud`, excluded from nothing: it is included in device backups.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ThoughtCloud", isDirectory: true)
    }

    public func load() throws -> LibrarySnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .empty }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder.library.decode(LibrarySnapshot.self, from: data)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let quarantine = directory.appendingPathComponent("library-corrupt-\(stamp).json")
            try fileManager.moveItem(at: fileURL, to: quarantine)
            throw PersistenceError.corruptFileQuarantined(quarantine)
        }
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.library.encode(snapshot)
        if fileManager.fileExists(atPath: fileURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) { try fileManager.removeItem(at: backupURL) }
            try fileManager.copyItem(at: fileURL, to: backupURL)
        }
        try data.write(to: fileURL, options: [.atomic])
    }
}
