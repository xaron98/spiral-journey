import SwiftUI
import SpiralKit

struct DateRangeSettingsView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        @Bindable var store = store
        let hasHealthKitData = store.sleepEpisodes.contains { $0.source == .healthKit }
        ScrollView {
            VStack(spacing: 0) {
                if hasHealthKitData {
                    HStack {
                        Text(String(localized: "settings.dataRange.startDate", bundle: bundle))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                        Text(store.startDate, style: .date)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.text)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    Divider().background(SpiralColors.border.opacity(0.5))

                    HStack {
                        Text(String(localized: "settings.dataRange.days", bundle: bundle))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                        Text(String(format: String(localized: "settings.dataRange.daysValue", bundle: bundle), store.numDays))
                            .font(.subheadline.weight(.semibold).monospaced())
                            .foregroundStyle(SpiralColors.text)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    Divider().background(SpiralColors.border.opacity(0.5))

                    Text(String(localized: "settings.dataRange.autoNote", bundle: bundle))
                        .font(.caption.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                } else {
                    DatePicker(
                        String(localized: "settings.dataRange.startDate", bundle: bundle),
                        selection: $store.startDate,
                        displayedComponents: .date
                    )
                    .font(.subheadline.monospaced())
                    .foregroundStyle(SpiralColors.text)
                    .datePickerStyle(.compact)
                    .tint(SpiralColors.accent)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    Divider().background(SpiralColors.border.opacity(0.5))

                    HStack {
                        Text(String(localized: "settings.dataRange.days", bundle: bundle))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                        Stepper("\(store.numDays)", value: $store.numDays, in: 3...90).labelsHidden()
                        Text(String(format: String(localized: "settings.dataRange.daysValue", bundle: bundle), store.numDays))
                            .font(.subheadline.weight(.semibold).monospaced())
                            .foregroundStyle(SpiralColors.text)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
            }
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "settings.dataRange.title", bundle: bundle))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
