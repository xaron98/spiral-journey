import UIKit
import SpiralKit

/// Generates a multi-page PDF report suitable for sharing with a healthcare provider.
///
/// Uses Core Graphics (`CGContext`) directly instead of `UIGraphicsPDFRenderer`
/// so PDF generation can run on a **background thread** without blocking the UI.
/// Text rendering uses `UIGraphicsPushContext` (a C function that uses thread-local
/// storage, NOT `@MainActor`) to make `NSAttributedString.draw` work off-main.
///
/// Page 1: Header with summary scores and date range.
/// Page 2: Biomarker estimates with confidence ranges + category breakdown.
/// Page 3: Disorder signatures + top recommendations.
/// Footer on every page: disclaimer and generation timestamp.
enum PDFReportGenerator {

    // MARK: - Fixed Colors

    // Adaptive colors (UIColor.label etc.) resolve incorrectly in PDF context
    // when device is in dark mode, producing white-on-white. Use explicit values.
    private static let pdfBlack      = UIColor.black
    private static let pdfGray       = UIColor(white: 0.45, alpha: 1)
    private static let pdfLightGray  = UIColor(white: 0.65, alpha: 1)
    private static let pdfSeparator  = UIColor(white: 0.80, alpha: 1)

    // MARK: - Localization Helper

    private static func loc(_ key: String, bundle: Bundle) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    // MARK: - Public API

    /// Generate a PDF `Data` blob from current analysis data.
    ///
    /// **Thread-safe.** Can be called from any dispatch queue.
    static func generate(
        records: [SleepRecord],
        analysis: AnalysisResult,
        consistency: SpiralConsistencyScore?,
        dateRange: String,
        numDays: Int,
        bundle: Bundle = .main
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let margin: CGFloat = 50
        let contentWidth = pageRect.width - margin * 2

        // Create an in-memory PDF context via Core Graphics.
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = pageRect
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        // ── Page 1: Summary ──────────────────────────────────────
        beginPage(ctx, rect: pageRect)
        var y = drawHeader(ctx, rect: pageRect, margin: margin, bundle: bundle)
        y = drawSummarySection(y: y, margin: margin, width: contentWidth,
                                analysis: analysis, consistency: consistency,
                                dateRange: dateRange, numDays: numDays, bundle: bundle)
        y = drawStatsSection(y: y, margin: margin, width: contentWidth,
                              stats: analysis.stats, bundle: bundle)
        drawFooter(ctx, rect: pageRect, margin: margin, page: 1, totalPages: 3, bundle: bundle)
        endPage(ctx)

        // ── Page 2: Biomarkers + Categories ─────────────────────
        beginPage(ctx, rect: pageRect)
        y = margin + 20
        y = drawBiomarkersSection(y: y, margin: margin, width: contentWidth,
                                   records: records, bundle: bundle)
        y = drawCategoriesSection(y: y, margin: margin, width: contentWidth,
                                   categories: analysis.categories, bundle: bundle)
        drawFooter(ctx, rect: pageRect, margin: margin, page: 2, totalPages: 3, bundle: bundle)
        endPage(ctx)

        // ── Page 3: Disorder Signatures + Recommendations ───────
        beginPage(ctx, rect: pageRect)
        y = margin + 20
        y = drawSignaturesSection(y: y, margin: margin, width: contentWidth,
                                   signatures: analysis.signatures, bundle: bundle)
        y = drawRecommendationsSection(y: y, margin: margin, width: contentWidth,
                                        recommendations: Array(analysis.recommendations.prefix(5)),
                                        bundle: bundle)
        drawFooter(ctx, rect: pageRect, margin: margin, page: 3, totalPages: 3, bundle: bundle)
        endPage(ctx)

        ctx.closePDF()
        return data as Data
    }

    // MARK: - Page Lifecycle

    /// Begin a PDF page, flip to UIKit coordinates (top-left origin), and push
    /// the context so `NSAttributedString.draw` works.
    private static func beginPage(_ ctx: CGContext, rect: CGRect) {
        ctx.beginPDFPage(nil)
        ctx.saveGState()
        // Flip from CG (bottom-left origin) to UIKit (top-left origin).
        ctx.translateBy(x: 0, y: rect.height)
        ctx.scaleBy(x: 1, y: -1)
        // Push as current UIKit context (thread-local, not @MainActor).
        UIGraphicsPushContext(ctx)
    }

    /// Pop the UIKit context and end the current PDF page.
    private static func endPage(_ ctx: CGContext) {
        UIGraphicsPopContext()
        ctx.restoreGState()
        ctx.endPDFPage()
    }

    // MARK: - Page 1 Sections

