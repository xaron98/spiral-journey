import SwiftUI
import SpiralKit

struct ContextSettingsView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(\.languageBundle) private var bundle

    @State private var showContextBlockEditor = false
    @State private var editingBlock: ContextBlock? = nil
    @State private var isImportingCalendar = false

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 16) {
                // Master toggle
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "settings.context.enable", bundle: bundle))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.text)
                            Text(String(localized: "settings.context.enable.desc", bundle: bundle))
                                .font(.caption)
                                .foregroundStyle(SpiralColors.muted)
                        }
                        Spacer()
                        Toggle("", isOn: $store.contextBlocksEnabled)
                            .labelsHidden()
                            .accessibilityLabel(String(localized: "accessibility.toggle.context", defaultValue: "Daily context"))
                            .toggleStyle(SwitchToggleStyle(tint: SpiralColors.contextPrimary))
                    }
                    .padding(16)
                }
                .liquidGlass(cornerRadius: 16)

                if store.contextBlocksEnabled {
                    // Blocks list
                    if !store.contextBlocks.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(store.contextBlocks) { block in
                                HStack(spacing: 10) {
                                    Image(systemName: block.type.sfSymbol)
                                        .font(.footnote)
                                        .foregroundStyle(SpiralColors.contextPrimary.opacity(block.isEnabled ? 1 : 0.4))
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(block.label)
                                            .font(.subheadline.weight(.medium).monospaced())
                                            .foregroundStyle(block.isEnabled ? SpiralColors.text : SpiralColors.muted)
                                        HStack(spacing: 4) {
                                            Text(block.timeRangeString)
                                            if let days = block.activeDaysShort {
                                                Text("·"); Text(days)
                                            }
                                        }
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(SpiralColors.muted)
                                    }

                                    Spacer()

                                    Button {
                                        var updated = block; updated.isEnabled.toggle()
                                        store.updateContextBlock(updated)
                                    } label: {
                                        Image(systemName: block.isEnabled ? "eye.fill" : "eye.slash")
                                            .font(.caption)
                                            .foregroundStyle(block.isEnabled ? SpiralColors.contextPrimary : SpiralColors.muted)
                                    }
                                    .buttonStyle(.plain)

                                    Button { editingBlock = block } label: {
                                        Image(systemName: "pencil").font(.caption).foregroundStyle(SpiralColors.accent)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        store.removeContextBlock(id: block.id)
                                    } label: {
                                        Image(systemName: "trash").font(.caption).foregroundStyle(SpiralColors.poor)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)

                                if block.id != store.contextBlocks.last?.id {
                                    Divider().background(SpiralColors.border.opacity(0.5)).padding(.horizontal, 16)
                                }
                            }
                        }
                        .liquidGlass(cornerRadius: 16)
                    }

                    // Add block + buffer + calendar
                    VStack(spacing: 0) {
                        Button {
                            editingBlock = nil
                            showContextBlockEditor = true
                        } label: {
                            HStack {
                                Label(String(localized: "settings.context.addBlock", bundle: bundle), systemImage: "plus.circle")
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.contextPrimary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Buffer slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(localized: "settings.context.buffer", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                Text(String(format: "%.0f min", store.contextBufferMinutes))
                                    .font(.subheadline.weight(.semibold).monospaced())
                                    .foregroundStyle(SpiralColors.contextPrimary)
                            }
                            Slider(value: $store.contextBufferMinutes, in: 15...120, step: 15)
                                .tint(SpiralColors.contextPrimary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Calendar import
                        if calendarManager.isAuthorized {
                            Button {
                                isImportingCalendar = true
                                let newBlocks = calendarManager.importBlocks(existingBlocks: store.contextBlocks)
                                for block in newBlocks { store.addContextBlock(block) }
                                isImportingCalendar = false
                            } label: {
                                HStack {
                                    if isImportingCalendar { ProgressView().scaleEffect(0.7) }
                                    Label(String(localized: "settings.context.importCalendar", bundle: bundle), systemImage: "calendar.badge.plus")
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(SpiralColors.contextPrimary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isImportingCalendar)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        } else {
                            Button {
                                Task { await calendarManager.requestAuthorization() }
                            } label: {
                                HStack {
                                    Label(String(localized: "settings.context.connectCalendar", bundle: bundle), systemImage: "calendar")
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(SpiralColors.muted)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        }

                        if let err = calendarManager.errorMessage {
                            Text(err).font(.caption2).foregroundStyle(SpiralColors.poor)
                                .padding(.horizontal, 16).padding(.bottom, 8)
                        }
                    }
                    .liquidGlass(cornerRadius: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "settings.context.title", bundle: bundle))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showContextBlockEditor) {
            ContextBlockEditorView { block in store.addContextBlock(block) }
        }
        .sheet(item: $editingBlock) { block in
            ContextBlockEditorView(existing: block) { updated in store.updateContextBlock(updated) }
        }
    }
}
