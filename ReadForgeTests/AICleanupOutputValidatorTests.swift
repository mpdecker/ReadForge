import Testing
@testable import ReadForge

struct AICleanupOutputValidatorTests {
    // Regression test: the markdown-blockquote check used to be a plain substring match for
    // "> ", which rejected perfectly correct cleanup output on ordinary technical text that
    // happens to contain a greater-than comparison.
    @Test func mathematicalComparisonIsNotFlaggedAsMarkdown() {
        let original = "The algorithm only rebalances when n > 100 elements are processed, which keeps overhead low for small inputs."
        let candidate = original // cleanup returning the text essentially unchanged is valid
        #expect(AICleanupOutputValidator.isValid(candidate, against: original))
    }

    @Test func actualBlockquoteAtLineStartIsStillRejected() {
        let original = "Some paragraph of ordinary text that is reasonably long for this test to pass the length check."
        let candidate = "> Some paragraph of ordinary text that is reasonably long for this test to pass the length check."
        #expect(!AICleanupOutputValidator.isValid(candidate, against: original))
    }

    @Test func actualBlockquoteMidTextIsStillRejected() {
        let original = "First line of a paragraph here. Second line continues right after that one plainly."
        let candidate = "First line of a paragraph here.\n> Second line continues right after that one plainly."
        #expect(!AICleanupOutputValidator.isValid(candidate, against: original))
    }

    @Test func emptyCandidateIsInvalid() {
        #expect(!AICleanupOutputValidator.isValid("", against: "Some original text."))
    }

    @Test func muchShorterCandidateIsInvalid() {
        let original = "This is a fairly long original paragraph that should not be drastically shortened by cleanup."
        #expect(!AICleanupOutputValidator.isValid("Too short.", against: original))
    }

    @Test func assistantCommentaryIsInvalid() {
        let original = "A normal paragraph of source text that is long enough to pass the length check easily."
        let candidate = "Here is the cleaned text: a normal paragraph of source text that is long enough to pass the length check easily."
        #expect(!AICleanupOutputValidator.isValid(candidate, against: original))
    }
}
