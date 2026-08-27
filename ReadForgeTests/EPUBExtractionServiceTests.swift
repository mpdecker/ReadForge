import Testing
import Foundation
import ZIPFoundation
@testable import ReadForge

/// Builds a minimal, real EPUB archive on disk (not mocked XML parsing) so these tests exercise
/// the actual ZIP + XML parsing path `EPUBExtractionService` uses in production.
struct EPUBExtractionServiceTests {
    /// - Parameter chapterFileName: the actual on-disk (unencoded) chapter filename.
    /// - Parameter manifestHref: the `href` attribute value written into the OPF manifest —
    ///   pass a percent-encoded string to exercise the decode-before-lookup path.
    private func makeEPUB(chapterFileName: String, manifestHref: String, chapterBody: String) throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let metaInf = staging.appendingPathComponent("META-INF", isDirectory: true)
        let oebps = staging.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)

        let containerXML = """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try Data(containerXML.utf8).write(to: metaInf.appendingPathComponent("container.xml"))

        let opf = """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book</dc:title></metadata>
          <manifest>
            <item id="ch1" href="\(manifestHref)" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="ch1"/></spine>
        </package>
        """
        try Data(opf.utf8).write(to: oebps.appendingPathComponent("content.opf"))

        try Data(chapterBody.utf8).write(to: oebps.appendingPathComponent(chapterFileName))

        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try FileManager.default.zipItem(at: staging, to: zipURL, shouldKeepParent: false)
        try? FileManager.default.removeItem(at: staging)
        return zipURL
    }

    // Regression test: OPF manifest `href` attributes are percent-encoded per the EPUB spec when
    // they contain spaces/non-ASCII characters, but the actual ZIP entry is named literally.
    // Looking up the still-encoded href directly against the archive used to fail silently,
    // dropping the entire chapter with no error.
    @Test func percentEncodedHrefResolvesToTheRealChapterFile() throws {
        let zipURL = try makeEPUB(
            chapterFileName: "chapter 1.xhtml",
            manifestHref: "chapter%201.xhtml",
            chapterBody: "<html><body><p>Hello from a spaced filename.</p></body></html>"
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let pages = try EPUBExtractionService().extractPages(from: zipURL)
        #expect(pages.count == 1, "The chapter must not be silently dropped")
        #expect(pages.first?.text.contains("Hello from a spaced filename.") == true)
    }

    // Regression test: a plain tag-strip removes markup but not the TEXT CONTENT of <style> (or
    // <script>) — per-chapter inline CSS is extremely common in EPUB, and previously its raw CSS
    // text was prepended verbatim to the narrated chapter instead of being removed along with
    // its tags.
    @Test func inlineStyleAndScriptContentIsStrippedNotJustTheirTags() throws {
        let zipURL = try makeEPUB(
            chapterFileName: "chapter1.xhtml",
            manifestHref: "chapter1.xhtml",
            chapterBody: """
            <html>
            <head><style>body{font-family:Georgia;color:#333}</style><script>var x = 1;</script></head>
            <body><p>Real narrated content here.</p></body>
            </html>
            """
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let pages = try EPUBExtractionService().extractPages(from: zipURL)
        let text = try #require(pages.first?.text)
        #expect(text.contains("Real narrated content here."))
        #expect(!text.contains("font-family"), "Style rule text must not leak into narrated content")
        #expect(!text.contains("var x"), "Script text must not leak into narrated content")
    }
}
