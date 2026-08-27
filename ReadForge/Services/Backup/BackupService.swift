import Foundation
import SwiftData
import ZIPFoundation

/// Local backup & restore.
///
/// CLAUDE.md's privacy rules say "no cloud processing by default" and "optional cloud sync is
/// explicit opt-in only" — but there's no backend to sync to (`NetworkService` is a stub with
/// nowhere to send data). Standing up a real hosted sync service isn't something a coding session
/// can deliver — that needs a deployed, maintained server. This is the honest, buildable
/// interpretation of "opt-in sync": package the whole library into one file, entirely under the
/// user's control — put it in iCloud Drive, another cloud provider, AirDrop it — nothing leaves
/// the device unless the user explicitly exports it.
struct BackupService {
    enum BackupError: LocalizedError, Equatable {
        case noDocuments
        case invalidArchive
        case unsupportedVersion(Int)
        case incompatibleVersion(Int)

        var errorDescription: String? {
            switch self {
            case .noDocuments:
                return "There's nothing in your library to back up yet."
            case .invalidArchive:
                return "This doesn't look like a ReadForge backup file."
            case .unsupportedVersion(let version):
                return "This backup was made with a newer version of ReadForge (format \(version)) and can't be restored here."
            case .incompatibleVersion(let version):
                return "This backup uses an old, incompatible format (format \(version)) that can no longer be restored."
            }
        }
    }

    // Bumped from 1: v1 stored every document's snapshot in one `documents.json` array, which
    // meant the whole library's raw+clean section text was resident in memory at once during
    // export/import — a direct violation of CLAUDE.md's "never load a full document into
    // memory." v2 stores one JSON file per document instead (see `Manifest.documentIds` +
    // `Documents/<id>.json`), so at most one document's text is ever in memory at a time. No
    // migration from v1 is provided — there's no released version of this app with real user
    // backups in that format yet.
    private static let formatVersion = 2

    // MARK: - Codable snapshots (independent of the @Model types, which aren't Codable-safe
    // across app versions if the schema ever changes)

    private struct Manifest: Codable {
        let formatVersion: Int
        let exportedAt: Date
        let documentIds: [UUID]
    }

    private struct DocumentSnapshot: Codable {
        let id: UUID
        let title: String
        let author: String?
        let pageCount: Int
        let importedAt: Date
        let status: String
        let languageCode: String?
        let originalFileName: String?
        let sections: [SectionSnapshot]
        let bookmarks: [BookmarkSnapshot]
        let playbackState: PlaybackStateSnapshot?
    }

    private struct SectionSnapshot: Codable {
        let id: UUID
        let title: String
        let rawText: String
        let cleanText: String?
        let order: Int
        let startPage: Int
        let endPage: Int
    }

    private struct BookmarkSnapshot: Codable {
        let id: UUID
        let sectionId: UUID
        let sentenceIndex: Int
        let note: String?
        let createdAt: Date
    }

    private struct PlaybackStateSnapshot: Codable {
        let sectionId: UUID
        let sentenceIndex: Int
        let characterOffset: Int
        let lastPlayedAt: Date
        let playbackRate: Double
        let voiceIdentifier: String?
    }

    // MARK: - Export

    /// Builds and writes ONE document's snapshot at a time — never accumulates the whole
    /// library's raw+clean section text in memory at once (CLAUDE.md: "never load a full
    /// document into memory," "store raw and clean text per section separately"). Reading each
    /// document's SwiftData properties (fast, in-memory) happens on the main actor; writing
    /// that one document's JSON + copying its original file happens off the main actor before
    /// moving on to the next document, so memory stays bounded to one document at a time and
    /// the UI thread is never blocked by the file I/O.
    @MainActor
    func exportBackup(context: ModelContext) async throws -> URL {
        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        guard !documents.isEmpty else { throw BackupError.noDocuments }

        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documentsDir = staging.appendingPathComponent("Documents", isDirectory: true)
        let filesDir = staging.appendingPathComponent("Files", isDirectory: true)
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        }.value

        var documentIds: [UUID] = []

