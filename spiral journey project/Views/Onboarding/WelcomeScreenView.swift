import SwiftUI

/// Full-screen welcome shown on first launch before the tutorial overlay.
/// Displays the app icon, name, and a language selector so the tutorial
/// already appears in the chosen language.
struct WelcomeScreenView: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    /// Called when the user taps Continue.
    var onContinue: () -> Void

    var body: some View {
        @Bindable var store = store

        ZStack {
            SpiralColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Logo + name ──────────────────────────────────────────────
                VStack(spacing: 16) {
                    Image("AppIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: SpiralColors.accent.opacity(0.35), radius: 20)

                    Text("Spiral Journey")
                        .font(.system(size: 28, weight: .light, design: .default))
                        .foregroundStyle(SpiralColors.accent)

                    Text(String(localized: "welcome.subtitle", bundle: bundle))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(SpiralColors.muted)
                        .textCase(.uppercase)
                }

                Spacer()

                // ── Language selector ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "welcome.chooseLanguage", bundle: bundle))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(SpiralColors.muted)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ],
                        spacing: 8
                    ) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    store.language = lang
                                }
                            } label: {
                                Text(lang.nativeName)
                                    .font(.system(size: 13, weight: store.language == lang ? .semibold : .regular))
                                    .foregroundStyle(store.language == lang ? .black : SpiralColors.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(store.language == lang
                                                  ? SpiralColors.accent
                                                  : SpiralColors.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(store.language == lang
                                                    ? SpiralColors.accent
                                                    : SpiralColors.border,
                                                    lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)

                // ── Continue button ──────────────────────────────────────────
                Button(action: onContinue) {
                    Text(String(localized: "welcome.continue", bundle: bundle))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(SpiralColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)

                Spacer().frame(height: 16)

                Text(String(localized: "onboarding.disclaimer", bundle: bundle))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 32)
            }
        }
        .transition(.opacity)
    }
}
