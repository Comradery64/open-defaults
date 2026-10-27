import Foundation
import UniformTypeIdentifiers
@testable import DefaultApps

/// In-memory HandlerService. Never touches NSWorkspace; setDefault only records and updates the dictionary.
@MainActor
final class FakeHandlers: HandlerService {
    var defaults: [String: URL] = [:]
    var candidates: [String: [URL]] = [:]
    var setError: Error?
    var setCalls: [(URL, String)] = []
    /// When true, setDefault succeeds but leaves `defaults` unchanged (the write did not stick).
    var ignoreSets = false

    func defaultApp(for type: UTType) -> URL? {
        defaults[type.identifier]
    }

    func candidates(for type: UTType) -> [URL] {
        candidates[type.identifier] ?? []
    }

    func setDefault(_ app: URL, for type: UTType) async throws {
        setCalls.append((app, type.identifier))
        if let setError { throw setError }
        if !ignoreSets { defaults[type.identifier] = app }
    }
}
