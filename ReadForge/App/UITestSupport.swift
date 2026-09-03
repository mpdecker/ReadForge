import Foundation
import SwiftData

/// Launch-argument hooks the XCUITest bundle uses to put the app into a known state.
///
/// Compiled out of release builds on purpose. The sign-in gate is the only barrier in front of
/// document content, so a code path that skips it must not exist in anything shipped — see
/// CLAUDE.md's privacy rules. Every switch is additionally opt-in via an argument the test
/// runner passes, so an ordinary debug launch from Xcode still boots through the normal
/// sign-in flow.
///
/// The UI tests previously passed `--uitesting` / `UI_TESTING` that nothing ever read, so every
/// one of them launched into `AuthenticationView` and failed on its first assertion about the
/// tab bar.
enum UITestSupport {
    /// Skip the sign-in screen and boot straight into `ContentView`.
    static let bypassAuthArgument = "-uitest-bypass-auth"

    /// Back SwiftData with an in-memory store so a run can neither see leftovers from a previous
    /// one nor persist anything into the simulator.
    static let inMemoryStoreArgument = "-uitest-in-memory-store"

    /// Insert one ready-to-play document so the player tests have something to navigate into.
    static let seedLibraryArgument = "-uitest-seed-library"

    /// Title of the fixture inserted by ``seedLibrary(in:)``; the tests address the row by it.
    static let seededDocumentTitle = "UI Test Document"

    static func isEnabled(_ argument: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(argument)
        #else
        return false
        #endif
    }

    #if DEBUG
    /// A signed-in identity for `bypassAuthArgument`. Registered through the model context like
    /// any other user so `SettingsView`'s Account section renders its normal signed-in state.
    @MainActor
    static func makeTestUser(in context: ModelContext) -> User {
        let existing = (try? context.fetch(FetchDescriptor<User>())) ?? []
        if let user = existing.first(where: { $0.email == "uitest@readforge.app" }) {
            return user
        }
        let user = User(email: "uitest@readforge.app", name: "UI Test")
        context.insert(user)
        try? context.save()
        return user
    }

    /// Inserts the document the player tests open.
    ///
    /// Two sections, so `PlayerView` also renders its section picker, and well over
    /// `SentenceChunker`'s 800-character ceiling of prose in each so every section chunks into
    /// several utterances — otherwise skip-forward has nowhere to move and the transport
    /// assertions would pass or fail on chunking luck.
    @MainActor
    static func seedLibrary(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<DocumentRecord>())) ?? []
        guard existing.isEmpty else { return }

        let document = DocumentRecord(
            title: seededDocumentTitle,
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("uitest-document.pdf"),
            author: "ReadForge"
        )
        document.pageCount = 2
        document.processingStatus = .ready
        // Nothing was ever extracted from a real file here, and no view surfaces this flag —
        // but leaving it false would be a lie about a document whose `filePath` points at
        // nothing, and any future re-extraction path is documented to check it.
        document.sourceFileMissing = true
        context.insert(document)

        let bodies = [
            """
            The first chapter opens on a quiet morning. Rain moved across the valley overnight \
            and left the road soft underfoot. She walked the whole length of it without meeting \
            anyone at all. By the time the sun cleared the ridge the puddles had already begun \
            to shrink back into the gravel. There was a gate at the far end that had not been \
            closed properly in years, and she went through it the way she always had, sideways, \
            without breaking her stride. The field beyond was full of the particular silence \
            that follows heavy weather. Nothing moved except the water still finding its way \
            downhill. She stopped once, near the middle, and listened for a long moment to a \
            sound she could not place, and then decided it had been nothing after all. The \
            house came into view exactly when she expected it to, which was somehow the most \
            surprising thing about the entire walk. Smoke was already rising from the chimney. \
            Someone had been up before her, then, and had not said so the night before. She \
            considered this for the last hundred yards and arrived without having reached any \
            conclusion worth the effort of thinking it.
            """,
            """
            The second chapter begins somewhere else entirely. A train station, mid afternoon, \
            with the departure boards clicking over one destination at a time. He counted the \
            departures twice and still could not decide which of them he wanted. The \
            announcement repeated itself, and then it did not, and the platform emptied in the \
            unhurried way that platforms do. A man with a folded newspaper had been sitting on \
            the same bench since before he arrived, and showed no sign of intending to board \
            anything. There was a coffee stand at the north end that had run out of almost \
            everything. He bought what was left and drank it standing up, watching the boards \
            reset themselves for the evening timetable. Somewhere behind him a case fell over \
            and nobody picked it up. He thought about the letter in his coat pocket and decided, \
            not for the first time that week, that he would read it properly once he was moving \
            and not a minute before. The next train was in eleven minutes. He had until then to \
            invent a reason for being on it.
            """,
        ]

        for (index, body) in bodies.enumerated() {
            let section = SectionRecord(
                title: "Chapter \(index + 1)",
                rawText: body,
                order: index,
                startPage: index + 1,
                endPage: index + 1
            )
            section.document = document
            context.insert(section)
        }

        try? context.save()
    }
    #endif
}
