import SwiftUI
import NOVA

// MARK: - CounterPanelView

struct CounterPanelView: View {
    @ObservedNode var counter: NodeObserver<CounterNode>
    private let appStore: AppStore

    init(appStore: AppStore) {
        _counter     = ObservedNode(appStore.counter)
        self.appStore = appStore
    }

    // Derived synchronously from the nonisolated timeline on every render.
    // @ObservedNode already re-renders the view after each send(), so stats
    // are always fresh without a second stateStream subscription.
    private var stats: TimelineStats { appStore.timelineStats }

    var body: some View {
        VStack(spacing: 0) {
            countDisplay
            Divider().padding(.horizontal, 40)
            controlArea
            Divider().padding(.horizontal, 40)
            statsBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Count display

    private var countDisplay: some View {
        VStack(spacing: 12) {
            Text("\(counter.state.count)")
                .font(.system(size: 100, weight: .black, design: .rounded))
                .foregroundStyle(countColor)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: counter.state.count < 0))
                .animation(.spring(duration: 0.25), value: counter.state.count)
                .frame(minWidth: 200)

            if counter.state.isAtMax {
                boundaryLabel("Maximum \(counter.state.maximum) reached", color: .orange)
            } else if counter.state.isAtMin {
                boundaryLabel("Minimum \(counter.state.minimum) reached", color: .orange)
            } else {
                Text(" ").font(.caption)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(countColor.gradient)
                        .frame(width: geo.size.width * counter.state.progress)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 60)
        }
        .padding(.vertical, 32)
    }

    // MARK: Controls

    private var controlArea: some View {
        VStack(spacing: 20) {
            HStack(spacing: 32) {
                circleButton(
                    systemImage: "minus.circle.fill",
                    color: counter.state.isAtMin ? .gray : .red,
                    disabled: counter.state.isAtMin
                ) { counter.send { $0.decrement() } }

                circleButton(
                    systemImage: "arrow.counterclockwise.circle.fill",
                    color: counter.state.count == 0 ? .gray : .blue,
                    disabled: counter.state.count == 0
                ) { counter.send { $0.reset() } }

                circleButton(
                    systemImage: "plus.circle.fill",
                    color: counter.state.isAtMax ? .gray : .green,
                    disabled: counter.state.isAtMax
                ) { counter.send { $0.increment() } }
            }

            HStack(spacing: 6) {
                Text("Step")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach([1, 5, 10], id: \.self) { step in
                    stepButton(step)
                }
            }


            HStack(spacing: 12) {
                Button {
                    counter.task { await appStore.undoCounter() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!stats.canUndo)

                Button {
                    counter.task { await appStore.redoCounter() }
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!stats.canRedo)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 24)
    }

    // MARK: Stats bar

    private var statsBar: some View {
        HStack(spacing: 24) {
            statCell(label: "Operations", value: "\(stats.operationCount)")
            Divider().frame(height: 30)
            statCell(label: "Highest",    value: "\(stats.highestValue)")
            Divider().frame(height: 30)
            statCell(label: "Lowest",     value: "\(stats.lowestValue)")
            Divider().frame(height: 30)
            statCell(label: "Step",       value: "×\(counter.state.step)")
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: Helpers

    private var countColor: Color {
        let c = counter.state.count
        if c > 0 { return .green }
        if c < 0 { return .red }
        return .primary
    }

    // MARK: Sub-views

    private func circleButton(
        systemImage: String,
        color: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func stepButton(_ step: Int) -> some View {
        let isActive = counter.state.step == step
        return Button("\(step)") {
            counter.send { $0.setStep(step) }
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .accentColor : nil)
        .fontWeight(isActive ? .bold : .regular)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func boundaryLabel(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(color)
    }
}
