import Foundation

/// A single entry in a `Timeline`: the full state of a `Node` after one mutation.
public struct TimelineEvent<N: Node>: Sendable {
    /// Stable identifier for this event.
    public let id: UUID
    /// When the mutation was recorded.
    public let timestamp: Date
    /// The node's state immediately after the mutation completed.
    public let state: N
}
