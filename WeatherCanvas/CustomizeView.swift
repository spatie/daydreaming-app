import SwiftUI

struct CustomizeView: View {
    var width: CGFloat = 500
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var style: WallpaperStyle = .natural

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Your Wallpaper") {
                    Picker("Style", selection: $style) {
                        ForEach(WallpaperStyle.allCases) { Text($0.title).tag($0) }
                    }
                }
                LabeledContent("Weather", value: "Local weather")
                    .help("Uses your approximate location to fetch the local forecast from MET Norway.")
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
                    .help("Saves your style and makes a preview. New images use OpenAI credit.")
            }
            .padding(20)
        }
        .frame(width: width)
        .frame(minHeight: 260, idealHeight: 300, maxHeight: 340)
        .onAppear {
            style = model.settings.style
        }
    }

    private func save() {
        var settings = model.settings
        settings.style = style
        settings.weatherChoice = .automatic
        model.settings = settings
        dismiss()
        model.schedulePreviewGeneration(hour: model.selectedPreviewHour ?? Calendar.current.component(.hour, from: .now))
    }
}
