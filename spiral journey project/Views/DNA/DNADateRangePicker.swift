import SwiftUI

/// Sheet that lets the user restrict the 3D helix hero to a specific
/// window of dates. Presented from the DNA tab's calendar button.
///
/// The picker stays schedule-agnostic — "last month" or "March only" are
/// both valid slices. The only invariant enforced is `from <= to`. Tapping
/// "Quitar filtro" clears any existing range and reverts the helix to its
/// full history view.
struct DNADateRangePicker: View {

    /// Currently applied range (or nil when the helix shows everything).
    let initialRange: (from: Date, to: Date)?
    /// Bounds from the user's actual record history — the pickers are
    /// clamped to this range so empty days outside the data are unselectable.
    let availableRange: ClosedRange<Date>
    /// Invoked with a validated range when the user taps "Aplicar".
    let onApply: ((from: Date, to: Date)?) -> Void
    let onCancel: () -> Void

    @Environment(\.languageBundle) private var bundle
    @State private var fromDate: Date
    @State private var toDate: Date

    init(initialRange: (from: Date, to: Date)?,
         availableRange: ClosedRange<Date>,
         onApply: @escaping ((from: Date, to: Date)?) -> Void,
         onCancel: @escaping () -> Void) {
        self.initialRange = initialRange
        self.availableRange = availableRange
        self.onApply = onApply
        self.onCancel = onCancel
        _fromDate = State(initialValue: initialRange?.from ?? availableRange.lowerBound)
        _toDate = State(initialValue: initialRange?.to ?? availableRange.upperBound)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(loc("dna.range.from"),
                               selection: $fromDate,
                               in: availableRange,
                               displayedComponents: .date)
                    DatePicker(loc("dna.range.to"),
                               selection: $toDate,
                               in: availableRange,
                               displayedComponents: .date)
                } footer: {
                    Text(loc("dna.range.footer"))
                        .font(.caption2)
                        .foregroundStyle(SpiralColors.muted)
                }

                // Quick presets so the user doesn't have to click through a
                // calendar for common windows.
                Section(loc("dna.range.presets")) {
                    presetRow(days: 7, label: loc("dna.range.preset.week"))
                    presetRow(days: 30, label: loc("dna.range.preset.month"))
                    presetRow(days: 90, label: loc("dna.range.preset.quarter"))
                }

                if initialRange != nil {
                    Section {
                        Button(role: .destructive) {
                            onApply(nil)
                        } label: {
                            Label(loc("dna.range.clear"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle(loc("dna.range.title"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("common.cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("common.apply")) {
                        // Normalize so `from <= to` even if the user picked
                        // them out of order — nobody benefits from an empty
                        // filter because of a typo.
                        let lo = min(fromDate, toDate)
                        let hi = max(fromDate, toDate)
                        onApply((from: lo, to: hi))
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func presetRow(days: Int, label: String) -> some View {
        Button {
            let upper = availableRange.upperBound
            let lower = Calendar.current.date(byAdding: .day, value: -days, to: upper)
                ?? availableRange.lowerBound
            fromDate = max(lower, availableRange.lowerBound)
            toDate = upper
        } label: {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(SpiralColors.accent)
                Text(label)
                    .foregroundStyle(SpiralColors.text)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
