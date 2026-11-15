import Foundation

/// Seam over "now" so time-dependent behaviour is testable.
public protocol DateProviding: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public func now() -> Date { Date() }
}
