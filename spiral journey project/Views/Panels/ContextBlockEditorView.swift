import SwiftUI
import SpiralKit

/// Sheet for adding or editing a context block (work, study, commute, etc.).
struct ContextBlockEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    /// Nil when adding a new block; populated when editing an existing one.
    let existing: ContextBlock?
    let onSave: (ContextBlock) -> Void

    @State private var blockType: ContextBlockType = .work
    @State private var label: String = ""
    @State private var startHour: Double = 9.0
    @State private var endHour: Double = 17.0
    @State private var activeDays: UInt8 = ContextBlock.weekdays

    // Day labels (Mon → Sun matching bitmask bit 1…6, 0)
    private let dayLabels = ["D", "L", "M", "X", "J", "V", "S"]

    init(existing: ContextBlock? = nil, onSave: @escaping (ContextBlock) -> Void) {
        self.existing = existing
        self.onSave = onSave
        if let e = existing {
            _blockType = State(initialValue: e.type)
            _label = State(initialValue: e.label)
            _startHour = State(initialValue: e.startHour)
            _endHour = State(initialValue: e.endHour)
            _activeDays = State(initialValue: e.activeDays)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Block type ──
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("context.editor.type")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(ContextBlockType.allCases, id: \.self) { type in
                                    Button {
                                        blockType = type
                                        if label.isEmpty {
                                            label = defaultLabel(for: type)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: type.sfSymbol)
                                                .font(.system(size: 10))
                                            Text(typeDisplayName(type))
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(blockType == type ? SpiralColors.contextPrimary.opacity(0.2) : SpiralColors.border)
                                        .foregroundStyle(blockType == type ? SpiralColors.contextPrimary : SpiralColors.muted)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // ── Label ──
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("context.editor.label")
                        TextField(
                            String(localized: "context.editor.labelPlaceholder", bundle: bundle),
                            text: $label
                        )
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                        .padding(8)
                        .background(SpiralColors.border)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // ── Start hour ──
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            sectionLabel("context.editor.start")
                            Spacer()
                            Text(formatHour(startHour))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SpiralColors.contextPrimary)
                        }
                        Slider(value: $startHour, in: 0...23.75, step: 0.25)
                            .tint(SpiralColors.contextPrimary)
                    }

                    // ── End hour ──
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            sectionLabel("context.editor.end")
                            Spacer()
                            Text(formatHour(endHour))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SpiralColors.contextPrimary)
                        }
                        Slider(value: $endHour, in: 0...23.75, step: 0.25)
                            .tint(SpiralColors.contextPrimary)
                    }

                    // ── Active days ──
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("context.editor.days")
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { bit in
                                let isOn = activeDays & (1 << bit) != 0
                                Button {
                                    activeDays ^= (1 << bit)
                                } label: {
                                    Text(dayLabels[bit])
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .frame(width: 32, height: 32)
                                        .background(isOn ? SpiralColors.contextPrimary.opacity(0.2) : SpiralColors.border)
                                        .foregroundStyle(isOn ? SpiralColors.contextPrimary : SpiralColors.muted)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Quick presets
                        HStack(spacing: 8) {
                            presetButton("L-V", mask: ContextBlock.weekdays)
                            presetButton("S-D", mask: ContextBlock.weekends)
                            presetButton("L-D", mask: ContextBlock.everyDay)
                        }
                    }

                    // ── Duration preview ──
                    let dur = durationText()
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(SpiralColors.muted)
                        Text(dur)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
                .padding(16)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(existing != nil
                ? String(localized: "context.editor.editTitle", bundle: bundle)
                : String(localized: "context.editor.addTitle", bundle: bundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "context.editor.cancel", bundle: bundle)) {
                        dismiss()
                    }
                    .foregroundStyle(SpiralColors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "context.editor.save", bundle: bundle)) {
                        let block = ContextBlock(
                            id: existing?.id ?? UUID(),
                            type: blockType,
                            label: label.isEmpty ? defaultLabel(for: blockType) : label,
                            startHour: startHour,
                            endHour: endHour,
                            activeDays: activeDays,
                            calendarEventID: existing?.calendarEventID,
                            isEnabled: existing?.isEnabled ?? true
                        )
                        onSave(block)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(SpiralColors.contextPrimary)
                    .disabled(activeDays == 0)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionLabel(_ key: String) -> some View {
        Text(String(localized: String.LocalizationValue(key), bundle: bundle))
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(SpiralColors.muted)
            .textCase(.uppercase)
    }

    private func presetButton(_ text: String, mask: UInt8) -> some View {
        Button {
            activeDays = mask
        } label: {
            Text(text)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(activeDays == mask ? SpiralColors.contextPrimary.opacity(0.15) : SpiralColors.border)
                .foregroundStyle(activeDays == mask ? SpiralColors.contextPrimary : SpiralColors.muted)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func formatHour(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        let hh = (total / 60) % 24
        let mm = total % 60
        return String(format: "%02d:%02d", hh, mm)
    }

    private func durationText() -> String {
        let d = endHour - startHour
        let hours = d >= 0 ? d : d + 24.0
        return String(format: "%.0fh %02dmin", floor(hours), Int((hours - floor(hours)) * 60))
    }

    private func typeDisplayName(_ type: ContextBlockType) -> String {
        String(localized: String.LocalizationValue(type.localizationKey), bundle: bundle)
    }

    private func defaultLabel(for type: ContextBlockType) -> String {
        typeDisplayName(type)
    }
}
