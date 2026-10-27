import Foundation

/// Per-type record of the handler that was in place before this app's first change to that type.
struct RevertLedger: Codable, Equatable {
    struct Original: Codable, Equatable {
        let appURL: URL?
        let bundleID: String?
        let appName: String?
    }

    private(set) var originals: [String: Original] = [:]

    /// First change wins: an existing original is never overwritten.
    mutating func recordChange(typeID: String, from previous: AppInfo?) {
        guard originals[typeID] == nil else { return }
        originals[typeID] = Original(appURL: previous?.url, bundleID: previous?.bundleID, appName: previous?.name)
    }

    func original(for typeID: String) -> Original? {
        originals[typeID]
    }

    mutating func clear(_ typeID: String) {
        originals[typeID] = nil
    }

    func needsRevert(typeID: String, current: AppInfo?) -> Bool {
        guard let original = originals[typeID] else { return false }
        return original.appURL?.standardizedFileURL != current?.url.standardizedFileURL
    }

    static let defaultsKey = "revertLedger"

    static func load(from defaults: UserDefaults = .standard) -> RevertLedger {
        guard let data = defaults.data(forKey: defaultsKey),
              let ledger = try? JSONDecoder().decode(RevertLedger.self, from: data)
        else { return RevertLedger() }
        return ledger
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
