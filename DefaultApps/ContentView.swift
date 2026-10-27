import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(HandlerStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @ScaledMetric private var headerIcon = 48.0
    @ScaledMetric private var appIcon = 24.0
    /// Side margin that keeps detail content at most 640 pt wide while the scroller stays at the window edge.
    @State private var sideMargin = 20.0
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            Group {
                if store.visibleRows.isEmpty && !store.query.isEmpty {
                    ContentUnavailableView.search(text: store.query)
                } else {
                    ScrollViewReader { proxy in
                        List(store.visibleRows, selection: $store.selection) { row in
                            TypeRow(row: row, canRevert: store.revertOffer(for: row.id) != nil)
                        }
                        .listStyle(.sidebar)
                        // Keep the selected type visible when it is set from outside the list.
                        // No anchor: scrolls only as far as needed, so clicking a visible row doesn't move the list.
                        .onChange(of: store.selection) { _, id in if let id { proxy.scrollTo(id) } }
                        // A selection restored at launch is set before the rows exist; scroll once they do.
                        .task {
                            try? await Task.sleep(for: .milliseconds(300))
                            if let id = store.selection { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let id = store.selection, let row = store.rows.first(where: { $0.id == id }) {
                detail(row)
            } else {
                ContentUnavailableView("Select a File Type", systemImage: "doc")
            }
        }
        .searchable(text: $store.query)
        .searchFocused($searchFocused)
        .onChange(of: store.searchFocusRequested) { _, new in
            if new {
                searchFocused = true
                store.searchFocusRequested = false
            }
        }
        .navigationTitle("Open Defaults")
        // User preference: no focus rings anywhere (search field, toolbar, rows).
        .focusEffectDisabled()
        .frame(minWidth: 640, minHeight: 400)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refresh()
        }
        // A system default-change dialog takes key status without deactivating the app.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            store.refresh()
            guard let window = note.object as? NSWindow else { return }
            // The Window scene doesn't restore its frame; setting the autosave name restores and then saves it.
            if window.frameAutosaveName != "MainWindow" { window.setFrameAutosaveName("MainWindow") }
            // The toolbar search field is AppKit's; .focusEffectDisabled() doesn't reach it.
            for case let item as NSSearchToolbarItem in window.toolbar?.items ?? [] {
                item.searchField.focusRingType = .none
            }
        }
        #if DEBUG
        .onAppear {
            // Screenshot seeds: -DAInitialSearch <q> -DAInitialSelection <typeId>
            if let q = UserDefaults.standard.string(forKey: "DAInitialSearch") { store.query = q }
            if let s = UserDefaults.standard.string(forKey: "DAInitialSelection") { store.selection = s }
        }
        #endif
    }

    /// A Revert-section row: app icon, action title, app name.
    private func restoreButton(_ title: String, a11y: String, hint: String? = nil, app: AppInfo, row: HandlerStore.Row, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: appIcon, height: appIcon)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(app.name).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.uturn.backward").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.status[row.id] == .applying)
        .accessibilityLabel(a11y)
        .accessibilityHint(hint ?? "")
    }

    private func detail(_ row: HandlerStore.Row) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TypeIcon(row: row, size: headerIcon)
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Text(row.type.name).font(.title2.bold())
                        if let ext = row.type.ext {
                            Text(".\(ext)").font(.title3).foregroundStyle(.secondary)
                        }
                    }
                    Text(row.type.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Line up with the grouped Form's cards (Form adds its own 20 pt inset).
            .padding(.horizontal, sideMargin + 20)
            .padding(.top)
            Form {
                ApplyStatusLine(
                    status: store.status[row.id] ?? .idle, typeName: row.type.name, appName: row.current?.name,
                    onRetry: { if let app = store.lastAttempt[row.id] { Task { await store.apply(app, to: row.id, undoManager: undoManager) } } },
                    onDismiss: { store.clearStatus(row.id) }
                )
                .id(row.id)
                if let current = row.current, !current.exists {
                    Section {
                        Label("\(current.name) was moved or deleted.", systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                }
                let apps = row.candidates.filter(\.exists)
                Section {
                    if apps.isEmpty {
                        Label("No apps on this Mac can open \(row.type.name) files.", systemImage: "questionmark.app.dashed")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(apps) { app in
                            Button {
                                Task { await store.apply(app, to: row.id, undoManager: undoManager) }
                            } label: {
                                HStack {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                        .resizable()
                                        .frame(width: appIcon, height: appIcon)
                                    Text(app.name)
                                    Spacer()
                                    if row.isCurrent(app) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(store.status[row.id] == .applying)
                            .accessibilityLabel(app.name)
                            .accessibilityAddTraits(row.isCurrent(app) ? .isSelected : [])
                        }
                    }
                } header: {
                    // On the header, not the Section: a Section label overrides every row's label.
                    Text("Open with")
                        .accessibilityLabel("Default app for \(row.type.name)")
                        .accessibilityValue(row.current?.name ?? "none")
                }
                let previous = store.previousOffer(for: row.id)
                let offer = store.revertOffer(for: row.id)
                if previous != nil || offer != nil {
                    Section("Revert") {
                        if let previous {
                            restoreButton("Restore Previous", a11y: "Restore \(row.type.name) to previous app, \(previous.name)", app: previous, row: row) {
                                await store.apply(previous, to: row.id, undoManager: undoManager)
                            }
                        }
                        switch offer {
                        case .available(let app):
                            restoreButton("Restore Original", a11y: "Revert \(row.type.name) to \(app.name)", hint: offer!.helpText, app: app, row: row) {
                                await store.revert(row.id, undoManager: undoManager)
                            }
                            .help(offer!.helpText)
                        case .missing:
                            Button {} label: {
                                HStack {
                                    Image(systemName: "questionmark.app.dashed")
                                        .frame(width: appIcon, height: appIcon)
                                    Text("Restore Original")
                                    Spacer()
                                    Image(systemName: "arrow.uturn.backward")
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(true)
                            .accessibilityLabel("Revert \(row.type.name) to original app")
                            .help(offer!.helpText)
                            .accessibilityHint(offer!.helpText)
                            Text(offer!.helpText).font(.footnote).foregroundStyle(.secondary)
                        case .noHandler:
                            Text(offer!.helpText).font(.footnote).foregroundStyle(.secondary)
                        case nil:
                            EmptyView()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .contentMargins(.horizontal, sideMargin, for: .scrollContent)
        // Fill the detail column so the margin follows the window, not the content.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: Double.self) { $0.size.width } action: { sideMargin = max(20, ($0 - 640) / 2) }
    }
}

/// D7 status, shown as its own grouped section above "Open with". "Applied" clears after 4 s;
/// the spinner shows only if applying runs past 0.5 s.
private struct ApplyStatusLine: View {
    let status: ApplyStatus
    let typeName: String
    let appName: String?
    let onRetry: () -> Void
    let onDismiss: () -> Void
    @State private var slow = false
    @State private var expired = false

    var body: some View {
        Group {
            switch status {
            case .applying:
                Section {
                    Label {
                        Text("Waiting for macOS to confirm…")
                    } icon: {
                        if slow { ProgressView().controlSize(.small) } else { Image(systemName: "clock") }
                    }
                    .foregroundStyle(.secondary)
                }
            case .applied where !expired:
                if let appName {
                    Section {
                        Label("\(typeName) files now open with \(appName).", systemImage: "checkmark.circle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                }
            case .failed(let failure):
                Section {
                    HStack {
                        Label {
                            Text(failure.message(typeName: typeName, appName: appName ?? ""))
                                .help(failure.technicalDetail ?? "")
                        } icon: {
                            Image(systemName: failure.isDeclined ? "info.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(failure.isDeclined ? Color.secondary : Color.orange)
                        }
                        Spacer()
                        if !failure.isDeclined {
                            Button("Try Again", action: onRetry)
                        }
                        Button("Dismiss", action: onDismiss)
                    }
                }
            default:
                EmptyView()
            }
        }
        .task(id: status) {
            switch status {
            case .applied:
                if let appName { AccessibilityNotification.Announcement("\(typeName) files now open with \(appName).").post() }
            case .failed(let failure):
                AccessibilityNotification.Announcement(failure.message(typeName: typeName, appName: appName ?? "")).post()
            default: break
            }
            slow = false
            expired = false
            // The task is cancelled when status changes, so a newer apply is never clobbered.
            switch status {
            case .applying:
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled { slow = true }
            case .applied:
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { expired = true }
            default:
                break
            }
        }
    }
}
