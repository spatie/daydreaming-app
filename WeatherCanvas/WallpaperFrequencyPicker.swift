import SwiftUI

struct WallpaperFrequencyPicker: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingCustom = false
    @State private var amount = 1
    @State private var unit = FrequencyUnit.hours

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CreationStepHeading(number: 3, title: "Wallpaper updates")
            HStack(spacing: 4) {
                Picker("Wallpaper updates", selection: Binding(get: { model.settings.interval }, set: { interval in
                    if interval == .custom { editCustom() }
                    else { model.settings.interval = interval }
                })) {
                    ForEach(UpdateInterval.allCases) { interval in
                        Text(interval == .custom && model.settings.interval == .custom
                             ? model.settings.frequencyTitle : interval.title).tag(interval)
                    }
                }
                .labelsHidden().pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                if model.settings.interval == .custom {
                    Button("Edit…", action: editCustom).buttonStyle(.borderless).font(.caption)
                }
            }
            .help(frequencyHelp)
            if model.settings.interval == .twiceDaily {
                Text("Around \(model.hourLabel(7)) and \(model.hourLabel(19))")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Morning and evening, in your local time.")
            }
            Text(model.automaticUpdateStatus)
                .font(.caption.weight(.medium)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let desktop = model.desktopPictureDescription {
                Text(desktop)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let lastUpdated = model.lastUpdated {
                Text("Applied to desktop \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("The last time Daydreaming successfully changed your desktop wallpaper. Making a preview does not change this time.")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wallpaper updates")
        .popover(isPresented: $showingCustom) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Update every").font(.headline)
                HStack {
                    TextField("Amount", value: $amount, format: .number.grouping(.never))
                        .frame(width: 60).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Update interval amount")
                    Stepper("Amount", value: $amount, in: 1...unit.maximum).labelsHidden()
                        .accessibilityLabel("Update interval amount")
                    Picker("Unit", selection: $unit) {
                        ForEach(FrequencyUnit.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }.labelsHidden().frame(width: 105)
                }
                Text("One minute to one month. Updates use \(model.imageCreditName).")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel", role: .cancel) { showingCustom = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Done") {
                        var settings = model.settings
                        settings.customMinutes = min(unit.maximum, max(1, amount)) * unit.minutes
                        settings.interval = .custom
                        model.settings = settings
                        showingCustom = false
                    }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20).frame(width: 320)
            .onChange(of: unit) { _, _ in amount = min(unit.maximum, max(1, amount)) }
        }
    }

    private func editCustom() {
        let minutes = model.settings.intervalMinutes
        unit = FrequencyUnit.allCases.reversed().first { minutes.isMultiple(of: $0.minutes) } ?? .minutes
        amount = min(unit.maximum, max(1, minutes / unit.minutes))
        showingCustom = true
    }

    private var frequencyHelp: String {
        let timing = model.settings.interval == .twiceDaily
            ? "Updates around \(model.hourLabel(7)) and \(model.hourLabel(19)), in your local time. "
            : "How often your wallpaper updates after you use this picture and idea. "
        return timing + "Frequent updates can use more \(model.imageCreditName). Your daily image limit still applies."
    }
}
