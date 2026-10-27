import AppKit
import Foundation
import UniformTypeIdentifiers

struct AppInfo: Identifiable, Hashable {
    let url: URL
    let bundleID: String?
    let name: String
    /// Whether the bundle is still on disk (S4); re-read on every refresh.
    let exists: Bool

    var id: URL { url }

    init(url: URL, bundleID: String?, name: String, exists: Bool = true) {
        self.url = url
        self.bundleID = bundleID
        self.name = name
        self.exists = exists
    }

    init(url: URL) {
        let display = FileManager.default.displayName(atPath: url.path)
        self.init(
            url: url,
            bundleID: Bundle(url: url)?.bundleIdentifier,
            name: display.hasSuffix(".app") ? String(display.dropLast(4)) : display,
            exists: FileManager.default.fileExists(atPath: url.path)
        )
    }
}

@MainActor
protocol HandlerService {
    func defaultApp(for type: UTType) -> URL?
    func candidates(for type: UTType) -> [URL]
    func setDefault(_ app: URL, for type: UTType) async throws
}

@MainActor
struct WorkspaceHandlers: HandlerService {
    func defaultApp(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    func candidates(for type: UTType) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: type)
    }

    func setDefault(_ app: URL, for type: UTType) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }
}

enum CandidateRules {
    /// The real user home (not the sandbox container that NSHomeDirectory() returns under App Sandbox).
    static let realHome = String(cString: getpwuid(getuid())!.pointee.pw_dir)

    /// D2: drop missing paths, hide stale copies, dedupe by bundle id (preferred install locations
    /// first, then shortest path), always keep `current`, sort by name.
    static func clean(
        _ apps: [AppInfo],
        current: AppInfo?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        home: String = realHome
    ) -> [AppInfo] {
        let preferred = ["/Applications/", "/System/Applications/", home + "/Applications/", "/System/Library/", "/Library/"]
        let libraryPrefix = home + "/Library/"

        func isStale(_ path: String) -> Bool {
            path.split(separator: "/").contains { $0.hasPrefix(".") }
                || path.hasPrefix(libraryPrefix)
                || path.contains("/DerivedData/")
        }
        func key(_ app: AppInfo) -> String {
            app.bundleID ?? app.url.resolvingSymlinksInPath().path
        }
        func rank(_ app: AppInfo) -> (Int, Int) {
            let path = app.url.path
            return (preferred.contains { path.hasPrefix($0) } ? 0 : 1, path.count)
        }

        var winners: [String: AppInfo] = [:]
        for app in apps where fileExists(app.url.path) && !isStale(app.url.path) {
            let k = key(app)
            if let existing = winners[k], rank(existing) <= rank(app) { continue }
            winners[k] = app
        }

        var result = Array(winners.values)
        if let current {
            let k = key(current)
            result.removeAll { key($0) == k }
            result.append(current)
        }
        return result.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame
                ? $0.url.path < $1.url.path
                : order == .orderedAscending
        }
    }
}

#if DEBUG
/// Debug-only fault injection: `-DAFault setFails` makes `setDefault` throw a non-cancel error.
@MainActor
struct FaultyHandlers: HandlerService {
    let base: HandlerService

    func defaultApp(for type: UTType) -> URL? { base.defaultApp(for: type) }
    func candidates(for type: UTType) -> [URL] { base.candidates(for: type) }

    func setDefault(_ app: URL, for type: UTType) async throws {
        if UserDefaults.standard.string(forKey: "DAFault") == "setFails" {
            throw NSError(domain: "DefaultApps.Fault", code: 1, userInfo: [NSLocalizedDescriptionKey: "Injected failure"])
        }
        try await base.setDefault(app, for: type)
    }
}
#endif
