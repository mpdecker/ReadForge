# ReadForge — Claude Development Guide

## What This Is

ReadForge is an iOS-first mobile app that converts PDFs into private, listenable audiobooks. Everything runs on-device — no cloud, no uploads, no analytics on document content.

**Core promise:** "Turn any long PDF into a private, listenable audiobook on your phone."

## Platform & Stack

- **iOS 17+**, SwiftUI, MVVM + Services architecture
- PDFKit for text extraction
- AVFoundation / AVSpeechSynthesizer for native TTS (MVP)
- Core Data or SQLite for local storage
- Background audio via AVAudioSession
- llama.cpp or ONNX Runtime Mobile for local LLM (post-MVP)

Android comes later. Do not design for cross-platform parity in the MVP.

## Architecture

```
App/
Models/
Views/
ViewModels/
Services/
  PDF/        ← PDFExtractionService, DocumentImportService
  Speech/     ← SpeechService, SentenceChunker, TTSEngine protocol
  Storage/    ← persistence layer
  AI/         ← AIModelManager, TextCleanupService (LLM phase)
  Playback/   ← PlaybackController, progress tracking
Resources/
Tests/
```

## Build Order (Critical — Do Not Skip Ahead)

```
1.  SwiftUI shell + navigation
2.  Library screen (empty state, import button, document list)
3.  PDF import (fileImporter, copy into app sandbox)
4.  PDF text extraction (PDFKit, page by page)
5.  Rule-based text cleanup (deterministic, no LLM)
6.  Section splitting (use PDF outline; fallback: 2k–4k word chunks)
7.  Native TTS playback (AVSpeechSynthesizer)
8.  Sentence chunking (300–800 chars per utterance)
9.  Progress saving (per sentence, per character offset)
10. Background audio (AVAudioSession .playback category)
11. Bookmarks
12. Settings screen
--- MVP complete ---
13. Local LLM cleanup (llama.cpp + GGUF, 1B–3B model)
14. Ask mode (local RAG with embeddings)
15. Audio caching (AVSpeechSynthesizer.write buffer)
16. OCR (Vision framework, VNRecognizeTextRequest)
17. Neural voice packs
```

**Do not build neural voice generation until steps 1–10 are solid.**

## Core Data Models

```swift
// PDFDocumentRecord — one per imported file
// PDFSection — extracted/cleaned text chunk with order + page range
// PlaybackProgress — sentence-level position, saved after every sentence
// Bookmark — sentence + optional note
```

See implementation plan Steps 3 & 24 for full struct definitions.

## Text Processing Pipeline

```
PDF → extract raw text (PDFKit) → deterministic cleanup → (later: LLM cleanup) → section split → sentence chunk → TTS → audio
```

### Deterministic Cleanup Rules (Step 10–11)
- Collect first/last 2 lines per page; remove any line repeated on 30%+ of pages (headers/footers)
- Fix hyphenated line breaks: `"exam-\nple"` → `"example"`
- Join soft-wrapped lines within paragraphs
- Normalize whitespace; preserve double-newline paragraph breaks

### LLM Cleanup Prompt (Phase 9, Step 29)
```
You are preparing PDF text for spoken narration.
Remove layout artifacts, headers, footers, broken line wraps, and citation clutter.
Preserve all meaning. Do not summarize. Return only the cleaned text.
```
Always validate LLM output: not empty, not much shorter than input, no markdown, no assistant commentary. Fall back to deterministic clean text on failure.

## Speech

- Chunk text into 300–800 char utterances (sentence boundaries preferred)
- One utterance at a time through AVSpeechSynthesizer
- Save `sentenceIndex` + `characterOffset` after every utterance completes
- Background audio: set `AVAudioSession` category to `.playback` at launch
- Lock screen controls: MPNowPlayingInfoCenter (post-MVP polish)

## Storage

Five tables: `documents`, `sections`, `playback_progress`, `bookmarks`, `settings`

Store raw and clean text per section separately. Never load a full document into memory.

Audio cache keyed by: `documentId + sectionId + voiceId + speed + textHash`

## Privacy Rules (Non-Negotiable)

- PDFs never leave the device
- No cloud processing by default
- Crash analytics must exclude document content
- Optional cloud sync is explicit opt-in only
- Offline-only mode is a first-class setting

## Performance Targets

- Open 100-page text PDF within 5 seconds
- Begin playback within 10 seconds of import
- Allow listening before full document is processed (progressive pipeline)
- Pause AI processing when battery is low or device is hot
- Memory: stay within safe mobile limits; load sections on demand

## Listening Time Estimate

`words / 160 = minutes` at 1x speed. Divide by playback speed for adjusted time.

## Scanned PDF Handling (MVP)

If average extracted text < 50 chars/page → mark as `needsOCR`, show message, do not attempt playback. OCR (Vision framework) comes in Phase 13.

## LLM Model Targets (Phase 9+)

- 1B–4B parameter instruct model
- 4-bit quantized GGUF
- 4k–16k context window
- Candidate families: Qwen 2.5/3, Phi, Gemma, Llama-compatible small instruct

## MVP Scope — Build These

PDF import, text extraction, basic cleanup, native TTS, progress saving, library, player, background audio, section splitting, offline privacy.

## MVP Scope — Do Not Build Yet

Custom neural voice cloning, cloud sync, social sharing, multi-device sync, full OCR, audio export, complex RAG chat.

## Release Milestones

| Release | Must Have |
|---------|-----------|
| Alpha   | Import → extract → clean → read aloud → save progress → background audio |
| Beta    | + Bookmarks, voice/speed settings, error handling, crash reporting (no doc content) |
| v1.0    | Stable text PDF playback, offline, library, player, privacy-first |
| v1.5    | + Local LLM cleanup, summaries, Ask mode |
| v2.0    | + Neural voices, OCR, audio export, advanced narration modes |
