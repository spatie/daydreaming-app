import AppKit
import SwiftUI

@main
struct DaydreamingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 920, height: 610)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }

        MenuBarExtra("Daydreaming", systemImage: "cloud.sun", isInserted: Binding(
            get: { model.showMenuBar },
            set: { if model.showMenuBar != $0 { model.showMenuBar = $0 } }
        )) {
            MenuBarContent()
                .environmentObject(model)
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows,
           let window = sender.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.isGenerating {
            Label(model.status, systemImage: "sparkles")
        } else {
            Text(model.status)
        }
        Text(model.detail)
            .font(.caption)

        Divider()

        Button("Open Daydreaming") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Generate now", systemImage: "sparkles") {
            model.generateNow()
        }
        .disabled(model.isGenerating)

        Button(model.settings.automaticUpdates ? "Pause automatic updates" : "Start automatic updates") {
            model.settings.automaticUpdates ? model.stopAutomatic() : model.startAutomatic()
        }

        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit Daydreaming") {
            NSApp.terminate(nil)
        }
    }
}
