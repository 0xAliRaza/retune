import AppKit
import SwiftUI

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Lumen", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1360, height: 860)
        .commands { LumenCommands(model: model) }

        Settings {
            SettingsView().environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        guard let model else { return }
        model.session.stop()
        model.flushLibrary()
        model.session.videoView.videoLayer.releaseRenderContext()
        model.session.engine.shutdown()
    }
}

struct LumenCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Playlist…") { model.isAddingPlaylist = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Refresh Playlist") { Task { await model.refresh() } }
                .keyboardShortcut("r")
                .disabled(model.activePlaylist == nil)
        }
        CommandGroup(after: .toolbar) {
            ForEach(Array(LayoutMode.allCases.enumerated()), id: \.element) { offset, mode in
                Toggle("as \(mode.title)", isOn: Binding(get: { model.layoutMode == mode }, set: { _ in model.layoutMode = mode }))
                    .keyboardShortcut(KeyEquivalent(Character(String(offset + 1))), modifiers: [.command, .control])
            }
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { model.isShowingShortcuts = true }
                .keyboardShortcut("/")
        }
        CommandMenu("Browse") {
            ForEach(Array(LibrarySection.allCases.enumerated()), id: \.element) { offset, section in
                Button(section.title) { model.section = section }
                    .keyboardShortcut(KeyEquivalent(Character(String(offset + 1))))
            }
            Divider()
            Button("Lock Categories Again") { model.relockAll() }
                .keyboardShortcut("l")
                .disabled(model.unlockedCategories.isEmpty)
        }
    }
}
