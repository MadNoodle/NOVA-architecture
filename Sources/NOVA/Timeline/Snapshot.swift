import Foundation

/// An immutable export of a `Timeline`'s history at a given instant.
///
/// Use snapshots for debugging, persistence, or sharing with external systems:
///
/// ```swift
/// let snap = store.timeline.snapshot()
/// print(snap.count)          // total mutations
/// print(snap.latest?.count)  // most recent state
///
/// // Find the state at a specific date
/// let past = snap.state(at: someDate)
/// ```
public struct Snapshot<N: Node>: Sendable {

    /// All events captured in this snapshot, in chronological order.
    public let events: [TimelineEvent<N>]

    /// When this snapshot was taken.
    public let exportedAt: Date

    /// Total number of recorded mutations.
    public var count: Int { events.count }

    /// The most recent node state in this snapshot, or `nil` if empty.
    public var latest: N? { events.last?.state }

    /// Returns the state of the most recent event recorded at or before `date`,
    /// or `nil` if no event precedes that date.
    public func state(at date: Date) -> N? {
        events.last(where: { $0.timestamp <= date })?.state
    }

    init(events: [TimelineEvent<N>]) {
        self.events  = events
        self.exportedAt = Date()
    }
}
