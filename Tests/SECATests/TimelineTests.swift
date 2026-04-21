import Testing
import Foundation
@testable import SECA

// MARK: - Fixture

@Node
private struct ScoreNode {
    enum Signal: SECA.Signal { case changed(Int) }
    var score = 0
    mutating func add(_ n: Int) { score += n; emit(.changed(score)) }
    mutating func reset()       { score = 0 }
}

// MARK: - Timeline recording

@Suite("Timeline — recording")
struct TimelineRecordingTests {

    @Test("timeline is empty before any send")
    func emptyBeforeSend() async {
        let store = NodeStore<ScoreNode>()
        #expect(store.timeline.count == 0)
        #expect(store.timeline.canUndo == false)
        #expect(store.timeline.canRedo == false)
    }

    @Test("each send appends one event")
    func eachSendAppendsEvent() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(10) }
        await store.send { $0.add(5) }
        #expect(store.timeline.count == 2)
    }

    @Test("recorded state matches node state after mutation")
    func recordedStateMatchesNodeState() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(42) }
        let events = store.timeline.events
        #expect(events.last?.state.score == 42)
        #expect(await store.state.score == 42)
    }
}

// MARK: - Undo / Redo

@Suite("Timeline — undo / redo")
struct TimelineUndoRedoTests {

    @Test("undo restores previous state")
    func undoRestoresPrevious() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(10) }   // score = 10
        await store.send { $0.add(5) }    // score = 15

        await store.undo()
        #expect(await store.state.score == 10)
    }

    @Test("undo when nothing to undo is a no-op")
    func undoAtBeginningIsNoOp() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(7) }
        await store.undo()                // back to first event
        await store.undo()                // nothing before first — no-op
        #expect(await store.state.score == 0)
    }

    @Test("redo re-applies after undo")
    func redoReApplies() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(10) }   // score = 10
        await store.send { $0.add(5) }    // score = 15

        await store.undo()                // score = 10
        await store.redo()               // score = 15
        #expect(await store.state.score == 15)
    }

    @Test("redo when nothing to redo is a no-op")
    func redoAtEndIsNoOp() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(3) }
        await store.redo()               // nothing to redo
        #expect(await store.state.score == 3)
    }

    @Test("canUndo / canRedo reflect cursor position")
    func canUndoCanRedoFlags() async {
        let store = NodeStore<ScoreNode>()
        #expect(store.timeline.canUndo == false)
        #expect(store.timeline.canRedo == false)

        await store.send { $0.add(1) }
        await store.send { $0.add(2) }
        #expect(store.timeline.canUndo == true)
        #expect(store.timeline.canRedo == false)

        await store.undo()
        #expect(store.timeline.canUndo == true)   // can still undo to genesis
        #expect(store.timeline.canRedo == true)
    }

    @Test("new mutation after undo discards redo branch")
    func newMutationDiscardsRedo() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(10) }   // event 0
        await store.send { $0.add(5) }    // event 1

        await store.undo()               // cursor → 0
        await store.send { $0.add(99) }  // event 1 (replaces old branch)

        #expect(store.timeline.count == 2)
        #expect(store.timeline.canRedo == false)
        #expect(await store.state.score == 109)  // 10 + 99
    }
}

// MARK: - Replay

@Suite("Timeline — replay")
struct TimelineReplayTests {

    @Test("replay(to:) restores state at that point in time")
    func replayToDate() async {
        let store = NodeStore<ScoreNode>()

        await store.send { $0.add(10) }
        let checkpoint = Date()
        try? await Task.sleep(nanoseconds: 1_000_000)  // 1 ms gap
        await store.send { $0.add(50) }
        await store.send { $0.add(100) }

        await store.replay(to: checkpoint)
        #expect(await store.state.score == 10)
    }

    @Test("replay(to:) does not affect undo stack")
    func replayDoesNotAffectUndoStack() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(10) }
        await store.send { $0.add(20) }
        let countBefore = store.timeline.count

        await store.replay(to: Date())
        #expect(store.timeline.count == countBefore)
    }

    @Test("replay before any event is a no-op")
    func replayBeforeAnyEvent() async {
        let store = NodeStore<ScoreNode>()
        let past = Date(timeIntervalSince1970: 0)
        await store.send { $0.add(5) }
        await store.replay(to: past)
        #expect(await store.state.score == 5)  // unchanged
    }
}

