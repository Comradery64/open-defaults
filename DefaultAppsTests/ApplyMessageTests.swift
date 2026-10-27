import Foundation
import Testing
@testable import DefaultApps

@MainActor
@Suite struct ApplyMessageTests {
    private static let domain = "NSOSStatusErrorDomain"
    private let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
    private let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    @Test func systemMessageNamesTypeAndHidesDomain() {
        let text = ApplyFailure.system(domain: Self.domain, code: -50, message: "x").message(typeName: "GIF image", appName: "TextEdit")
        #expect(text.contains("GIF image"))
        #expect(!text.contains(Self.domain))
    }

    @Test func didNotStickMessageNamesTypeAndActualApp() {
        let text = ApplyFailure.didNotStick(expected: "TextEdit", actual: "Preview").message(typeName: "GIF image", appName: "TextEdit")
        #expect(text.contains("GIF image"))
        #expect(text.contains("Preview"))
        #expect(!text.contains(Self.domain))
    }

    @Test func declinedMessageNamesPreviousApp() {
        let text = ApplyFailure.declined(previous: "Preview").message(typeName: "GIF image", appName: "TextEdit")
        #expect(text.contains("Preview"))
        #expect(!text.contains(Self.domain))
    }

    @Test func declinedWithoutPreviousFallsBack() {
        let text = ApplyFailure.declined(previous: nil).message(typeName: "GIF image", appName: "TextEdit")
        #expect(text.contains("the current app"))
    }

    @Test func declinedFromMacOSPromptSetsDeclinedStatus() async {
        let fake = FakeHandlers()
        let gif = FileType(id: "com.compuserve.gif", name: "GIF image", ext: "gif")
        fake.defaults[gif.id] = preview
        let store = HandlerStore(service: fake, types: [gif])
        fake.setError = NSError(domain: NSCocoaErrorDomain, code: 256,
                                userInfo: [NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -128)])
        await store.apply(AppInfo(url: textEdit), to: gif.id)
        #expect(store.status[gif.id] == .failed(.declined(previous: "Preview")))
        store.clearStatus(gif.id)
        #expect(store.status[gif.id] == .idle)
    }
}
