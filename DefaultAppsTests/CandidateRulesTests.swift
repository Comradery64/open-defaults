import Foundation
import Testing
@testable import DefaultApps

@MainActor
@Suite struct CandidateRulesTests {
    private let home = "/Users/t"

    private func app(_ path: String, bid: String? = "com.example.foo", name: String = "Foo") -> AppInfo {
        AppInfo(url: URL(fileURLWithPath: path), bundleID: bid, name: name)
    }

    private func clean(_ apps: [AppInfo], current: AppInfo? = nil, exists: @escaping (String) -> Bool = { _ in true }) -> [AppInfo] {
        CandidateRules.clean(apps, current: current, fileExists: exists, home: home)
    }

    @Test func duplicatesOfOneBundleIDCollapseToOne() {
        let result = clean([
            app("/Users/t/Downloads/Foo.app"),
            app("/Applications/Foo.app"),
            app("/Volumes/Ext/Foo.app"),
        ])
        #expect(result.count == 1)
    }

    @Test func applicationsCopyWinsOverVolumes() {
        let result = clean([app("/Volumes/Ext/Foo.app"), app("/Applications/Foo.app")])
        #expect(result.map(\.url.path) == ["/Applications/Foo.app"])
    }

    @Test func libraryCopyIsHidden() {
        let result = clean([
            app("/Applications/Chromium.app", bid: "org.chromium.Chromium", name: "Chromium"),
            app("/Users/t/Library/Caches/x/Chromium.app", bid: "org.chromium.Chromium", name: "Chromium"),
        ])
        #expect(result.map(\.url.path) == ["/Applications/Chromium.app"])
    }

    @Test func dotDirectoryCopyIsHidden() {
        #expect(clean([app("/Users/t/.cache/x/Foo.app")]).isEmpty)
    }

    @Test func missingPathIsDropped() {
        let result = clean([app("/Applications/Gone.app"), app("/Applications/Here.app", bid: "com.example.here")]) {
            $0 != "/Applications/Gone.app"
        }
        #expect(result.map(\.url.path) == ["/Applications/Here.app"])
    }

    @Test func currentIsPresentEvenIfMissingFromInput() {
        let current = app("/Applications/Gone.app")
        let result = clean([], current: current) { _ in false }
        #expect(result == [current])
    }

    @Test func currentReplacesOtherCopyWithSameBundleID() {
        let current = app("/Volumes/Ext/Foo.app")
        let result = clean([app("/Applications/Foo.app")], current: current)
        #expect(result == [current])
    }

    @Test func resultIsSortedByName() {
        let result = clean([
            app("/Applications/beta.app", bid: "b", name: "beta"),
            app("/Applications/Alpha.app", bid: "a", name: "Alpha"),
            app("/Applications/gamma.app", bid: "g", name: "gamma"),
        ])
        #expect(result.map(\.name) == ["Alpha", "beta", "gamma"])
    }

    @Test func emptyInputWithNilCurrentIsEmpty() {
        #expect(clean([]).isEmpty)
    }
}
