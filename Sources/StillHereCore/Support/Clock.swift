import Foundation

/// Source of the current wall-clock time, injectable for deterministic tests.
public protocol NowProvider: Sendable {
    var now: Date { get }
}

public struct SystemNow: NowProvider {
    public init() {}
    public var now: Date { Date() }
}

public struct FixedNow: NowProvider {
    public var now: Date
    public init(_ now: Date) { self.now = now }
}
