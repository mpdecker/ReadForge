import Testing
import Foundation
@testable import ReadForge

@MainActor
struct CacheManagerTests {
    // Regression test: `cacheSectionData` used to JSON-encode the whole `[SectionData]` array
    // (every section's raw+clean text for a document) in one blob — CLAUDE.md: "Store raw and
    // clean text per section separately. Never load a full document into memory." Now each
    // section is stored under its own cache key; this confirms the round trip still works.
    @Test func sectionDataRoundTripsThroughPerSectionStorage() async throws {
        let cache = CacheManager()
        let documentId = UUID()
        let sections = (0..<5).map { i in
            SectionData(
                title: "Section \(i)", order: i, startPage: i * 10, endPage: i * 10 + 9,
                rawText: "Raw text for section \(i).", cleanText: "Clean text for section \(i)."
            )
        }

        await cache.cacheSectionData(sections, for: documentId)
        let retrieved = try #require(await cache.getCachedSectionData(for: documentId))

        #expect(retrieved.count == sections.count)
        for (original, roundTripped) in zip(sections, retrieved) {
            #expect(original.title == roundTripped.title)
            #expect(original.order == roundTripped.order)
            #expect(original.rawText == roundTripped.rawText)
            #expect(original.cleanText == roundTripped.cleanText)
        }
    }

    @Test func uncachedDocumentReturnsNil() async throws {
        let cache = CacheManager()
        let result = await cache.getCachedSectionData(for: UUID())
        #expect(result == nil)
    }
}
