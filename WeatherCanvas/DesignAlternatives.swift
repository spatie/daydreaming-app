#if DEBUG
import AppKit
import SwiftUI

/// Isolated layout studies. They use one bundled picture and never initialize app services.
private struct DesignAlternative: View {
    enum Organizer { case photos, inspector, composer, library, conversation, filmstrip }
    let organizer: Organizer
    @State private var prompt = "Reimagine this picture at dusk with warm window lights."
    @State private var hour = 18.0

    var body: some View {
        Group {
            switch organizer {
            case .photos:
                VStack(spacing: 0) { canvas; Divider(); editor; timeline }
            case .inspector:
                HStack(spacing: 0) {
                    VStack(spacing: 0) { canvas; timeline }
                    Divider()
                    VStack(alignment: .leading, spacing: 20) {
                        editor
                        actions.padding(.horizontal, 20)
                        Spacer()
                    }.frame(width: 300)
                }
            case .composer:
                VStack(spacing: 0) { editor; Divider(); canvas; timeline }
            case .library:
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Saved Wallpapers").font(.headline)
                        Text("Today").foregroundStyle(.secondary)
                        DesignAlternativePicture().frame(height: 100)
                        Text("18:00 · Draft").font(.caption)
                        DesignAlternativePicture().frame(height: 100)
                        Text("12:00 · Full Quality").font(.caption)
                        Spacer()
                    }.padding(20).frame(width: 190)
                    Divider()
                    VStack(spacing: 0) { canvas; editor; timeline }
                }
            case .conversation:
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Spacer(); editor.frame(width: 600) }
                    canvas
                    timeline
                }.padding(20)
            case .filmstrip:
                VStack(spacing: 0) {
                    canvas
                    HStack(spacing: 14) {
                        ForEach([6, 12, 18, 23], id: \.self) { time in
                            VStack(spacing: 6) {
                                DesignAlternativePicture().frame(height: 65)
                                Text("\(time):00").font(.caption)
                            }
                        }
                    }.padding(16)
                    editor
                    timeline
                }
            }
        }
        .navigationTitle("Daydreaming")
        .toolbar {
            ToolbarItemGroup {
                Button("Saved Wallpapers", systemImage: "photo.on.rectangle") {}
                Button("Choose Picture", systemImage: "photo") {}
                Button("Crop", systemImage: "crop") {}
            }
            ToolbarSpacer(.fixed)
            ToolbarItem { Button("Customize", systemImage: "slider.horizontal.3") {} }
        }
        .frame(width: 1_000, height: 720)
    }

    private var canvas: some View {
        VStack(spacing: 12) {
            DesignAlternativePicture()
            HStack {
                Text("18:00 · Rainy").font(.callout)
                Text("Draft").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var editor: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Prompt").font(.caption).foregroundStyle(.secondary)
                TextField("Describe your wallpaper", text: $prompt, axis: .vertical)
                    .lineLimit(2...3).textFieldStyle(.roundedBorder)
                Text("Drafts use your OpenAI key as you edit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Save") {}.padding(.top, 24)
        }
        .padding(20)
    }

    private var timeline: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Slider(value: $hour, in: 0...23, step: 1) { Text("Time of Day") }
                HStack {
                    Text("0:00")
                    Spacer()
                    Button("Now") { hour = 10 }
                    Spacer()
                    Text("23:00")
                }.font(.caption).foregroundStyle(.secondary)
            }
            if organizer != .inspector { actions }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
    }

    private var actions: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button("Use as Wallpaper") {}.buttonStyle(.borderedProminent)
            Button("Make Full Quality") {}
            Text("Uses OpenAI credit").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DesignAlternativePicture: View {
    var body: some View {
        ZStack {
            Color.black
            if let url = Bundle.main.url(forResource: "YosemiteValley", withExtension: "jpg"),
               let picture = NSImage(contentsOf: url) {
                Image(nsImage: picture).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white)
            }
        }
    }
}

#Preview("Photos Desk") { DesignAlternative(organizer: .photos) }
#Preview("Quiet Inspector") { DesignAlternative(organizer: .inspector) }
#Preview("Prompt First") { DesignAlternative(organizer: .composer) }
#Preview("Library Desk") { DesignAlternative(organizer: .library) }
#Preview("Prompt Conversation") { DesignAlternative(organizer: .conversation) }
#Preview("Day Filmstrip") { DesignAlternative(organizer: .filmstrip) }
#endif
