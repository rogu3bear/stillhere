import Foundation
import Testing
@testable import StillHereCore

@Suite struct TitleExtractorTests {
    @Test func multiLineTitleIsCollapsed() throws {
        #expect(TitleExtractor.title(from: try Fixture.data("html/multiline.html")) == "Vite + React")
    }

    @Test func entitiesAreDecoded() throws {
        #expect(TitleExtractor.title(from: try Fixture.data("html/entities.html"))
            == "Node & Test — “quoted” AB &unknown; <ok>")
    }

    @Test func uppercaseTagWithAttributes() throws {
        #expect(TitleExtractor.title(from: try Fixture.data("html/uppercase.html")) == "Upper Case Title")
    }

    @Test func missingOrEmptyTitle() throws {
        #expect(TitleExtractor.title(from: try Fixture.data("html/missing.html")) == nil)
        #expect(TitleExtractor.title(from: "<title>   </title>") == nil)
        #expect(TitleExtractor.title(from: "<title>unterminated") == nil)
    }

    @Test func onlyFirst64KBIsSearched() {
        let padding = String(repeating: "x", count: TitleExtractor.maxBytes)
        #expect(TitleExtractor.title(from: Data("<html>\(padding)<title>Too late</title>".utf8)) == nil)
        let early = "<title>Early</title>" + padding
        #expect(TitleExtractor.title(from: Data(early.utf8)) == "Early")
    }

    @Test func longTitleIsTruncated() throws {
        let long = String(repeating: "a", count: 200)
        let title = try #require(TitleExtractor.title(from: "<title>\(long)</title>"))
        #expect(title.count == TitleExtractor.maxLength)
        #expect(title.hasSuffix("…"))
    }

    @Test func malformedEntitiesAreKept() {
        #expect(TitleExtractor.decodeEntities("a & b &#xZZ; &#99999999; &amp") == "a & b &#xZZ; &#99999999; &amp")
    }
}
