import Foundation
import AppKit
import Observation

enum ApplyStatus: Equatable {
    case idle, applying, applied
    case failed(ApplyFailure)
}

enum ApplyFailure: Equatable {
    case system(domain: String, code: Int, message: String)
    case didNotStick(expected: String, actual: String?)
    case declined(previous: String?)
    case revertUnavailable(appName: String)

    /// D7 copy. Error domain and code stay out of the main text (see `technicalDetail`).
    func message(typeName: String, appName: String) -> String {
        switch self {
        case .system:
            "Couldn't change the default app for \(typeName). Try again, or pick a different app."
        case .didNotStick(_, let actual):
            "macOS didn't apply the change. \(typeName) still opens with \(actual ?? "another app"). Try again."
        case .declined(let previous):
            "Not changed. You chose to keep \(previous ?? "the current app") in the macOS prompt."
        case .revertUnavailable(let appName):
            "Can't revert: \(appName) is no longer on this Mac."
        }
    }

    var isDeclined: Bool {
        if case .declined = self { true } else { false }
    }

    var technicalDetail: String? {
        if case .system(let domain, let code, _) = self { "\(domain) \(code)" } else { nil }
    }
}

/// What the Revert section shows for a type whose current default differs from the ledger original.
enum RevertOffer: Equatable {
    case available(app: AppInfo)
    /// D5/D7 S4: the original app is gone (and its bundle id no longer resolves).
    case missing(appName: String)
    /// D5: there was no default app before.
    case noHandler

    /// D5/D7 copy, used for `.help`, the VoiceOver hint and the footnote.
    var helpText: String {
        switch self {
        case .available(let app):
            "Reverting sets \(app.name) again. If macOS was choosing automatically before, it will now keep \(app.name) as a fixed choice."
        case .missing(let name):
            "Can't revert: \(name) is no longer on this Mac."
        case .noHandler:
            "There was no default app before, and macOS has no public way to remove one."
        }
    }
}

@Observable
final class HandlerStore {
    struct Row: Identifiable {
        let type: FileType
        var current: AppInfo?
        var candidates: [AppInfo] = []

        var id: String { type.id }

        /// Bundle id match when both have one; otherwise compare symlink-resolved URLs.
        func isCurrent(_ app: AppInfo) -> Bool {
            guard let current else { return false }
            if let a = app.bundleID, let b = current.bundleID { return a == b }
            return app.url.resolvingSymlinksInPath().standardizedFileURL
                == current.url.resolvingSymlinksInPath().standardizedFileURL
        }
    }

    private(set) var rows: [Row]
    /// Last apply result per type id.
    private(set) var status: [String: ApplyStatus] = [:]
    /// The app the user last asked for per type id; used by "Try Again".
    private(set) var lastAttempt: [String: AppInfo] = [:]
    /// The handler before the last confirmed change per type id (session only); "Restore Previous".
    private(set) var previous: [String: AppInfo] = [:]
    var query = ""
    /// Set by the Find command; ContentView moves focus to the search field and clears it.
    var searchFocusRequested = false
    /// Selected type id. Selecting a type loads its candidates (lazy: D1).
    var selection: String? {
        didSet {
            if let selection { loadCandidates(for: selection) }
        }
    }

    /// Handler recorded before this app's first change per type (D5). Persisted per D9.
    private(set) var ledger: RevertLedger
    private let service: HandlerService
    private let types: [FileType]
    private let defaults: UserDefaults
    private let fileExists: (String) -> Bool
    private let urlForBundleID: (String) -> URL?

    var visibleRows: [Row] {
        let ids = Set(FileTypes.filter(rows.map(\.type), query: query).map(\.id))
        return rows.filter { ids.contains($0.id) }
    }

    init(
        service: HandlerService = WorkspaceHandlers(),
        types: [FileType] = FileTypes.all(),
        ledger: RevertLedger? = nil,
        defaults: UserDefaults = .standard,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        urlForBundleID: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    ) {
        self.service = service
        self.types = types
        self.defaults = defaults
        self.fileExists = fileExists
        self.urlForBundleID = urlForBundleID
        self.ledger = ledger ?? RevertLedger.load(from: defaults)
        self.rows = types.map { Row(type: $0, current: nil) }
        refresh()
    }

    /// Reads `current` for every type; re-reads candidates for the selected type only.
    func refresh() {
        for i in rows.indices { readCurrent(at: i) }
        if let selection { loadCandidates(for: selection) }
    }

    /// Re-reads `current` for one type.
    func refresh(_ typeID: String) {
        guard let i = rows.firstIndex(where: { $0.id == typeID }) else { return }
        readCurrent(at: i)
    }

