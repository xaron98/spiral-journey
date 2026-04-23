import SwiftUI
import SpiralKit
#if canImport(UserNotifications)
import UserNotifications
#endif

struct CoachPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    @State private var targetHour: Double = 1.5   // 01:30, replaced on appear
    @State private var reminderScheduled = false
    @State private var reminderError: ReminderError?

    private enum ReminderError {
        case denied, failed, unsupported
    }

    private var adapter: CoachDataAdapter { CoachDataAdapter(store: store, bundle: bundle) }

    var body: some View {
        ZStack(alignment: .bottom) {
            CoachTokens.bg.ignoresSafeArea()
            RadialGradient(colors: [CoachTokens.purple.opacity(0.25), .clear],
                           center: UnitPoint(x: 0.5, y: -0.2),
                           startRadius: 40, endRadius: 260)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 0) {
                    header
                    dialSection
                    headline
                    preparationList
                    Spacer().frame(height: 120)
                }
            }

            bottomCTA
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: initializeTargetHour)
        .onChange(of: targetHour) { _, _ in
            // Drag invalidates any previously scheduled reminder.
            if reminderScheduled { reminderScheduled = false }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(CoachTokens.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CoachTokens.border))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
            Text(String(localized: "coach.plan.header", bundle: bundle))
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(1)
            Spacer()
            Color.clear.frame(width: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var dialSection: some View {
        ZStack {
            CoachTargetDialView(size: 240, targetHour: $targetHour)
            VStack(spacing: -2) {
                Text(String(localized: "coach.plan.bedtimeAt", bundle: bundle))
                    .font(CoachTokens.mono(10))
                    .foregroundStyle(CoachTokens.purple)
                    .tracking(1.5)
                Text(formatTarget(targetHour))
                    .font(CoachTokens.mono(56, weight: .bold))
                    .tracking(-2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, CoachTokens.purple],
                            startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: targetHour)
                Text(countdownLabel(to: targetHour))
                    .font(CoachTokens.mono(11))
                    .foregroundStyle(CoachTokens.textDim)
            }
            .allowsHitTesting(false)
        }
        .padding(.top, 30)
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Text(String(localized: "coach.plan.headline", bundle: bundle))
                .font(CoachTokens.sans(19, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text(String(localized: "coach.plan.description", bundle: bundle))
                .font(CoachTokens.sans(13))
                .multilineTextAlignment(.center)
                .foregroundStyle(CoachTokens.textDim)
                .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }

    private var preparationList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "coach.plan.preparation", bundle: bundle))
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(1)
                .padding(.leading, 4)
                .padding(.bottom, 6)

            ForEach(steps, id: \.minutesBefore) { step in
                HStack(spacing: 10) {
                    Text(formatTarget(targetHour - step.minutesBefore / 60.0))
                        .font(CoachTokens.mono(13, weight: .semibold))
                        .foregroundStyle(step.color)
                        .frame(width: 52, alignment: .leading)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.15), value: targetHour)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.label)
                            .font(CoachTokens.sans(13, weight: .medium))
                            .foregroundStyle(.white)
                        Text(step.detail)
                            .font(CoachTokens.sans(11))
                            .foregroundStyle(CoachTokens.textDim)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(stepBackground(step))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(step.highlight ? CoachTokens.purple.opacity(0.35) : CoachTokens.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    @ViewBuilder
    private func stepBackground(_ step: Step) -> some View {
        if step.highlight {
            LinearGradient(
                colors: [CoachTokens.purple.opacity(0.18), CoachTokens.card],
                startPoint: .leading, endPoint: .trailing)
        } else {
            CoachTokens.card
        }
    }

    private var bottomCTA: some View {
        VStack(spacing: 6) {
            if let error = reminderError {
                Text(reminderErrorMessage(error))
                    .font(CoachTokens.sans(11))
                    .foregroundStyle(CoachTokens.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(CoachTokens.red.opacity(0.15))
                    .clipShape(Capsule())
            }

            Button { toggleReminder() } label: {
                HStack(spacing: 8) {
                    if reminderScheduled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(String(localized: reminderScheduled
                                ? "coach.plan.cta.reminderActive"
                                : "coach.plan.cta.enableReminder",
                                bundle: bundle))
                        .font(CoachTokens.sans(14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(LinearGradient(
                    colors: reminderScheduled
                        ? [CoachTokens.green, CoachTokens.green.opacity(0.6)]
                        : [CoachTokens.purple, CoachTokens.purpleDeep],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }
        }
        .padding(6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial)
                Color(hex: "1E1E3C").opacity(0.72)
            })
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    // MARK: Data

    private var steps: [Step] {
        [
            .init(minutesBefore: 60,
                  label: String(localized: "coach.plan.step1.label", bundle: bundle),
                  detail: String(localized: "coach.plan.step1.detail", bundle: bundle),
                  color: CoachTokens.yellow, highlight: false),
            .init(minutesBefore: 30,
                  label: String(localized: "coach.plan.step2.label", bundle: bundle),
                  detail: String(localized: "coach.plan.step2.detail", bundle: bundle),
                  color: CoachTokens.yellow, highlight: false),
            .init(minutesBefore: 10,
                  label: String(localized: "coach.plan.step3.label", bundle: bundle),
                  detail: String(localized: "coach.plan.step3.detail", bundle: bundle),
                  color: CoachTokens.purple, highlight: false),
            .init(minutesBefore: 0,
                  label: String(localized: "coach.plan.step4.label", bundle: bundle),
                  detail: String(localized: "coach.plan.step4.detail", bundle: bundle),
                  color: CoachTokens.purple, highlight: true),
        ]
    }

    private struct Step {
        let minutesBefore: Double   // minutes before the target hour
        let label: String
        let detail: String
        let color: Color
        let highlight: Bool
    }

    // MARK: Helpers

    private func initializeTargetHour() {
        if let p = adapter.proposal {
            targetHour = (p.dialStart + p.dialEnd) / 2
        }
    }

    private func formatTarget(_ h: Double) -> String {
        var hours = h
        while hours < 0 { hours += 24 }
        while hours >= 24 { hours -= 24 }
        let hh = Int(hours)
        let mm = Int((hours - Double(hh)) * 60)
        return String(format: "%02d:%02d", hh, mm)
    }

    private func countdownLabel(to hour: Double) -> String {
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowHours = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        var diff = hour - nowHours
        if diff < 0 { diff += 24 }
        let h = Int(diff)
        let m = Int((diff - Double(h)) * 60)
        return String(format: String(localized: "coach.plan.countdown", bundle: bundle), h, m)
    }

    private func reminderErrorMessage(_ error: ReminderError) -> String {
        switch error {
        case .denied:      return String(localized: "coach.plan.reminder.denied", bundle: bundle)
        case .failed:      return String(localized: "coach.plan.reminder.failed", bundle: bundle)
        case .unsupported: return String(localized: "coach.plan.reminder.unsupported", bundle: bundle)
        }
    }

    // MARK: Reminder scheduling

    private func toggleReminder() {
        if reminderScheduled {
            cancelReminder()
        } else {
            scheduleReminder()
        }
    }

    private func scheduleReminder() {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                guard granted else {
                    reminderError = .denied
                    return
                }
                scheduleAfterAuthorized(center: center)
            }
        }
        #else
        reminderError = .unsupported
        #endif
    }

    #if canImport(UserNotifications)
    @MainActor
    private func scheduleAfterAuthorized(center: UNUserNotificationCenter) {
        let hours = Int(targetHour)
        let minutes = Int((targetHour - Double(hours)) * 60)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "coach.plan.reminder.title", bundle: bundle)
        content.body = String(format: String(localized: "coach.plan.reminder.body", bundle: bundle),
                              formatTarget(targetHour))
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hours
        dateComponents.minute = minutes
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.reminderIdentifier,
                                            content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
        center.add(request) { error in
            Task { @MainActor in
                if error == nil {
                    reminderScheduled = true
                    reminderError = nil
                    #if canImport(UIKit) && !os(watchOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                } else {
                    reminderError = .failed
                }
            }
        }
    }

    private func cancelReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
        reminderScheduled = false
        reminderError = nil
    }
    #else
    private func cancelReminder() {
        reminderScheduled = false
    }
    #endif

    private static let reminderIdentifier = "spiral.coach.plan.bedtimeReminder"
}
