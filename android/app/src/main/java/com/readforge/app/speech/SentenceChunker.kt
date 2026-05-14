package com.readforge.app.speech

import java.text.BreakIterator
import java.util.Locale

/**
 * 300–800 character utterances, sentence-first then merged — parity with iOS [SentenceChunker].
 */
object SentenceChunker {

    private const val MIN_LENGTH = 300
    private const val MAX_LENGTH = 800

    fun chunk(text: String): List<String> {
        if (text.isBlank()) return emptyList()
        val sentences = mutableListOf<String>()
        val iterator = BreakIterator.getSentenceInstance(Locale.getDefault())
        iterator.setText(text)
        var start = iterator.first()
        var end = iterator.next()
        while (end != BreakIterator.DONE) {
            val sentence = text.substring(start, end).trim()
            if (sentence.isNotEmpty()) {
                sentences.add(sentence)
            }
            start = end
            end = iterator.next()
        }
        return merge(sentences).flatMap { hardSplit(it) }
    }

    private fun merge(sentences: List<String>): List<String> {
        val chunks = mutableListOf<String>()
        var current = ""

        for (sentence in sentences) {
            when {
                current.isEmpty() -> current = sentence
                current.length + 1 + sentence.length <= MAX_LENGTH -> current += " $sentence"
                current.length >= MIN_LENGTH -> {
                    chunks.add(current)
                    current = sentence
                }
                else -> {
                    current += " $sentence"
                    if (current.length >= MIN_LENGTH) {
                        chunks.add(current)
                        current = ""
                    }
                }
            }
        }
        if (current.isNotEmpty()) {
            chunks.add(current)
        }
        return chunks
    }

    private fun hardSplit(text: String): List<String> {
        if (text.length <= MAX_LENGTH) return listOf(text)
        val result = mutableListOf<String>()
        var remaining = text
        while (remaining.length > MAX_LENGTH) {
            val prefix = remaining.take(MAX_LENGTH)
            val lastSpace = prefix.lastIndexOf(' ')
            if (lastSpace > 0) {
                result.add(remaining.substring(0, lastSpace))
                remaining = remaining.substring(lastSpace + 1)
            } else {
                result.add(remaining.take(MAX_LENGTH))
                remaining = remaining.drop(MAX_LENGTH)
            }
        }
        if (remaining.isNotEmpty()) {
            result.add(remaining)
        }
        return result
    }
}
