import SwiftUI

struct CustomizeView: View {
    var width: CGFloat = 500
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var style: WallpaperStyle = .natural
    @State private var weather: WeatherChoice = .automatic

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Your Wallpaper") {
                    Picker("Style", selection: $style) {
                        ForEach(WallpaperStyle.allCases) { Text($0.title).tag($0) }
                    }

                }
                Section("Time and Weather") {
                    Picker("Weather", selection: $weather) {
                        ForEach(WeatherChoice.allCases) { choice in
                            Label(choice == .automatic ? "Local Weather" : choice.title, systemImage: choice.symbol).tag(choice)
                        }
                    }
                    if weather == .automatic {
                        Text("Uses your approximate location.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            Text("Links and files in your instructions are read before each new wallpaper and their text is sent to OpenAI.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .help("Saves your changes and creates a draft using OpenAI credit.")
            }
            .padding(20)
        }
        .frame(width: width)
        .frame(minHeight: 340, idealHeight: 390, maxHeight: 400)
        .onAppear {
            style = model.settings.style
            weather = model.settings.weatherChoice
        }
    }

    private func save() {
        var settings = model.settings
        settings.style = style
        settings.weatherChoice = weather
        model.settings = settings
        dismiss()
        model.schedulePreviewGeneration(hour: model.selectedPreviewHour ?? Calendar.current.component(.hour, from: .now))
    }
}
