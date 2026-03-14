import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// A `Transferable` wrapper around PDF data for use with `ShareLink`.
struct PDFReportDocument: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { doc in
            doc.data
        }
        .suggestedFileName("SpiralJourney_SleepReport.pdf")
    }
}
