import Testing
@testable import DefaultApps

@MainActor
@Suite struct FileTypesTests {
    @Test func makeDropsInvalidIdentifiers() {
        #expect(FileTypes.make(from: ["not.a.type", "public.png"]).map(\.id) == ["public.png"])
    }

    @Test func makeKeepsOneTypePerNameAndExtension() {
        let types = FileTypes.make(from: ["com.apple.music.mp2", "public.mp2"])
        #expect(types.map(\.id) == ["public.mp2"])
    }

    @Test func makeSortsByName() {
        #expect(FileTypes.make(from: ["public.png", "com.compuserve.gif"]).map(\.id)
            == ["com.compuserve.gif", "public.png"])
    }

    @Test func emptyQueryReturnsAll() {
        let types = FileTypes.make(from: ["public.png", "com.compuserve.gif"])
        #expect(FileTypes.filter(types, query: "") == types)
    }

    @Test(arguments: ["gif", ".gif", "GIF"])
    func queryMatchesGif(_ query: String) {
        let types = FileTypes.make(from: ["public.png", "com.compuserve.gif"])
        #expect(FileTypes.filter(types, query: query).map(\.id) == ["com.compuserve.gif"])
    }

    @Test func queryMatchesIdentifier() {
        let types = FileTypes.make(from: ["public.png", "com.compuserve.gif"])
        #expect(FileTypes.filter(types, query: "compuserve").map(\.id) == ["com.compuserve.gif"])
    }

    @Test func unmatchedQueryReturnsEmpty() {
        let types = FileTypes.make(from: ["public.png", "com.compuserve.gif"])
        #expect(FileTypes.filter(types, query: "zzzz").isEmpty)
    }

    @Test func allContainsCuratedGifAndDeclaredExtras() {
        let all = FileTypes.all()
        #expect(all.contains { $0.id == "com.compuserve.gif" })
        #expect(all.count > 42)
    }
}
