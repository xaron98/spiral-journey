import SwiftUI
import SpiralKit

struct AboutView: View {
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Spiral Journey")
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(SpiralColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                Divider().background(SpiralColors.border.opacity(0.5))

                Text(String(localized: "settings.about.description", bundle: bundle))
                    .font(.subheadline)
                    .foregroundStyle(SpiralColors.muted)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                Divider().background(SpiralColors.border.opacity(0.5))

                Text(String(localized: "settings.about.philosophy", bundle: bundle))
                    .font(.subheadline)
                    .foregroundStyle(SpiralColors.muted)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
            }
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "settings.about.title", bundle: bundle))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
