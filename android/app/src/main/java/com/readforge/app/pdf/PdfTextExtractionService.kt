package com.readforge.app.pdf

import com.readforge.app.models.PageText
import com.readforge.app.models.PdfExtractionSummary
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object PdfTextExtractionService {

    suspend fun extract(file: File): Result<PdfExtractionSummary> = withContext(Dispatchers.IO) {
        runCatching {
            require(file.exists() && file.canRead()) { "cannot_open" }

            PDDocument.load(file).use { document ->
                if (document.isEncrypted) {
                    try {
                        document.setAllSecurityToBeRemoved(true)
                    } catch (_: Exception) {
                        error("password_protected")
                    }
                }

                val pageCount = document.numberOfPages
                require(pageCount > 0) { "no_pages" }

                val stripper = PDFTextStripper().apply {
                    sortByPosition = true
                }

                val pages = ArrayList<PageText>(pageCount)
                for (pageIndex in 1..pageCount) {
                    stripper.startPage = pageIndex
                    stripper.endPage = pageIndex
                    val text = stripper.getText(document).trim()
                    pages.add(PageText(pageNumber = pageIndex, text = text))
                }

                PdfExtractionSummary(pages = pages)
            }
        }
    }
}
