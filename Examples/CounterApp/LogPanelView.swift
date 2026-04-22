import SwiftUI
import NOVA

// MARK: - LogPanelView

struct LogPanelView: View {
    @ObservedNode var log: NodeObserver<LogNode>
    private let appStore: AppStore

    init(appStore: AppStore) {
        _log          = ObservedNode(appStore.log)
        self.appStore = appStore
    }

    var body: some View {
        VStack(spacing: 0) {
            if log.state.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .navigationTitle("Event Log")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Clear") {
                    Task { await appStore.log.send { $0.clear() } }
                }
                .disabled(log.state.entries.isEmpty)
            }
        }
    }

    // MARK: Sub-views

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.clipboard")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No events yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Tap +/− to generate signals.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        List(log.state.entries.reversed()) { entry in
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(entry.kind.color)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.message)
                        .font(.system(.callout, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .listRowInsets(.init(top: 6, leading: 10, bottom: 6, trailing: 10))
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(log.state.entries.count) event\(log.state.entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
}

// MARK: - Kind → Color

extension LogNode.Entry.Kind {
    var color: Color {
        switch self {
        case .increment: .green
        case .decrement: .red
        case .reset:     .blue
        case .clamped:   .orange
        case .undo:      .purple
        case .redo:      .teal
        }
    }
}
