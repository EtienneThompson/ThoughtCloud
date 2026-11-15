import Foundation

/// Where the library lives. The app uses a JSON file on device; tests and
/// previews use memory. No servers involved.
public protocol LibraryPersisting: AnyObject {
    func load() throws -> LibrarySnapshot
    func save(_ snapshot: LibrarySnapshot) throws
}

public enum PersistenceError: Error, Equatable, LocalizedError {
    /// The file could not be read. It was moved aside (never deleted) to `URL`.
    case corruptFileQuarantined(URL)

    public var errorDescription: String? {
        switch self {
        case .corruptFileQuarantined(let url):
            "Your saved data couldn't be read. It was kept as \(url.lastPathComponent) and the app started fresh."
        }
    }
}

public final class InMemoryPersistence: LibraryPersisting {
    public private(set) var snapshot: LibrarySnapshot
    public init(_ snapshot: LibrarySnapshot = .empty) { self.snapshot = snapshot }
    public func load() throws -> LibrarySnapshot { snapshot }
    public func save(_ snapshot: LibrarySnapshot) throws { self.snapshot = snapshot }
}