        for document in documents {
            var originalFileName: String?
            var fileToCopy: (source: URL, destName: String)?
            if FileManager.default.fileExists(atPath: document.fileURL.path) {
                let destName = "\(document.id.uuidString).\(document.fileURL.pathExtension)"
                fileToCopy = (document.fileURL, destName)
                originalFileName = destName
            }

            // This is the only point where one document's section text is read into memory —
            // it's written to disk and released before the next document is touched.
            let sections = document.sections.sorted { $0.order < $1.order }.map {
                SectionSnapshot(
                    id: $0.id, title: $0.title, rawText: $0.rawText, cleanText: $0.cleanText,
                    order: $0.order, startPage: $0.startPage, endPage: $0.endPage
                )
            }
            let bookmarks = document.bookmarks.map {
                BookmarkSnapshot(
                    id: $0.id, sectionId: $0.sectionId, sentenceIndex: $0.sentenceIndex,
                    note: $0.note, createdAt: $0.createdAt
                )
            }
            let playbackState = document.playbackState.map {
                PlaybackStateSnapshot(
                    sectionId: $0.sectionId, sentenceIndex: $0.sentenceIndex,
                    characterOffset: $0.characterOffset, lastPlayedAt: $0.lastPlayedAt,
                    playbackRate: $0.playbackRate, voiceIdentifier: $0.voiceIdentifier
                )
            }

            let snapshot = DocumentSnapshot(
                id: document.id, title: document.title, author: document.author,
                pageCount: document.pageCount, importedAt: document.importedAt,
                status: document.processingStatus.rawValue, languageCode: document.languageCode,
                originalFileName: originalFileName, sections: sections, bookmarks: bookmarks,
                playbackState: playbackState
            )
            documentIds.append(document.id)

            try await Task.detached(priority: .utility) {
                try Self.writeDocument(snapshot, fileToCopy: fileToCopy, documentsDir: documentsDir, filesDir: filesDir)
            }.value
        }

