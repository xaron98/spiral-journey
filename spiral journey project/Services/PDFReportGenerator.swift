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

    // MARK: - Public API

    /// Generate a PDF `Data` blob from current analysis data.
    ///
    /// **Thread-safe.** Can be called from any dispatch queue.
    static func generate(
        records: [SleepRecord],
        analysis: AnalysisResult,
        consistency: SpiralConsistencyScore?,
        dateRange: String,
        numDays: Int
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
        var y = drawHeader(ctx, rect: pageRect, margin: margin)
        y = drawSummarySection(y: y, margin: margin, width: contentWidth,
                                analysis: analysis, consistency: consistency,
                                dateRange: dateRange, numDays: numDays)
        y = drawStatsSection(y: y, margin: margin, width: contentWidth,
                              stats: analysis.stats)
        drawFooter(ctx, rect: pageRect, margin: margin, page: 1, totalPages: 3)
        endPage(ctx)

        // ── Page 2: Biomarkers + Categories ─────────────────────
        beginPage(ctx, rect: pageRect)
        y = margin + 20
        y = drawBiomarkersSection(y: y, margin: margin, width: contentWidth,
                                   records: records)
        y = drawCategoriesSection(y: y, margin: margin, width: contentWidth,
                                   categories: analysis.categories)
        drawFooter(ctx, rect: pageRect, margin: margin, page: 2, totalPages: 3)
        endPage(ctx)

        // ── Page 3: Disorder Signatures + Recommendations ───────
        beginPage(ctx, rect: pageRect)
        y = margin + 20
        y = drawSignaturesSection(y: y, margin: margin, width: contentWidth,
                                   signatures: analysis.signatures)
        y = drawRecommendationsSection(y: y, margin: margin, width: contentWidth,
                                        recommendations: Array(analysis.recommendations.prefix(5)))
        drawFooter(ctx, rect: pageRect, margin: margin, page: 3, totalPages: 3)
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

    private static func drawHeader(_ ctx: CGContext, rect: CGRect, margin: CGFloat) -> CGFloat {
        let y: CGFloat = margin

        // App name
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .light),
            .foregroundColor: pdfBlack
        ]
        let title = NSAttributedString(string: "Spiral Journey — Sleep Report", attributes: titleAttrs)
        title.draw(at: CGPoint(x: margin, y: y))

        // Subtitle
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: pdfGray
        ]
        let sub = NSAttributedString(string: "Circadian rhythm & sleep pattern analysis", attributes: subAttrs)
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
        numDays: Int
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle("Summary", at: y, margin: margin)
        y = drawKeyValue("Period", value: "\(dateRange) (\(numDays) days)", at: y, margin: margin, width: width)
        y = drawKeyValue("Composite Score", value: "\(analysis.composite)/100 — \(analysis.label)", at: y, margin: margin, width: width)

        if let c = consistency {
            y = drawKeyValue("Consistency (SRI)", value: "\(c.score)/100 — \(c.label.rawValue)", at: y, margin: margin, width: width)
            if let delta = c.deltaVsPreviousWeek {
                let sign = delta >= 0 ? "+" : ""
                y = drawKeyValue("  Week-over-week Δ", value: "\(sign)\(String(format: "%.1f", delta))", at: y, margin: margin, width: width)
            }
        }

        let sri = analysis.stats.sri
        if sri > 0 {
            y = drawKeyValue("Sleep Regularity Index", value: String(format: "%.1f/100", sri), at: y, margin: margin, width: width)
        }

        y += 12
        return y
    }

    private static func drawStatsSection(
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        stats: SleepStats
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle("Sleep Statistics", at: y, margin: margin)
        y = drawKeyValue("Mean Duration", value: String(format: "%.1f h", stats.meanSleepDuration), at: y, margin: margin, width: width)
        y = drawKeyValue("Mean Acrophase", value: SleepStatistics.formatHour(stats.meanAcrophase), at: y, margin: margin, width: width)
        y = drawKeyValue("Bedtime SD (circular)", value: String(format: "%.2f h", stats.stdBedtime), at: y, margin: margin, width: width)
        y = drawKeyValue("Rhythm Stability", value: String(format: "%.2f", stats.rhythmStability), at: y, margin: margin, width: width)
        y = drawKeyValue("Social Jetlag", value: formatJetlag(stats.socialJetlag), at: y, margin: margin, width: width)
        y = drawKeyValue("Mean Cosinor R²", value: String(format: "%.3f", stats.meanR2), at: y, margin: margin, width: width)

        y += 12
        return y
    }

    // MARK: - Page 2 Sections

    private static func drawBiomarkersSection(
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        records: [SleepRecord]
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle("Estimated Circadian Biomarkers", at: y, margin: margin)

        guard let lastRecord = records.last else {
            y = drawBody("Insufficient data for biomarker estimation.", at: y, margin: margin, width: width)
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

        y = drawBody(
            "Note: Biomarkers are statistical estimates based on sleep timing patterns, not direct measurements.",
            at: y + 4, margin: margin, width: width
        )

        y += 16
        return y
    }

    private static func drawCategoriesSection(
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        categories: [CategoryScore]
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle("Category Breakdown", at: y, margin: margin)

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
        signatures: [DisorderSignature]
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle("Circadian Pattern Analysis", at: y, margin: margin)

        if signatures.isEmpty {
            y = drawBody("No notable circadian patterns detected.", at: y, margin: margin, width: width)
        } else {
            for sig in signatures {
                let confStr = String(format: "%.0f%%", sig.confidence * 100)
                y = drawKeyValue(sig.fullLabel, value: "Confidence: \(confStr)", at: y, margin: margin, width: width)
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
        recommendations: [Recommendation]
    ) -> CGFloat {
        var y = startY

        y = drawSectionTitle("Recommendations", at: y, margin: margin)

        if recommendations.isEmpty {
            y = drawBody("No specific recommendations at this time.", at: y, margin: margin, width: width)
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

    private static func drawFooter(_ ctx: CGContext, rect: CGRect, margin: CGFloat, page: Int, totalPages: Int) {
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
            string: "Generated by Spiral Journey · Self-reported data · Does not substitute medical diagnosis",
            attributes: footerAttrs
        )
        disclaimer.draw(at: CGPoint(x: margin, y: footerY))

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let pageStr = NSAttributedString(
            string: "Page \(page)/\(totalPages) · \(dateStr)",
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
