import SwiftUI
import SpiralKit
import struct SpiralGeometry.WearableSleepSample
import struct SpiralGeometry.WearableTo4DMapper
import struct SpiralGeometry.SleepTrajectoryAnalysis
import enum SpiralGeometry.Tesseract
import enum SpiralGeometry.CliffordTorus

struct NeuroSpiralExportView: View {
    let samples: [WearableSleepSample]
    let analysis: SleepTrajectoryAnalysis

    @Environment(\.languageBundle) private var bundle
    @State private var csvURL: URL?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                summaryCard
                previewCard
                exportButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(loc("neurospiral.export.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { generateCSV() }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("neurospiral.export.summary"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            HStack {
                Label("\(samples.count) epochs", systemImage: "waveform")
                Spacer()
                Label("\(analysis.trajectory.count) points", systemImage: "circle.dotted")
            }
            .font(.caption)
            .foregroundStyle(SpiralColors.muted)

            if let first = samples.first, let last = samples.last {
                HStack {
                    Text(first.timestamp, style: .date)
                    Text("→")
                    Text(last.timestamp, style: .date)
                }
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("neurospiral.export.preview"))
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            Text("timestamp,hrv,hr,motion,phase,θ,φ,vertex,code,ω₁,ω₂")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)

            ForEach(0..<min(3, samples.count), id: \.self) { i in
                Text(buildPreviewRow(index: i))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(SpiralColors.text.opacity(0.7))
                    .lineLimit(1)
            }

            if samples.count > 3 {
                Text("… \(samples.count - 3) " + loc("neurospiral.export.more_rows"))
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.muted)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Group {
            if let csvURL {
                ShareLink(item: csvURL) {
                    Label(loc("neurospiral.export.share"), systemImage: "square.and.arrow.up")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SpiralColors.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            } else {
                ProgressView()
                    .padding()
            }
        }
    }

    // MARK: - CSV Generation

    private func generateCSV() {
        let mapper = WearableTo4DMapper()
        let isoFormatter = ISO8601DateFormatter()
        var rows = "timestamp_iso,hrv_ms,heart_rate_bpm,motion_intensity,sleep_phase,theta,phi,vertex_idx,vertex_code,omega1,omega2\n"

        var prevAngles: (Double, Double)?

        for sample in samples {
            let point = mapper.map(sample)
            let (theta, phi) = CliffordTorus.angles(of: point)
            let vertex = Tesseract.discretize(point)

            var omega1 = 0.0, omega2 = 0.0
            if let prev = prevAngles {
                omega1 = abs(CliffordTorus.wrapAngle(theta - prev.0))
                omega2 = abs(CliffordTorus.wrapAngle(phi - prev.1))
            }
            prevAngles = (theta, phi)

            let phase: String
            switch sample.sleepStage {
            case .deep: phase = "deep"
            case .rem: phase = "rem"
            case .core: phase = "light"
            case .awake: phase = "awake"
            case .none: phase = "unknown"
            }

            let code = formatCode(vertex.code)
            let ts = isoFormatter.string(from: sample.timestamp)
            rows += "\(ts),\(String(format: "%.1f", sample.hrv)),\(String(format: "%.1f", sample.heartRate)),\(String(format: "%.3f", sample.motionIntensity)),\(phase),\(String(format: "%.4f", theta)),\(String(format: "%.4f", phi)),\(vertex.index),\(code),\(String(format: "%.4f", omega1)),\(String(format: "%.4f", omega2))\n"
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("neurospiral_export_\(Int(Date().timeIntervalSince1970)).csv")
        try? rows.write(to: fileURL, atomically: true, encoding: .utf8)
        csvURL = fileURL
    }

    private func buildPreviewRow(index i: Int) -> String {
        let sample = samples[i]
        let mapper = WearableTo4DMapper()
        let point = mapper.map(sample)
        let (theta, phi) = CliffordTorus.angles(of: point)
        let vertex = Tesseract.discretize(point)
        let ts = ISO8601DateFormatter().string(from: sample.timestamp)
        return "\(ts),\(String(format: "%.1f", sample.hrv)),\(String(format: "%.1f", sample.heartRate)),...,\(vertex.index)"
    }

    private func formatCode(_ code: SIMD4<Int>) -> String {
        let fmt: (Int) -> String = { $0 > 0 ? "+" : "-" }
        return "\(fmt(code.x))\(fmt(code.y))\(fmt(code.z))\(fmt(code.w))"
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
