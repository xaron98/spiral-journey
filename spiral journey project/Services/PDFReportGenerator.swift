import CoreGraphics
import CoreText
import UIKit  // Only for UIFont (toll-free bridged to CTFont)
import SpiralKit

/// Generates a multi-page PDF report suitable for sharing with a healthcare provider.
///
/// **100% thread-safe.** Uses only Core Graphics + Core Text — zero UIKit drawing calls.
/// `NSAttributedString.draw()` internally dispatch_sync's to main thread even from
/// a background queue; this implementation uses `CTLineDraw` / `CTFrameDraw` instead,
/// which are pure C functions with no actor or thread affinity.
///
/// Page 1: Header with summary scores and date range.
/// Page 2: Biomarker estimates with confidence ranges + category breakdown.
/// Page 3: Disorder signatures + top recommendations.
/// Footer on every page: disclaimer and generation timestamp.
enum PDFReportGenerator {

    // MARK: - Fixed Colors (CGColor for Core Text compatibility)

    private static let pdfBlack: CGColor      = UIColor.black.cgColor
    private static let pdfGray: CGColor       = UIColor(white: 0.45, alpha: 1).cgColor
    private static let pdfLightGray: CGColor  = UIColor(white: 0.65, alpha: 1).cgColor
    private static let pdfSeparator: CGColor  = UIColor(white: 0.80, alpha: 1).cgColor

    // MARK: - Localization Helper

    private static func loc(_ key: String, bundle: Bundle) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    // MARK: - Public API

    /// Generate a PDF `Data` blob from current analysis data.
    ///
    /// **Thread-safe.** Can be called from any dispatch queue — uses only
    /// Core Graphics and Core Text, no UIKit drawing.
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

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = pageRect
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        // ── Page 1: Summary ──────────────────────────────────────
        beginPage(ctx, rect: pageRect)
        var y = drawHeader(ctx, rect: pageRect, margin: margin, bundle: bundle)
        y = drawSummarySection(ctx, y: y, margin: margin, width: contentWidth,
                                analysis: analysis, consistency: consistency,
                                dateRange: dateRange, numDays: numDays, bundle: bundle)
        y = drawStatsSection(ctx, y: y, margin: margin, width: contentWidth,
                              stats: analysis.stats, bundle: bundle)
        drawFooter(ctx, rect: pageRect, margin: margin, page: 1, totalPages: 4, bundle: bundle)
        endPage(ctx)

        // ── Page 2: Biomarkers + Categories ─────────────────────
        beginPage(ctx, rect: pageRect)
        y = margin + 20
        y = drawBiomarkersSection(ctx, y: y, margin: margin, width: contentWidth,
                                   records: records, bundle: bundle)
        y = drawCategoriesSection(ctx, y: y, margin: margin, width: contentWidth,
                                   categories: analysis.categories, bundle: bundle)
        drawFooter(ctx, rect: pageRect, margin: margin, page: 2, totalPages: 4, bundle: bundle)
        endPage(ctx)

        // ── Page 3: Disorder Signatures + Recommendations ───────
        beginPage(ctx, rect: pageRect)
        y = margin + 20
        y = drawSignaturesSection(ctx, y: y, margin: margin, width: contentWidth,
                                   signatures: analysis.signatures, bundle: bundle)
        y = drawRecommendationsSection(ctx, y: y, margin: margin, width: contentWidth,
                                        recommendations: Array(analysis.recommendations.prefix(5)),
                                        bundle: bundle)
        drawFooter(ctx, rect: pageRect, margin: margin, page: 3, totalPages: 4, bundle: bundle)
        endPage(ctx)

        // ── Page 4: Glossary of Terms ─────────────────────────
        beginPage(ctx, rect: pageRect)
        y = margin + 20
        y = drawGlossarySection(ctx, y: y, margin: margin, width: contentWidth, bundle: bundle)
        drawFooter(ctx, rect: pageRect, margin: margin, page: 4, totalPages: 4, bundle: bundle)
        endPage(ctx)

