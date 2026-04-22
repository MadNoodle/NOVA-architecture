import Testing

// MARK: - CallCounter

/// Thread-safe call counter used across test suites.
actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
    func reset()     { value = 0 }
}

// MARK: - waitUntil

/// Polls `condition` every 5 ms until it returns `true` or `timeout` elapses.
///
/// Prefer this over `Task.yield()` chains in async tests — it is deterministic
/// under load and on all hardware, unlike cooperative-scheduling tricks.
///
/// ```swift
/// await store.send { $0.increment() }
/// await waitUntil { await logStore.state.entries.count == 1 }
/// ```
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @escaping () async -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("waitUntil: condition was not met within \(timeout)")
}
