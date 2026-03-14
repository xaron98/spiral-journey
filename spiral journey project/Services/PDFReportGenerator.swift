import UIKit
import SpiralKit

/// Generates a multi-page PDF report suitable for sharing with a healthcare provider.
///
/// Page 1: Header with summary scores and date range.
/// Page 2: Biomarker estimates with confidence ranges + category breakdown.
/// Page 3: Disorder signatures + top recommendations.
/// Footer on every page: disclaimer and generation timestamp.
enum PDFReportGenerator {

    // MARK: - Public API

    /// Generate a PDF `Data` blob from current analysis data.
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

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { ctx in
            // ── Page 1: Summary ──────────────────────────────────────
            ctx.beginPage()
            var y = drawHeader(in: ctx, rect: pageRect, margin: margin)
            y = drawSummarySection(in: ctx, y: y, margin: margin, width: contentWidth,
                                    analysis: analysis, consistency: consistency,
                                    dateRange: dateRange, numDays: numDays)
            y = drawStatsSection(in: ctx, y: y, margin: margin, width: contentWidth,
                                  stats: analysis.stats)
            drawFooter(in: ctx, rect: pageRect, margin: margin, page: 1, totalPages: 3)

            // ── Page 2: Biomarkers + Categories ─────────────────────
            ctx.beginPage()
            y = margin + 20
            y = drawBiomarkersSection(in: ctx, y: y, margin: margin, width: contentWidth,
                                       records: records)
            y = drawCategoriesSection(in: ctx, y: y, margin: margin, width: contentWidth,
                                       categories: analysis.categories)
            drawFooter(in: ctx, rect: pageRect, margin: margin, page: 2, totalPages: 3)

            // ── Page 3: Disorder Signatures + Recommendations ───────
            ctx.beginPage()
            y = margin + 20
            y = drawSignaturesSection(in: ctx, y: y, margin: margin, width: contentWidth,
                                       signatures: analysis.signatures)
            y = drawRecommendationsSection(in: ctx, y: y, margin: margin, width: contentWidth,
                                            recommendations: Array(analysis.recommendations.prefix(5)))
            drawFooter(in: ctx, rect: pageRect, margin: margin, page: 3, totalPages: 3)
        }
    }

    // MARK: - Page 1 Sections

    private static func drawHeader(in ctx: UIGraphicsPDFRendererContext, rect: CGRect, margin: CGFloat) -> CGFloat {
        let y: CGFloat = margin

        // App name
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .light),
            .foregroundColor: UIColor.label
        ]
        let title = NSAttributedString(string: "Spiral Journey — Sleep Report", attributes: titleAttrs)
        title.draw(at: CGPoint(x: margin, y: y))

        // Subtitle
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let sub = NSAttributedString(string: "Circadian rhythm & sleep pattern analysis", attributes: subAttrs)
        sub.draw(at: CGPoint(x: margin, y: y + 28))

        // Separator line
        let lineY = y + 50
        ctx.cgContext.setStrokeColor(UIColor.separator.cgColor)
        ctx.cgContext.setLineWidth(0.5)
        ctx.cgContext.move(to: CGPoint(x: margin, y: lineY))
        ctx.cgContext.addLine(to: CGPoint(x: rect.width - margin, y: lineY))
        ctx.cgContext.strokePath()

        return lineY + 16
    }

    private static func drawSummarySection(
        in ctx: UIGraphicsPDFRendererContext,
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        analysis: AnalysisResult,
        consistency: SpiralConsistencyScore?,
        dateRange: String,
        numDays: Int
    ) -> CGFloat {
        var y = startY

        // Section title
        y = drawSectionTitle("Summary", at: y, margin: margin)

        // Date range + days
        y = drawKeyValue("Period", value: "\(dateRange) (\(numDays) days)", at: y, margin: margin, width: width)

        // Composite score
        y = drawKeyValue("Composite Score", value: "\(analysis.composite)/100 — \(analysis.label)", at: y, margin: margin, width: width)

        // Consistency
        if let c = consistency {
            y = drawKeyValue("Consistency (SRI)", value: "\(c.score)/100 — \(c.label.rawValue)", at: y, margin: margin, width: width)
            if let delta = c.deltaVsPreviousWeek {
                let sign = delta >= 0 ? "+" : ""
                y = drawKeyValue("  Week-over-week Δ", value: "\(sign)\(String(format: "%.1f", delta))", at: y, margin: margin, width: width)
            }
        }

        // SRI from stats
        let sri = analysis.stats.sri
        if sri > 0 {
            y = drawKeyValue("Sleep Regularity Index", value: String(format: "%.1f/100", sri), at: y, margin: margin, width: width)
        }

        y += 12
        return y
    }

    private static func drawStatsSection(
        in ctx: UIGraphicsPDFRendererContext,
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
        in ctx: UIGraphicsPDFRendererContext,
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
        in ctx: UIGraphicsPDFRendererContext,
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
        in ctx: UIGraphicsPDFRendererContext,
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
        in ctx: UIGraphicsPDFRendererContext,
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

    private static func drawFooter(
        in ctx: UIGraphicsPDFRendererContext,
        rect: CGRect,
        margin: CGFloat,
        page: Int,
        totalPages: Int
    ) {
        let footerY = rect.height - margin + 10

        // Separator
        ctx.cgContext.setStrokeColor(UIColor.separator.cgColor)
        ctx.cgContext.setLineWidth(0.3)
        ctx.cgContext.move(to: CGPoint(x: margin, y: footerY - 6))
        ctx.cgContext.addLine(to: CGPoint(x: rect.width - margin, y: footerY - 6))
        ctx.cgContext.strokePath()

        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 7, weight: .regular),
            .foregroundColor: UIColor.tertiaryLabel
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
            .foregroundColor: UIColor.label
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(at: CGPoint(x: margin, y: y))
        return y + 22
    }

    private static func drawKeyValue(_ key: String, value: String, at y: CGFloat, margin: CGFloat, width: CGFloat) -> CGFloat {
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.label
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
            .foregroundColor: UIColor.secondaryLabel
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
            .foregroundColor: UIColor.label
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.secondaryLabel
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
