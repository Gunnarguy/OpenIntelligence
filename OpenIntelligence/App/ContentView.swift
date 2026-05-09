import SwiftUI

struct ContentView: View {
    @State private var selectedTab: DemoTab = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DemoOverviewView()
            }
            .tabItem {
                Label("Overview", systemImage: "sparkles.rectangle.stack")
            }
            .tag(DemoTab.overview)

            NavigationStack {
                DemoExperienceView()
            }
            .tabItem {
                Label("Experience", systemImage: "text.bubble")
            }
            .tag(DemoTab.experience)

            NavigationStack {
                DemoBoundaryView()
            }
            .tabItem {
                Label("Engine", systemImage: "cpu")
            }
            .tag(DemoTab.engine)
        }
    }
}

private enum DemoTab {
    case overview
    case experience
    case engine
}

#Preview {
    ContentView()
}