// MARK: - Capacity eviction

@Suite("Timeline — capacity")
struct TimelineCapacityTests {

    @Test("events are evicted when maxCapacity is exceeded")
    func evictsOldestWhenFull() async {
        let store = NodeStore<ScoreNode>(maxTimelineCapacity: 3)
        await store.send { $0.add(1) }
        await store.send { $0.add(2) }
        await store.send { $0.add(3) }
        await store.send { $0.add(4) }  // should evict the first event
        #expect(store.timeline.count == 3)
        // Oldest surviving event should be the second one (score = 3)
        #expect(store.timeline.events.first?.state.score == 3)
    }

    @Test("undo still works correctly after eviction")
    func undoAfterEviction() async {
        let store = NodeStore<ScoreNode>(maxTimelineCapacity: 2)
        await store.send { $0.add(10) }  // evicted once capacity is exceeded
        await store.send { $0.add(20) }
        await store.send { $0.add(30) }  // capacity = 2; first event (score=10) evicted
        #expect(store.timeline.count == 2)
        await store.undo()
        #expect(await store.state.score == 30)  // back to score before add(30)
    }

    @Test("unlimited capacity when maxCapacity is 0")
    func unlimitedCapacity() async {
        let store = NodeStore<ScoreNode>(maxTimelineCapacity: 0)
        for i in 1...1000 { await store.send { $0.add(i) } }
        #expect(store.timeline.count == 1000)
    }
}

// MARK: - Replay cursor

@Suite("Timeline — replay cursor")
struct TimelineReplayCursorTests {

    @Test("replay(to:) moves undo/redo cursor to the replayed event")
    func replayMovesCursor() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(10) }   // event 0 — score = 10
        let mark = Date()
        try? await Task.sleep(nanoseconds: 1_000_000)
        await store.send { $0.add(20) }   // event 1 — score = 30
        await store.send { $0.add(30) }   // event 2 — score = 60

        // Replay to between event 0 and 1
        await store.replay(to: mark)
        #expect(await store.state.score == 10)

        // Cursor should now be at event 0 — redo brings us to event 1
        #expect(store.timeline.canRedo == true)
        await store.redo()
        #expect(await store.state.score == 30)
    }

    @Test("undo after replay reflects the replayed position")
    func undoAfterReplay() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(5) }
        let mark = Date()
        try? await Task.sleep(nanoseconds: 1_000_000)
        await store.send { $0.add(10) }

        await store.replay(to: mark)  // cursor → event 0 (score = 5)
        #expect(await store.state.score == 5)

        // undo from event 0 → genesis
        await store.undo()
        #expect(await store.state.score == 0)
        #expect(store.timeline.canUndo == false)
    }
}

// MARK: - Snapshot

@Suite("Timeline — snapshot")
struct TimelineSnapshotTests {

    @Test("snapshot captures all events")
    func snapshotCapturesAll() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(1) }
        await store.send { $0.add(2) }
        await store.send { $0.add(3) }

        let snap = store.timeline.snapshot()
        #expect(snap.count == 3)
        #expect(snap.latest?.score == 6)
    }

    @Test("snapshot.state(at:) returns correct historical state")
    func snapshotStateAt() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(10) }
        let mark = Date()
        try? await Task.sleep(nanoseconds: 1_000_000)
        await store.send { $0.add(90) }

        let snap = store.timeline.snapshot()
        #expect(snap.state(at: mark)?.score == 10)
        #expect(snap.latest?.score == 100)
    }

    @Test("snapshot is independent of subsequent mutations")
    func snapshotIsImmutable() async {
        let store = NodeStore<ScoreNode>()
        await store.send { $0.add(5) }
        let snap = store.timeline.snapshot()

        await store.send { $0.add(5) }  // after snapshot
        #expect(snap.count == 1)        // snapshot unchanged
        #expect(store.timeline.count == 2)
    }
}
