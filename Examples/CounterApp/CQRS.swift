import SECA

// MARK: - Timeline stats

/// Read-only snapshot of counter analytics derived from the Timeline.
/// Computed by `AppStore.timelineStats` — no QueryBus needed.
struct TimelineStats: Sendable {
    let operationCount: Int
    let highestValue:   Int
    let lowestValue:    Int
    let canUndo:        Bool
    let canRedo:        Bool

    static let empty = TimelineStats(
        operationCount: 0,
        highestValue:   0,
        lowestValue:    0,
        canUndo:        false,
        canRedo:        false
    )
}