        ctx.closePDF()
        return data as Data
    }

    // MARK: - Page Lifecycle

    /// Begin a PDF page, flip to UIKit-style coordinates (top-left origin, y↓).
    private static func beginPage(_ ctx: CGContext, rect: CGRect) {
        ctx.beginPDFPage(nil)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.height)
        ctx.scaleBy(x: 1, y: -1)
    }

    /// End the current PDF page.
    private static func endPage(_ ctx: CGContext) {
        ctx.restoreGState()
        ctx.endPDFPage()
    }

    // MARK: - Page 1 Sections

    private static func drawHeader(_ ctx: CGContext, rect: CGRect, margin: CGFloat, bundle: Bundle) -> CGFloat {
        let y: CGFloat = margin

        ctDrawLine(ctx, text: loc("pdf.report.title", bundle: bundle),
                   font: UIFont.systemFont(ofSize: 22, weight: .light), color: pdfBlack,
                   at: CGPoint(x: margin, y: y))

        ctDrawLine(ctx, text: loc("pdf.report.subtitle", bundle: bundle),
                   font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular), color: pdfGray,
                   at: CGPoint(x: margin, y: y + 28))

        // Separator line
        let lineY = y + 50
        ctx.setStrokeColor(pdfSeparator)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: lineY))
        ctx.addLine(to: CGPoint(x: rect.width - margin, y: lineY))
        ctx.strokePath()

        return lineY + 16
    }

    private static func drawSummarySection(
        _ ctx: CGContext,
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
        y = drawSectionTitle(ctx, loc("pdf.section.summary", bundle: bundle), at: y, margin: margin)
        let daysStr = loc("pdf.label.days", bundle: bundle)
        y = drawKeyValue(ctx, loc("pdf.label.period", bundle: bundle),
                         value: "\(dateRange) (\(numDays) \(daysStr))", at: y, margin: margin, width: width)
        let scoreLabel: String
        if let key = analysis.scoreKey {
            scoreLabel = loc("score.\(key.rawValue)", bundle: bundle)
        } else {
            scoreLabel = analysis.label
        }
        y = drawKeyValue(ctx, loc("pdf.label.composite", bundle: bundle),
                         value: "\(analysis.composite)/100 — \(scoreLabel)", at: y, margin: margin, width: width)

        if let c = consistency {
            let consistencyLabel = loc("pdf.consistency.\(c.label.rawValue)", bundle: bundle)
            y = drawKeyValue(ctx, loc("pdf.label.consistency", bundle: bundle),
                             value: "\(c.score)/100 — \(consistencyLabel)", at: y, margin: margin, width: width)
            if let delta = c.deltaVsPreviousWeek {
                let sign = delta >= 0 ? "+" : ""
                y = drawKeyValue(ctx, loc("pdf.label.weekDelta", bundle: bundle),
                                 value: "\(sign)\(String(format: "%.1f", delta))", at: y, margin: margin, width: width)
            }
        }

        let sri = analysis.stats.sri
        if sri > 0 {
            y = drawKeyValue(ctx, loc("pdf.label.sri", bundle: bundle),
                             value: String(format: "%.1f/100", sri), at: y, margin: margin, width: width)
        }

        y += 12
        return y
    }

    private static func drawStatsSection(
        _ ctx: CGContext,
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        stats: SleepStats,
        bundle: Bundle
    ) -> CGFloat {
        var y = startY
        y = drawSectionTitle(ctx, loc("pdf.section.stats", bundle: bundle), at: y, margin: margin)
        y = drawKeyValue(ctx, loc("pdf.label.meanDuration", bundle: bundle), value: String(format: "%.1f h", stats.meanSleepDuration), at: y, margin: margin, width: width)
        y = drawKeyValue(ctx, loc("pdf.label.meanAcrophase", bundle: bundle), value: SleepStatistics.formatHour(stats.meanAcrophase), at: y, margin: margin, width: width)
        y = drawKeyValue(ctx, loc("pdf.label.bedtimeSd", bundle: bundle), value: String(format: "%.2f h", stats.stdBedtime), at: y, margin: margin, width: width)
        y = drawKeyValue(ctx, loc("pdf.label.rhythmStability", bundle: bundle), value: String(format: "%.2f", stats.rhythmStability), at: y, margin: margin, width: width)
        y = drawKeyValue(ctx, loc("pdf.label.socialJetlag", bundle: bundle), value: formatJetlag(stats.socialJetlag), at: y, margin: margin, width: width)
        y = drawKeyValue(ctx, loc("pdf.label.meanR2", bundle: bundle), value: String(format: "%.3f", stats.meanR2), at: y, margin: margin, width: width)
        y += 12
        return y
    }

    // MARK: - Page 2 Sections

    private static func drawBiomarkersSection(
        _ ctx: CGContext,
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        records: [SleepRecord],
        bundle: Bundle
    ) -> CGFloat {
        var y = startY
        y = drawSectionTitle(ctx, loc("pdf.section.biomarkers", bundle: bundle), at: y, margin: margin)

        guard let lastRecord = records.last else {
            y = drawBody(ctx, loc("pdf.body.biomarkersInsufficient", bundle: bundle), at: y, margin: margin, width: width)
            return y + 16
        }

        let biomarkers = BiomarkerEstimation.estimatePersonalized(from: lastRecord)
        let rangeLabel = loc("pdf.label.range", bundle: bundle)
        for bm in biomarkers {
            var valueStr = SleepStatistics.formatHour(bm.hour)
            if let lo = bm.confidenceLow, let hi = bm.confidenceHigh {
                valueStr += "  (\(rangeLabel) \(SleepStatistics.formatHour(lo))–\(SleepStatistics.formatHour(hi)))"
            }
            y = drawKeyValue(ctx, bm.label, value: valueStr, at: y, margin: margin, width: width)
        }

        y = drawBody(ctx, loc("pdf.body.biomarkersNote", bundle: bundle), at: y + 4, margin: margin, width: width)
        y += 16
        return y
    }

    private static func drawCategoriesSection(
        _ ctx: CGContext,
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        categories: [CategoryScore],
        bundle: Bundle
    ) -> CGFloat {
        var y = startY
        y = drawSectionTitle(ctx, loc("pdf.section.categories", bundle: bundle), at: y, margin: margin)

        for cat in categories {
            let bar = String(repeating: "█", count: cat.score / 10)
            let empty = String(repeating: "░", count: 10 - cat.score / 10)
            let catLabel: String
            if let key = cat.labelKey {
                catLabel = loc("category.\(key.rawValue)", bundle: bundle)
            } else {
                catLabel = cat.label
            }
            y = drawKeyValue(ctx, catLabel, value: "\(bar)\(empty) \(cat.score)/100", at: y, margin: margin, width: width)
        }

        y += 16
        return y
    }

    // MARK: - Page 3 Sections

    private static func drawSignaturesSection(
        _ ctx: CGContext,
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        signatures: [DisorderSignature],
        bundle: Bundle
    ) -> CGFloat {
        var y = startY
        y = drawSectionTitle(ctx, loc("pdf.section.patterns", bundle: bundle), at: y, margin: margin)

        if signatures.isEmpty {
            y = drawBody(ctx, loc("pdf.body.noPatternsDetected", bundle: bundle), at: y, margin: margin, width: width)
        } else {
            for sig in signatures {
                let confStr = String(format: "%.0f%%", sig.confidence * 100)
                let confLabel = String(format: loc("pdf.body.confidence", bundle: bundle), confStr)
                let sigLabel = loc("pdf.disorder.\(sig.id)", bundle: bundle)
                y = drawKeyValue(ctx, sigLabel, value: confLabel, at: y, margin: margin, width: width)
                let sigDesc = loc("pdf.disorder.desc.\(sig.id)", bundle: bundle)
                y = drawBody(ctx, sigDesc, at: y, margin: margin, width: width)
                y += 4
            }
        }

        y += 16
        return y
    }

    private static func drawRecommendationsSection(
        _ ctx: CGContext,
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        recommendations: [Recommendation],
        bundle: Bundle
    ) -> CGFloat {
        var y = startY
        y = drawSectionTitle(ctx, loc("pdf.section.recommendations", bundle: bundle), at: y, margin: margin)

        if recommendations.isEmpty {
            y = drawBody(ctx, loc("pdf.body.noRecommendations", bundle: bundle), at: y, margin: margin, width: width)
        } else {
            for (i, rec) in recommendations.enumerated() {
                let recTitle: String
                let recText: String
                if let key = rec.key {
                    recTitle = loc("rec.\(key.rawValue).title", bundle: bundle)
                    let fmt = loc("rec.\(key.rawValue).text", bundle: bundle)
                    if rec.args.isEmpty {
                        recText = fmt
                    } else if key == .reduceSocialJetlag || key == .minimizeWeekendLag {
                        recText = String(format: fmt, formatJetlag(rec.args[0]))
                    } else {
                        recText = String(format: fmt, arguments: rec.args.map { $0 as CVarArg })
                    }
                } else {
                    recTitle = rec.title
                    recText = rec.text
                }
                let bullet = "\(i + 1). \(recTitle)"
                y = drawBullet(ctx, bullet, detail: recText, at: y, margin: margin, width: width)
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

        ctx.setStrokeColor(pdfSeparator)
        ctx.setLineWidth(0.3)
        ctx.move(to: CGPoint(x: margin, y: footerY - 6))
        ctx.addLine(to: CGPoint(x: rect.width - margin, y: footerY - 6))
        ctx.strokePath()

        let footerFont = UIFont.monospacedSystemFont(ofSize: 7, weight: .regular)

        ctDrawLine(ctx, text: loc("pdf.footer.disclaimer", bundle: bundle),
                   font: footerFont, color: pdfLightGray,
                   at: CGPoint(x: margin, y: footerY))

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let pageLabel = String(format: loc("pdf.footer.page", bundle: bundle), "\(page)", "\(totalPages)")
        let pageText = "\(pageLabel) · \(dateStr)"
        let pageWidth = ctTextWidth(pageText, font: footerFont)
        ctDrawLine(ctx, text: pageText,
                   font: footerFont, color: pdfLightGray,
                   at: CGPoint(x: rect.width - margin - pageWidth, y: footerY))
    }

    // MARK: - Core Text Drawing Primitives (100% thread-safe)

    /// Draw a single line of text at a point (UIKit-style coordinates).
    /// Uses CTLineDraw — a pure C function with no main-thread requirement.
    private static func ctDrawLine(
        _ ctx: CGContext,
        text: String,
        font: UIFont,
        color: CGColor,
        at point: CGPoint
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)

        var ascent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, nil, nil)

        ctx.saveGState()
        // In our flipped context, glyphs need a flipped text matrix to appear upright.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        // Baseline = point.y + ascent (so top of text aligns with point.y).
        ctx.textPosition = CGPoint(x: point.x, y: point.y + ascent)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// Measure the width of a single-line text string.
    private static func ctTextWidth(_ text: String, font: UIFont) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Draw multi-line text inside a rect, returning the actual height used.
    /// Uses CTFramesetterCreateFrame + CTFrameDraw — pure Core Text, no UIKit drawing.
    private static func ctDrawMultiline(
        _ ctx: CGContext,
        text: String,
        font: UIFont,
        color: CGColor,
        rect: CGRect
    ) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)

        // Measure how much height the text actually needs.
        var fitRange = CFRange()
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attrStr.length),
            nil,
            CGSize(width: rect.width, height: rect.height),
            &fitRange
        )
        let textHeight = ceil(suggestedSize.height)

        // CTFrameDraw uses CG coordinates (bottom-left origin). Our context is flipped,
        // so we locally un-flip a region for the frame.
        ctx.saveGState()
        ctx.translateBy(x: rect.origin.x, y: rect.origin.y + textHeight)
        ctx.scaleBy(x: 1, y: -1)

        // CRITICAL: textMatrix is NOT part of the graphics state — saveGState/restoreGState
        // do NOT preserve it. ctDrawLine sets textMatrix to scaleY:-1; if CTFrameDraw
        // inherits that, glyphs render upside-down. Reset to identity for CG-native drawing.
        ctx.textMatrix = .identity

        let localPath = CGPath(rect: CGRect(x: 0, y: 0, width: rect.width, height: textHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: fitRange.length), localPath, nil)
        CTFrameDraw(frame, ctx)

        ctx.restoreGState()
        return textHeight
    }

    // MARK: - High-Level Drawing Helpers

    private static func formatJetlag(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static func drawSectionTitle(_ ctx: CGContext, _ text: String, at y: CGFloat, margin: CGFloat) -> CGFloat {
        ctDrawLine(ctx, text: text,
                   font: UIFont.systemFont(ofSize: 14, weight: .semibold), color: pdfBlack,
                   at: CGPoint(x: margin, y: y))
        return y + 22
    }

    private static func drawKeyValue(_ ctx: CGContext, _ key: String, value: String, at y: CGFloat, margin: CGFloat, width: CGFloat) -> CGFloat {
        ctDrawLine(ctx, text: key,
                   font: UIFont.monospacedSystemFont(ofSize: 9, weight: .medium), color: pdfGray,
                   at: CGPoint(x: margin, y: y))
        ctDrawLine(ctx, text: value,
                   font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular), color: pdfBlack,
                   at: CGPoint(x: margin + width * 0.45, y: y))
        return y + 16
    }

    private static func drawBody(_ ctx: CGContext, _ text: String, at y: CGFloat, margin: CGFloat, width: CGFloat) -> CGFloat {
        let h = ctDrawMultiline(ctx, text: text,
                                font: UIFont.systemFont(ofSize: 8), color: pdfGray,
                                rect: CGRect(x: margin, y: y, width: width, height: 200))
        return y + h + 6
    }

    private static func drawBullet(_ ctx: CGContext, _ title: String, detail: String, at y: CGFloat, margin: CGFloat, width: CGFloat) -> CGFloat {
        ctDrawLine(ctx, text: title,
                   font: UIFont.systemFont(ofSize: 9, weight: .medium), color: pdfBlack,
                   at: CGPoint(x: margin + 8, y: y))
        var nextY = y + 14

        let h = ctDrawMultiline(ctx, text: detail,
                                font: UIFont.systemFont(ofSize: 8), color: pdfGray,
                                rect: CGRect(x: margin + 16, y: nextY, width: width - 16, height: 200))
        nextY += h + 8
        return nextY
    }

    // MARK: - Page 4: Glossary

    private static func drawGlossarySection(
        _ ctx: CGContext,
        y startY: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        bundle: Bundle
    ) -> CGFloat {
        var y = startY
        y = drawSectionTitle(ctx, loc("pdf.section.glossary", bundle: bundle), at: y, margin: margin)

        let terms = [
            "pdf.glossary.dlmo",
            "pdf.glossary.car",
            "pdf.glossary.tmin",
            "pdf.glossary.pld",
            "pdf.glossary.sri",
            "pdf.glossary.composite",
            "pdf.glossary.consistency",
            "pdf.glossary.r2",
            "pdf.glossary.acrophase",
            "pdf.glossary.socialJetlag",
            "pdf.glossary.rhythmStability",
        ]

        for key in terms {
            let text = loc(key, bundle: bundle)
            let h = ctDrawMultiline(ctx, text: text,
                                    font: UIFont.systemFont(ofSize: 8), color: pdfGray,
                                    rect: CGRect(x: margin, y: y, width: width, height: 120))
            y += h + 6
        }

        return y
    }
}
