//
//  SentenceDisplayView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI

struct SentenceDisplayView: View {
    let sentence: String
    let isAnimating: Bool
    /// The word about to be spoken, as an `NSRange` within `sentence` — `nil` when nothing is
    /// playing, or the current audio is a cached clip with no captured word timings (see
    /// `PlaybackController.currentWordRange`'s doc comment).
    var highlightRange: NSRange? = nil

    var body: some View {
        ScrollView {
            Text(highlightedText)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.15), value: isAnimating)
        }
    }

    // `String.Index` and `AttributedString.Index` are different index spaces — converting a
    // range directly between them needs care, so instead this slices `sentence` (a plain
    // `String`) into three pieces using ordinary `String.Index`, then builds the
    // `AttributedString` by concatenating those pieces, styling only the middle one.
    private var highlightedText: AttributedString {
        guard let highlightRange, let range = Range(highlightRange, in: sentence) else {
            return AttributedString(sentence)
        }

        let before = sentence[sentence.startIndex..<range.lowerBound]
        let highlighted = sentence[range]
        let after = sentence[range.upperBound...]

        var highlightedAttr = AttributedString(highlighted)
        highlightedAttr.foregroundColor = .white
        highlightedAttr.backgroundColor = .accentColor

        return AttributedString(before) + highlightedAttr + AttributedString(after)
    }
}
