import SwiftUI
import SpiralKit

struct LanguagePickerView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Button {
                        store.language = lang
                        UserDefaults(suiteName: "group.xaron.spiral-journey-project")?
                            .set(true, forKey: "userChoseLanguageExplicitly")
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lang == .system
                                     ? String(localized: "settings.language.system", bundle: bundle)
                                     : lang.nativeName)
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(store.language == lang ? SpiralColors.accent : SpiralColors.text)
                                if lang == .system {
                                    Text(Locale.current.localizedString(forLanguageCode: AppLanguage.resolvedSystemLocale) ?? AppLanguage.resolvedSystemLocale)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(SpiralColors.muted)
                                }
                            }
                            Spacer()
                            if store.language == lang {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.accent)
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if lang != AppLanguage.allCases.last {
                        Divider().background(SpiralColors.border.opacity(0.5))
                    }
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "settings.language.title", bundle: bundle))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
