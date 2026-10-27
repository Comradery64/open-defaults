import Foundation
import Testing
@testable import DefaultApps

@MainActor
@Suite struct RevertLedgerTests {
    private let preview = AppInfo(url: URL(fileURLWithPath: "/System/Applications/Preview.app"), bundleID: "com.apple.Preview", name: "Preview")
    private let textEdit = AppInfo(url: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), bundleID: "com.apple.TextEdit", name: "TextEdit")
    private let typeID = "com.compuserve.gif"

    @Test func firstChangeStoresOriginal() {
        var ledger = RevertLedger()
        ledger.recordChange(typeID: typeID, from: preview)
        #expect(ledger.original(for: typeID)?.appURL == preview.url)
        #expect(ledger.original(for: typeID)?.bundleID == "com.apple.Preview")
        #expect(ledger.original(for: typeID)?.appName == "Preview")
    }

    @Test func secondChangeKeepsFirstOriginal() {
        var ledger = RevertLedger()
        ledger.recordChange(typeID: typeID, from: preview)
        ledger.recordChange(typeID: typeID, from: textEdit)
        #expect(ledger.original(for: typeID)?.appURL == preview.url)
    }

    @Test func clearRemovesOriginal() {
        var ledger = RevertLedger()
        ledger.recordChange(typeID: typeID, from: preview)
        ledger.clear(typeID)
        #expect(ledger.original(for: typeID) == nil)
    }

    @Test func needsRevertFalseWhenCurrentMatchesOriginal() {
        var ledger = RevertLedger()
        ledger.recordChange(typeID: typeID, from: preview)
        #expect(!ledger.needsRevert(typeID: typeID, current: preview))
        #expect(ledger.needsRevert(typeID: typeID, current: textEdit))
    }

    @Test func nilAppURLOriginalRoundTrips() throws {
        var ledger = RevertLedger()
        ledger.recordChange(typeID: typeID, from: nil)
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(RevertLedger.self, from: data)
        #expect(decoded.original(for: typeID) == RevertLedger.Original(appURL: nil, bundleID: nil, appName: nil))
    }

    @Test func codableRoundTripEquals() throws {
        var ledger = RevertLedger()
        ledger.recordChange(typeID: typeID, from: preview)
        ledger.recordChange(typeID: "public.png", from: nil)
        let data = try JSONEncoder().encode(ledger)
        #expect(try JSONDecoder().decode(RevertLedger.self, from: data) == ledger)
    }

    @Test func saveThenLoadEquals() throws {
        let suite = "DefaultAppsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var ledger = RevertLedger()
        ledger.recordChange(typeID: typeID, from: preview)
        ledger.save(to: defaults)
        #expect(RevertLedger.load(from: defaults) == ledger)
    }

    @Test func corruptDataLoadsEmpty() throws {
        let suite = "DefaultAppsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: RevertLedger.defaultsKey)
        #expect(RevertLedger.load(from: defaults) == RevertLedger())
    }

    @Test func missingKeyLoadsEmpty() throws {
        let suite = "DefaultAppsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RevertLedger.load(from: defaults) == RevertLedger())
    }
}
