import Foundation
import UIKit

/// Generates real, valid PDFs for tests via `UIGraphicsPDFRenderer` — unlike hand-rolled byte
/// arrays (the previous approach, which lacked a valid xref table/trailer and made every test
/// depending on it fail with `PDFDocument`'s `.cannotOpen`), this produces files PDFKit can
/// actually open, with real extractable text.
enum PDFTestFixtures {
    private static let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter

    static func data(pageCount: Int = 1, titlePrefix: String = "Test Page") -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { context in
            for i in 1...max(pageCount, 1) {
                context.beginPage()
                let text = "\(titlePrefix) \(i)\n\nThis is sample body text for page \(i) used in tests."
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 18)]
                (text as NSString).draw(
                    in: CGRect(x: 40, y: 40, width: pageBounds.width - 80, height: pageBounds.height - 80),
                    withAttributes: attributes
                )
            }
        }
    }

    /// Writes a generated PDF to a unique temp file and returns its URL.
    @discardableResult
    static func write(pageCount: Int = 1, titlePrefix: String = "Test Page", filename: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data(pageCount: pageCount, titlePrefix: titlePrefix).write(to: url)
        return url
    }
}
