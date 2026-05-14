import Foundation

enum ImportError: LocalizedError {
    case unsupportedFormat, fileMissing, encrypted, corrupt, insufficientStorage

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:    return "This file type is not supported."
        case .fileMissing:          return "The file could not be accessed."
        case .encrypted:            return "Password-protected files are not supported yet."
        case .corrupt:              return "The file appears to be corrupt."
        case .insufficientStorage:  return "Not enough storage space to import this document."
        }
    }
}

struct DocumentImportService: Sendable {
    private static let documentsFolder = "ImportedDocuments"

    static func sandboxURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = support.appendingPathComponent(documentsFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Copies any supported document into the app sandbox and returns an unsaved `DocumentRecord`.
    /// The caller must insert the record into a `ModelContext`.
    nonisolated func importDocument(from sourceURL: URL) throws -> DocumentRecord {
        // Security validation
        guard SecurityService.validateFilePath(sourceURL.path) else {
            throw ImportError.corrupt
        }
        
        guard DocumentFormat(url: sourceURL) != nil else { throw ImportError.unsupportedFormat }

        let ext        = sourceURL.pathExtension.lowercased()
        let sandboxDir = try Self.sandboxURL()
        let destURL    = sandboxDir.appendingPathComponent(UUID().uuidString + "." + ext)

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ImportError.fileMissing
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch let err as CocoaError where err.code == .fileWriteOutOfSpace {
            throw ImportError.insufficientStorage
        } catch {
            throw ImportError.fileMissing
        }

        let rawName = sourceURL.deletingPathExtension().lastPathComponent
        let title   = rawName.removingPercentEncoding ?? rawName
        return DocumentRecord(title: title.isEmpty ? "Untitled" : title, fileURL: destURL)
    }

    // MARK: - Backward compatibility shim
    // `importPDF` was the original entry-point; delegate to the new generic method.
    nonisolated func importPDF(from sourceURL: URL) throws -> DocumentRecord {
        try importDocument(from: sourceURL)
    }
}