    /// Sets `app` as the default for `typeID`, then re-reads the default to confirm it stuck.
    /// On success the previous handler goes into the ledger (first change wins) unless `recordsLedger`
    /// is false (revert), and an undo is registered with `undoManager`. Returns whether it stuck.
    @discardableResult
    func apply(_ app: AppInfo, to typeID: String, undoManager: UndoManager? = nil, recordsLedger: Bool = true) async -> Bool {
        guard let row = rows.first(where: { $0.id == typeID }) else { return false }
        let type = row.type.utType
        let previousApp = row.current
        let previous = previousApp?.name
        lastAttempt[typeID] = app
        status[typeID] = .applying
        do {
            try await service.setDefault(app.url, for: type)
        } catch {
            let e = error as NSError
            // userCanceled (-128) from the macOS prompt, nested in NSCocoaErrorDomain 256 (R3, R4).
            let inner = e.userInfo[NSUnderlyingErrorKey] as? NSError ?? e
            if inner.domain == NSOSStatusErrorDomain && inner.code == -128 {
                status[typeID] = .failed(.declined(previous: previous))
            } else {
                status[typeID] = .failed(.system(domain: e.domain, code: e.code, message: e.localizedDescription))
            }
            refresh(typeID)
            return false
        }
        refresh(typeID)
        let actual = rows.first { $0.id == typeID }?.current
        guard actual?.url.standardizedFileURL.path == app.url.standardizedFileURL.path else {
            status[typeID] = .failed(.didNotStick(expected: app.name, actual: actual?.name))
            return false
        }
        status[typeID] = .applied
        if let previousApp, previousApp.url.standardizedFileURL != app.url.standardizedFileURL {
            self.previous[typeID] = previousApp
        }
        if recordsLedger, previousApp?.url.standardizedFileURL != app.url.standardizedFileURL {
            ledger.recordChange(typeID: typeID, from: previousApp)
            ledger.save(to: defaults)
        }
        if let undoManager, let previousApp, previousApp.url.standardizedFileURL != app.url.standardizedFileURL {
            registerUndo(undoManager, typeID: typeID, typeName: row.type.name, restore: previousApp)
        }
        return true
    }

    /// Undo applies `restore`; that apply registers its own undo, which is redo.
    /// Apply runs after an await, outside the event's undo group, so group explicitly for the action name to stick.
    private func registerUndo(_ undoManager: UndoManager, typeID: String, typeName: String, restore: AppInfo) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { store in
            Task { @MainActor in await store.apply(restore, to: typeID, undoManager: undoManager) }
        }
        undoManager.setActionName("Set \(typeName) Default")
        undoManager.endUndoGrouping()
    }

    /// The original app for Revert: the recorded URL if it still exists, else the bundle id lookup.
    private func resolvedOriginal(_ original: RevertLedger.Original) -> AppInfo? {
        guard let url = original.appURL else { return nil }
        if fileExists(url.path) { return AppInfo(url: url) }
        if let id = original.bundleID, let found = urlForBundleID(id) { return AppInfo(url: found) }
        return nil
    }

    /// The app before the last change, if it differs from the current one and from the Revert original.
    func previousOffer(for typeID: String) -> AppInfo? {
        guard let app = previous[typeID], fileExists(app.url.path),
              let row = rows.first(where: { $0.id == typeID }), !row.isCurrent(app)
        else { return nil }
        if case .available(let original) = revertOffer(for: typeID), original.url.standardizedFileURL == app.url.standardizedFileURL {
            return nil
        }
        return app
    }

    /// nil when there is nothing to revert (no ledger original, or current already equals it).
    func revertOffer(for typeID: String) -> RevertOffer? {
        guard let original = ledger.original(for: typeID),
              ledger.needsRevert(typeID: typeID, current: rows.first { $0.id == typeID }?.current)
        else { return nil }
        guard original.appURL != nil else { return .noHandler }
        if let app = resolvedOriginal(original) { return .available(app: app) }
        return .missing(appName: original.appName ?? "The original app")
    }

    /// Restores the ledger original (D5). Never records into the ledger; clears it on success.
    func revert(_ typeID: String, undoManager: UndoManager? = nil) async {
        guard let offer = revertOffer(for: typeID) else { return }
        switch offer {
        case .noHandler:
            return
        case .missing(let name):
            status[typeID] = .failed(.revertUnavailable(appName: name))
        case .available(let app):
            if await apply(app, to: typeID, undoManager: undoManager, recordsLedger: false) {
                ledger.clear(typeID)
                ledger.save(to: defaults)
            }
        }
    }

    func clearStatus(_ typeID: String) {
        status[typeID] = .idle
    }

    private func readCurrent(at i: Int) {
        rows[i].current = service.defaultApp(for: rows[i].type.utType).map(AppInfo.init(url:))
    }

    func loadCandidates(for id: String) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        let row = rows[i]
        rows[i].candidates = CandidateRules.clean(
            service.candidates(for: row.type.utType).map(AppInfo.init(url:)),
            current: row.current
        )
    }
}
