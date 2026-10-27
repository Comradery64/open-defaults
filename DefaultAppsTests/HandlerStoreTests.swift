import Foundation
import Testing
@testable import DefaultApps

@MainActor
@Suite struct HandlerStoreTests {
    private static let gif = FileType(id: "com.compuserve.gif", name: "GIF image", ext: "gif")
    private static let png = FileType(id: "public.png", name: "PNG image", ext: "png")
    private let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
    private let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    private func makeSuite() -> UserDefaults {
        let suite = UserDefaults(suiteName: "HandlerStoreTests-\(UUID().uuidString)")!
        return suite
    }

    private func makeStore(suite: UserDefaults? = nil, fileExists: @escaping (String) -> Bool = { _ in true }) -> (HandlerStore, FakeHandlers) {
        let fake = FakeHandlers()
        fake.defaults[Self.gif.id] = preview
        fake.candidates[Self.gif.id] = [preview, textEdit]
        let store = HandlerStore(
            service: fake, types: [Self.gif, Self.png], ledger: RevertLedger(),
            defaults: suite ?? makeSuite(), fileExists: fileExists, urlForBundleID: { _ in nil }
        )
        return (store, fake)
    }

    @Test func rowsCountEqualsTypesCount() {
        let (store, _) = makeStore()
        #expect(store.rows.map(\.id) == [Self.gif.id, Self.png.id])
    }

    @Test func currentReflectsFakeDefault() throws {
        let (store, _) = makeStore()
        let gifRow = try #require(store.rows.first { $0.id == Self.gif.id })
        let pngRow = try #require(store.rows.first { $0.id == Self.png.id })
        #expect(gifRow.current?.url == preview)
        #expect(pngRow.current == nil)
    }

    @Test func refreshPicksUpChangedDefault() throws {
        let (store, fake) = makeStore()
        fake.defaults[Self.gif.id] = textEdit
        store.refresh()
        let gifRow = try #require(store.rows.first { $0.id == Self.gif.id })
        #expect(gifRow.current?.url == textEdit)
    }

    @Test func queryNarrowsVisibleRows() {
        let (store, _) = makeStore()
        store.query = "gif"
        #expect(store.visibleRows.map(\.id) == [Self.gif.id])
        store.query = ""
        #expect(store.visibleRows.count == 2)
    }

    @Test func selectionLoadsOnlySelectedCandidates() throws {
        let (store, _) = makeStore()
        store.selection = Self.gif.id
        let gifRow = try #require(store.rows.first { $0.id == Self.gif.id })
        let pngRow = try #require(store.rows.first { $0.id == Self.png.id })
        #expect(Set(gifRow.candidates.map(\.url)) == Set([preview, textEdit]))
        #expect(pngRow.candidates.isEmpty)
    }

    @Test func isCurrentMatchesByBundleIDEvenWhenURLsDiffer() {
        let current = AppInfo(url: URL(fileURLWithPath: "/Applications/Alt/Preview.app"), bundleID: "com.apple.Preview", name: "Preview")
        let row = HandlerStore.Row(type: Self.gif, current: current)
        let candidate = AppInfo(url: preview, bundleID: "com.apple.Preview", name: "Preview")
        let other = AppInfo(url: textEdit, bundleID: "com.apple.TextEdit", name: "TextEdit")
        #expect(row.isCurrent(candidate))
        #expect(!row.isCurrent(other))
    }

    @Test func refreshMovesCheckmarkToNewDefaultInSelectedCandidates() throws {
        let (store, fake) = makeStore()
        store.selection = Self.gif.id
        fake.defaults[Self.gif.id] = textEdit
        store.refresh()
        let gifRow = try #require(store.rows.first { $0.id == Self.gif.id })
        let textEditApp = try #require(gifRow.candidates.first { $0.url == textEdit })
        let previewApp = try #require(gifRow.candidates.first { $0.url == preview })
        #expect(gifRow.isCurrent(textEditApp))
        #expect(!gifRow.isCurrent(previewApp))
    }

