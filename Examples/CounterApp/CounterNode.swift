import SECA

// MARK: - CounterNode

/// Business logic for a bounded integer counter with configurable step size.
@Node
struct CounterNode {
    enum Signal: SECA.Signal {
        case incremented(Int)   // emitted after a successful increment
        case decremented(Int)   // emitted after a successful decrement
        case reset              // emitted when reset to 0
        case clamped(to: Int)  // emitted when a mutation was blocked by a boundary
    }

    var count   = 0
    var step    = 1
    var minimum = -50
    var maximum =  50

    // MARK: Mutations

    mutating func increment() {
        let next = count + step
        if next > maximum {
            count = maximum
            emit(.clamped(to: maximum))
        } else {
            count = next
            emit(.incremented(count))
        }
    }

    mutating func decrement() {
        let next = count - step
        if next < minimum {
            count = minimum
            emit(.clamped(to: minimum))
        } else {
            count = next
            emit(.decremented(count))
        }
    }

    mutating func reset() {
        count = 0
        emit(.reset)
    }

    mutating func setStep(_ newStep: Int) {
        step = newStep
    }

    // MARK: Derived state (no mutations, no emits)

    var isAtMax: Bool { count >= maximum }
    var isAtMin: Bool { count <= minimum }

    /// Progress fraction in [0, 1] relative to [minimum, maximum].
    var progress: Double {
        let range = Double(maximum - minimum)
        guard range > 0 else { return 0.5 }
        return Double(count - minimum) / range
    }
}
