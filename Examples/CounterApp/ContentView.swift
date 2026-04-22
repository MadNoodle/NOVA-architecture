import SwiftUI
import NOVA

struct ContentView: View {
    @Store var appStore: AppStore

    var body: some View {
        NavigationSplitView {
            LogPanelView(appStore: appStore)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            CounterPanelView(appStore: appStore)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
