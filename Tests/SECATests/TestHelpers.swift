/// Thread-safe call counter used across test suites.
actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
    func reset()     { value = 0 }
}
