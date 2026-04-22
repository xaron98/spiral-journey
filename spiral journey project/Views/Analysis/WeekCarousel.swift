import SwiftUI
import SpiralKit

/// Horizontal chip carousel for selecting which week the Trends tab
/// should focus on. The newest chip is rightmost (S current); older
/// weeks scroll off to the left. When the set of available weeks is
/// wider than the screen, the chip row is horizontally scrollable.
///
/// Taps update `selectedOffset` (0 = this week, 1 = last week, …).
struct WeekCarousel: View {
    /// Total number of complete 7-night windows the data covers
    /// (minimum 1). Determines how many chips are shown.
    let availableWeeks: Int
    /// 0 = current week, 1 = previous, …
    @Binding var selectedOffset: Int

    @Environment(\.languageBundle) private var bundle

    private var entries: [Entry] {
        guard availableWeeks > 0 else { return [] }
        let today = Date()
        let cal = Calendar.current
        return (0..<availableWeeks).map { offset in
            let date = cal.date(byAdding: .weekOfYear, value: -offset, to: today) ?? today
            let week = cal.component(.weekOfYear, from: date)
            return Entry(offset: offset, label: "S\(week)")
        }
    }

    private struct Entry: Identifiable {
        let offset: Int
        let label: String
        var id: Int { offset }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Oldest first → newest last so the current week sits
                    // at the trailing edge, matching the reading order.
                    ForEach(entries.reversed()) { entry in
                        chip(entry)
                            .id(entry.offset)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
            .onAppear {
                proxy.scrollTo(selectedOffset, anchor: .trailing)
            }
            .onChange(of: selectedOffset) { _, new in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func chip(_ entry: Entry) -> some View {
        let isSelected = entry.offset == selectedOffset
        return Button {
            selectedOffset = entry.offset
        } label: {
            Text(entry.label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isSelected ? .white : SpiralColors.subtle)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected
                    ? AnyShapeStyle(SpiralColors.accent.opacity(0.25))
                    : AnyShapeStyle(Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? SpiralColors.accent.opacity(0.45) : Color.clear,
                                lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: String(localized: "analysis.week.a11yLabel", bundle: bundle), entry.label))
        .accessibilityHint(String(localized: "analysis.week.a11yHint", bundle: bundle))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
