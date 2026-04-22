import SwiftUI
import SpiralKit

struct ModeHeaderView: View {
    let selectedMode: Int
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        Text(headerText)
            .font(.title3.weight(.semibold))
            .foregroundStyle(SpiralColors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .id(selectedMode)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: selectedMode)
    }

    private var headerText: String {
        switch selectedMode {
        case 0: return torusHeader
        case 1: return spiralHeader
        case 2: return dnaHeader
        default: return ""
        }
    }

    private var torusHeader: String {
        // Pick the most recent record that actually looks like a full
        // sleep block (≥ 3h). Using `store.records.last` directly picked
        // up naps and accidentally-registered 12-min entries, which is
        // why the header was showing things like "Anoche · 0.2h" even
        // when the user had slept a full night.
        let main = store.records.last(where: { $0.sleepDuration >= 3.0 })
            ?? store.records.last
        guard let main else {
            return String(localized: "mode.torus.no_data", bundle: bundle)
        }
        let hours = String(format: "%.1f", main.sleepDuration)
        return "\(String(localized: "mode.torus.last_night", bundle: bundle)) · \(hours)h"
    }

    private var spiralHeader: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 21 || hour < 6 {
            return String(localized: "mode.spiral.good_night", bundle: bundle)
        } else if hour < 12 {
            return String(localized: "mode.spiral.good_morning", bundle: bundle)
        } else {
            return String(localized: "mode.spiral.good_afternoon", bundle: bundle)
        }
    }

    private var dnaHeader: String {
        String(localized: "mode.dna.header", bundle: bundle)
    }
}