        return try await Task.detached(priority: .utility) {
            try Self.finalizeArchive(staging: staging, documentIds: documentIds)
        }.value
    }

    private static func writeDocument(
        _ snapshot: DocumentSnapshot, fileToCopy: (source: URL, destName: String)?,
        documentsDir: URL, filesDir: URL
    ) throws {
        if let fileToCopy {
            try? FileManager.default.copyItem(at: fileToCopy.source, to: filesDir.appendingPathComponent(fileToCopy.destName))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: documentsDir.appendingPathComponent("\(snapshot.id.uuidString).json"))
    }

    private static func finalizeArchive(staging: URL, documentIds: [UUID]) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Manifest(formatVersion: Self.formatVersion, exportedAt: Date(), documentIds: documentIds))
            .write(to: staging.appendingPathComponent("manifest.json"))

        let destinationZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadForge-Backup-\(Int(Date().timeIntervalSince1970)).zip")
        try? FileManager.default.removeItem(at: destinationZip)
        try FileManager.default.zipItem(at: staging, to: destinationZip, shouldKeepParent: false)
        try? FileManager.default.removeItem(at: staging)

        return destinationZip
    }

    // MARK: - Import

    @MainActor
    func importBackup(from zipURL: URL, context: ModelContext) async throws {
        let accessed = zipURL.startAccessingSecurityScopedResource()
        defer { if accessed { zipURL.stopAccessingSecurityScopedResource() } }

        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: extractDir) }

        do {
            try FileManager.default.unzipItem(at: zipURL, to: extractDir)
        } catch {
            throw BackupError.invalidArchive
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let manifestData = try? Data(contentsOf: extractDir.appendingPathComponent("manifest.json")),
              let manifest = try? decoder.decode(Manifest.self, from: manifestData)
        else { throw BackupError.invalidArchive }
        // Must be an exact match, not `<=`: v1 used a completely different archive layout (see
        // the doc comment on `formatVersion`), and there is no migration from it. `<=` let a v1
        // (or any other older/mismatched) manifest silently proceed through v2's per-document-file
        // logic, where none of its lookups match, so every document was skipped and the restore
        // reported success having imported zero documents.
        guard manifest.formatVersion == Self.formatVersion else {
            if manifest.formatVersion > Self.formatVersion {
                throw BackupError.unsupportedVersion(manifest.formatVersion)
            } else {
                throw BackupError.incompatibleVersion(manifest.formatVersion)
            }
        }

        var existingIds = Set(try context.fetch(FetchDescriptor<DocumentRecord>()).map(\.id))
        let filesDir = extractDir.appendingPathComponent("Files", isDirectory: true)
        let documentsDir = extractDir.appendingPathComponent("Documents", isDirectory: true)

        for documentId in manifest.documentIds {
            // Skip documents already present (e.g. restoring the same backup twice) rather than
            // creating duplicates. `existingIds` must be updated as each id is consumed, not just
            // checked against the pre-loop snapshot — none of the four restored model types
            // enforce a uniqueness constraint on `id`, so a corrupted/crafted manifest listing the
            // same id twice previously sailed through this guard both times and created two
            // records sharing one id (which `StorageService.fetchDocument(id:)`'s `.first` match
            // then resolves to arbitrarily/unstably).
            guard !existingIds.contains(documentId) else { continue }
            existingIds.insert(documentId)

            // Only this one document's snapshot is ever decoded into memory at a time — never
            // the whole backup's worth of section text at once.
            let snapshotFile = documentsDir.appendingPathComponent("\(documentId.uuidString).json")
            guard let snapshotData = try? Data(contentsOf: snapshotFile),
                  let snapshot = try? decoder.decode(DocumentSnapshot.self, from: snapshotData)
            else { continue } // skip a corrupt/missing entry rather than aborting the whole restore

            // `/dev/null` is a real device node — `FileManager.fileExists(atPath:)` reports
            // `true` for it, so a naive future check for "does this document still have its
            // source file" would get a false positive. A placeholder path that's guaranteed not
            // to exist, plus an explicit `sourceFileMissing` flag, makes this state checkable
            // rather than silently misleading.
            let sandboxDir = try DocumentImportService.sandboxURL()
            var fileURL = sandboxDir.appendingPathComponent("missing-\(snapshot.id.uuidString)")
            var sourceFileMissing = true
            if let originalFileName = snapshot.originalFileName {
                let sourceFile = filesDir.appendingPathComponent(originalFileName)
                if FileManager.default.fileExists(atPath: sourceFile.path) {
                    let destFile = sandboxDir.appendingPathComponent(originalFileName)
                    try? FileManager.default.copyItem(at: sourceFile, to: destFile)
                    fileURL = destFile
                    sourceFileMissing = false
                }
            }

            let record = DocumentRecord(title: snapshot.title, fileURL: fileURL, author: snapshot.author)
            record.id = snapshot.id
            record.pageCount = snapshot.pageCount
            record.importedAt = snapshot.importedAt
            record.processingStatus = ProcessingStatus(rawValue: snapshot.status) ?? .imported
            record.languageCode = snapshot.languageCode
            record.sourceFileMissing = sourceFileMissing
            context.insert(record)

            record.sections = snapshot.sections.map { s in
                let section = SectionRecord(
                    title: s.title, rawText: s.rawText, order: s.order,
                    startPage: s.startPage, endPage: s.endPage
                )
                section.id = s.id
                section.cleanText = s.cleanText
                section.refreshWordCount()
                section.document = record
                context.insert(section)
                return section
            }

            record.bookmarks = snapshot.bookmarks.map { b in
                let bookmark = BookmarkRecord(sectionId: b.sectionId, sentenceIndex: b.sentenceIndex, note: b.note)
                bookmark.id = b.id
                bookmark.createdAt = b.createdAt
                bookmark.document = record
                context.insert(bookmark)
                return bookmark
            }

            if let ps = snapshot.playbackState {
                let state = PlaybackState(
                    documentId: record.id, sectionId: ps.sectionId,
                    sentenceIndex: ps.sentenceIndex, characterOffset: ps.characterOffset
                )
                state.lastPlayedAt = ps.lastPlayedAt
                state.playbackRate = ps.playbackRate
                state.voiceIdentifier = ps.voiceIdentifier
                record.playbackState = state
                context.insert(state)
            }
        }

        try context.save()
    }
}