    @Test func applySucceedsAndUpdatesCurrent() async throws {
        let (store, fake) = makeStore()
        await store.apply(AppInfo(url: textEdit), to: Self.gif.id)
        let gifRow = try #require(store.rows.first { $0.id == Self.gif.id })
        #expect(store.status[Self.gif.id] == .applied)
        #expect(gifRow.current?.url == textEdit)
        #expect(fake.setCalls.count == 1)
    }

    @Test func applyRegistersNamedUndo() async {
        let (store, _) = makeStore()
        let undoManager = UndoManager()
        await store.apply(AppInfo(url: textEdit), to: Self.gif.id, undoManager: undoManager)
        #expect(undoManager.undoActionName == "Set GIF image Default")
    }

    @Test func applyThrownErrorFailsAndLeavesCurrent() async throws {
        let (store, fake) = makeStore()
        fake.setError = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])
        await store.apply(AppInfo(url: textEdit), to: Self.gif.id)
        let gifRow = try #require(store.rows.first { $0.id == Self.gif.id })
        #expect(store.status[Self.gif.id] == .failed(.system(domain: "test", code: 7, message: "boom")))
        #expect(gifRow.current?.url == preview)
    }

    @Test func applyIgnoredSetFailsDidNotStick() async {
        let (store, fake) = makeStore()
        fake.ignoreSets = true
        await store.apply(AppInfo(url: textEdit), to: Self.gif.id)
        #expect(store.status[Self.gif.id] == .failed(.didNotStick(expected: "TextEdit", actual: "Preview")))
    }

    @Test func applyRecordsURLAndType() async {
        let (store, fake) = makeStore()
        await store.apply(AppInfo(url: textEdit), to: Self.gif.id)
        #expect(fake.setCalls.count == 1)
        #expect(fake.setCalls.first?.0 == textEdit)
        #expect(fake.setCalls.first?.1 == Self.gif.id)
    }

    @Test func applyThenRevertRestoresOriginalAndClearsLedger() async {
        let (store, fake) = makeStore()
        await store.apply(AppInfo(url: textEdit), to: Self.gif.id)
        #expect(store.ledger.original(for: Self.gif.id)?.appURL == preview)
        #expect(store.revertOffer(for: Self.gif.id) != nil)
        await store.revert(Self.gif.id)
        #expect(fake.defaults[Self.gif.id] == preview)
        #expect(store.ledger.original(for: Self.gif.id) == nil)
        #expect(store.revertOffer(for: Self.gif.id) == nil)
    }

    @Test func twoAppliesThenRevertGoesToFirstOriginal() async {
        let (store, fake) = makeStore()
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        await store.apply(AppInfo(url: textEdit), to: Self.gif.id)
        await store.apply(AppInfo(url: safari), to: Self.gif.id)
        await store.revert(Self.gif.id)
        #expect(fake.defaults[Self.gif.id] == preview)
    }

    @Test func revertWithMissingOriginalDoesNotCallSetDefault() async {
        let (store, fake) = makeStore(fileExists: { $0 != "/System/Applications/Preview.app" })
        await store.apply(AppInfo(url: textEdit), to: Self.gif.id)
        let calls = fake.setCalls.count
        await store.revert(Self.gif.id)
        #expect(fake.setCalls.count == calls)
        #expect(store.status[Self.gif.id] == .failed(.revertUnavailable(appName: "Preview")))
        #expect(store.ledger.original(for: Self.gif.id) != nil)
    }

    @Test func missingCurrentReportsNotExists() {
        let (store, fake) = makeStore()
        fake.defaults[Self.gif.id] = URL(fileURLWithPath: "/nonexistent/Gone.app")
        store.refresh()
        #expect(store.rows[0].current?.exists == false)
        #expect(AppInfo(url: preview).exists)
    }

    @Test func ledgerPersistsToInjectedSuite() async {
        let suite = makeSuite()
        let (store, _) = makeStore(suite: suite)
        await store.apply(AppInfo(url: textEdit), to: Self.gif.id)
        #expect(RevertLedger.load(from: suite).original(for: Self.gif.id)?.appURL == preview)
        await store.revert(Self.gif.id)
        #expect(RevertLedger.load(from: suite).original(for: Self.gif.id) == nil)
    }
}