    private static func drawHeader(_ ctx: CGContext, rect: CGRect, margin: CGFloat, bundle: Bundle) -> CGFloat {
        let y: CGFloat = margin

        // App name
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .light),
            .foregroundColor: pdfBlack
        ]
        let title = NSAttributedString(string: loc("pdf.report.title", bundle: bundle), attributes: titleAttrs)
        title.draw(at: CGPoint(x: margin, y: y))

        // Subtitle
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: pdfGray
        ]
        let sub = NSAttributedString(string: loc("pdf.report.subtitle", bundle: bundle), attributes: subAttrs)
        sub.draw(at: CGPoint(x: margin, y: y + 28))

        // Separator line
        let lineY = y + 50
        ctx.setStrokeColor(pdfSeparator.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: lineY))
        ctx.addLine(to: CGPoint(x: rect.width - margin, y: lineY))
        ctx.strokePath()

        return lineY + 16
    }

    private static func drawSummarySection(
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        analysis: AnalysisResult,
        consistency: SpiralConsistencyScore?,
        dateRange: String,
        numDays: Int,
        bundle: Bundle
    ) -> CGFloat {
        var y = startY

        // Section title
        y = drawSectionTitle(loc("pdf.section.summary", bundle: bundle), at: y, margin: margin)

        // Date range + days
        y = drawKeyValue(loc("pdf.label.period", bundle: bundle), value: "\(dateRange) (\(numDays) days)", at: y, margin: margin, width: width)

        // Composite score
        y = drawKeyValue(loc("pdf.label.composite", bundle: bundle), value: "\(analysis.composite)/100 — \(analysis.label)", at: y, margin: margin, width: width)

        if let c = consistency {
            y = drawKeyValue(loc("pdf.label.consistency", bundle: bundle), value: "\(c.score)/100 — \(c.label.rawValue)", at: y, margin: margin, width: width)
            if let delta = c.deltaVsPreviousWeek {
                let sign = delta >= 0 ? "+" : ""
                y = drawKeyValue(loc("pdf.label.weekDelta", bundle: bundle), value: "\(sign)\(String(format: "%.1f", delta))", at: y, margin: margin, width: width)
            }
        }

        let sri = analysis.stats.sri
        if sri > 0 {
            y = drawKeyValue(loc("pdf.label.sri", bundle: bundle), value: String(format: "%.1f/100", sri), at: y, margin: margin, width: width)
        }

        y += 12
        return y
    }

    private static func drawStatsSection(
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        stats: SleepStats,
        bundle: Bundle
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle(loc("pdf.section.stats", bundle: bundle), at: y, margin: margin)

        y = drawKeyValue(loc("pdf.label.meanDuration", bundle: bundle), value: String(format: "%.1f h", stats.meanSleepDuration), at: y, margin: margin, width: width)
        y = drawKeyValue(loc("pdf.label.meanAcrophase", bundle: bundle), value: SleepStatistics.formatHour(stats.meanAcrophase), at: y, margin: margin, width: width)
        y = drawKeyValue(loc("pdf.label.bedtimeSd", bundle: bundle), value: String(format: "%.2f h", stats.stdBedtime), at: y, margin: margin, width: width)
        y = drawKeyValue(loc("pdf.label.rhythmStability", bundle: bundle), value: String(format: "%.2f", stats.rhythmStability), at: y, margin: margin, width: width)
        y = drawKeyValue(loc("pdf.label.socialJetlag", bundle: bundle), value: formatJetlag(stats.socialJetlag), at: y, margin: margin, width: width)
        y = drawKeyValue(loc("pdf.label.meanR2", bundle: bundle), value: String(format: "%.3f", stats.meanR2), at: y, margin: margin, width: width)

        y += 12
        return y
    }

    // MARK: - Page 2 Sections

    private static func drawBiomarkersSection(
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        records: [SleepRecord],
        bundle: Bundle
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle(loc("pdf.section.biomarkers", bundle: bundle), at: y, margin: margin)

        guard let lastRecord = records.last else {
            y = drawBody(loc("pdf.body.biomarkersInsufficient", bundle: bundle), at: y, margin: margin, width: width)
            return y + 16
        }

        let biomarkers = BiomarkerEstimation.estimatePersonalized(from: lastRecord)
        for bm in biomarkers {
            var valueStr = SleepStatistics.formatHour(bm.hour)
            if let lo = bm.confidenceLow, let hi = bm.confidenceHigh {
                valueStr += "  (range: \(SleepStatistics.formatHour(lo))–\(SleepStatistics.formatHour(hi)))"
            }
            y = drawKeyValue(bm.label, value: valueStr, at: y, margin: margin, width: width)
        }

        y = drawBody(loc("pdf.body.biomarkersNote", bundle: bundle), at: y + 4, margin: margin, width: width)

        y += 16
        return y
    }

    private static func drawCategoriesSection(
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        categories: [CategoryScore],
        bundle: Bundle
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle(loc("pdf.section.categories", bundle: bundle), at: y, margin: margin)

        for cat in categories {
            let bar = String(repeating: "█", count: cat.score / 10)
            let empty = String(repeating: "░", count: 10 - cat.score / 10)
            y = drawKeyValue(cat.label, value: "\(bar)\(empty) \(cat.score)/100", at: y, margin: margin, width: width)
        }

        y += 16
        return y
    }

    // MARK: - Page 3 Sections

    private static func drawSignaturesSection(
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        signatures: [DisorderSignature],
        bundle: Bundle
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle(loc("pdf.section.patterns", bundle: bundle), at: y, margin: margin)

        if signatures.isEmpty {
            y = drawBody(loc("pdf.body.noPatternsDetected", bundle: bundle), at: y, margin: margin, width: width)
        } else {
            for sig in signatures {
                let confStr = String(format: "%.0f%%", sig.confidence * 100)
                let confLabel = String(format: loc("pdf.body.confidence", bundle: bundle), confStr)
                y = drawKeyValue(sig.fullLabel, value: confLabel, at: y, margin: margin, width: width)
                y = drawBody(sig.description, at: y, margin: margin, width: width)
                y += 4
            }
        }

        y += 16
        return y
    }

    private static func drawRecommendationsSection(
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        recommendations: [Recommendation],
        bundle: Bundle
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle(loc("pdf.section.recommendations", bundle: bundle), at: y, margin: margin)

        if recommendations.isEmpty {
            y = drawBody(loc("pdf.body.noRecommendations", bundle: bundle), at: y, margin: margin, width: width)
        } else {
            for (i, rec) in recommendations.enumerated() {
                let bullet = "\(i + 1). \(rec.title)"
                y = drawBullet(bullet, detail: rec.text, at: y, margin: margin, width: width)
            }
        }

        y += 12
        return y
    }

    // MARK: - Footer

    private static func drawFooter(
        _ ctx: CGContext,
        rect: CGRect,
        margin: CGFloat,
        page: Int,
        totalPages: Int,
        bundle: Bundle
    ) {
        let footerY = rect.height - margin + 10

        // Separator
        ctx.setStrokeColor(pdfSeparator.cgColor)
        ctx.setLineWidth(0.3)
        ctx.move(to: CGPoint(x: margin, y: footerY - 6))
        ctx.addLine(to: CGPoint(x: rect.width - margin, y: footerY - 6))
        ctx.strokePath()

        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 7, weight: .regular),
            .foregroundColor: pdfLightGray
        ]

        let disclaimer = NSAttributedString(
            string: loc("pdf.footer.disclaimer", bundle: bundle),
            attributes: footerAttrs
        )
        disclaimer.draw(at: CGPoint(x: margin, y: footerY))

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let pageLabel = String(format: loc("pdf.footer.page", bundle: bundle), "\(page)", "\(totalPages)")
        let pageStr = NSAttributedString(
            string: "\(pageLabel) · \(dateStr)",
            attributes: footerAttrs
        )
        let pageSize = pageStr.size()
        pageStr.draw(at: CGPoint(x: rect.width - margin - pageSize.width, y: footerY))
    }

    // MARK: - Drawing Primitives

    /// Formats minutes as "Xh Ym" or "Xm" for display.
    private static func formatJetlag(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static func drawSectionTitle(_ text: String, at y: CGFloat, margin: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: pdfBlack
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(at: CGPoint(x: margin, y: y))
        return y + 22
    }

    private static func drawKeyValue(_ key: String, value: String, at y: CGFloat, margin: CGFloat, width: CGFloat) -> CGFloat {
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: pdfGray
        ]
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: pdfBlack
        ]
        let keyStr = NSAttributedString(string: key, attributes: keyAttrs)
        let valStr = NSAttributedString(string: value, attributes: valAttrs)

        keyStr.draw(at: CGPoint(x: margin, y: y))
        let valX = margin + width * 0.45
        valStr.draw(at: CGPoint(x: valX, y: y))

        return y + 16
    }

    private static func drawBody(_ text: String, at y: CGFloat, margin: CGFloat, width: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: pdfGray
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let rect = CGRect(x: margin, y: y, width: width, height: 200)
        str.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        let boundingRect = str.boundingRect(with: CGSize(width: width, height: 200), options: .usesLineFragmentOrigin, context: nil)
        return y + boundingRect.height + 6
    }

    private static func drawBullet(_ title: String, detail: String, at y: CGFloat, margin: CGFloat, width: CGFloat) -> CGFloat {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: pdfBlack
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: pdfGray
        ]

        let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
        titleStr.draw(at: CGPoint(x: margin + 8, y: y))
        var nextY = y + 14

        let detailStr = NSAttributedString(string: detail, attributes: detailAttrs)
        let detailRect = CGRect(x: margin + 16, y: nextY, width: width - 16, height: 200)
        detailStr.draw(with: detailRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        let bound = detailStr.boundingRect(with: CGSize(width: width - 16, height: 200), options: .usesLineFragmentOrigin, context: nil)
        nextY += bound.height + 8

        return nextY
    }
}
