import SwiftUI

@main
struct DefaultAppsApp: App {
    #if DEBUG
    @State private var store = HandlerStore(service: FaultyHandlers(base: WorkspaceHandlers()))
    #else
    @State private var store = HandlerStore()
    #endif

    var body: some Scene {
        Window("Open Defaults", id: "main") {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(after: .toolbar) {
                Button("Refresh") { store.refresh() }
                    .keyboardShortcut("r")
            }
            CommandGroup(after: .textEditing) {
                Button("Find") { store.searchFocusRequested = true }
                    .keyboardShortcut("f")
            }
        }
    }
}
