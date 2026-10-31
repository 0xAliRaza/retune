import SwiftUI

/// Single source of truth for the keyboard shortcut cheat sheet (⌘/ or ? in the player).
enum ShortcutCatalog {
    struct Item: Identifiable {
        var id: String { action }
        let keys: [String]
        let action: String
    }

    static let player: [Item] = [
        Item(keys: ["Space"], action: "Play / pause"),
        Item(keys: ["←", "→"], action: "Back / forward 10 seconds"),
        Item(keys: ["⇧←", "⇧→"], action: "Back / forward 60 seconds"),
        Item(keys: ["↑", "↓"], action: "Previous / next channel, movie or episode"),
        Item(keys: ["Page Up", "Page Down"], action: "Previous / next (same as ↑ ↓)"),
        Item(keys: ["⌫"], action: "Last watched channel"),
        Item(keys: ["L"], action: "Channel / up-next list"),
        Item(keys: ["N", "⇧N"], action: "Next / previous (same as ↓ ↑)"),
        Item(keys: ["[", "]"], action: "Slower / faster"),
        Item(keys: ["\\"], action: "Normal speed"),
        Item(keys: ["−", "="], action: "Volume down / up"),
        Item(keys: ["M"], action: "Mute"),
        Item(keys: ["C"], action: "Subtitles on / off"),
        Item(keys: ["F"], action: "Full screen (or double-click)"),
        Item(keys: ["I"], action: "Stats"),
        Item(keys: ["S"], action: "Screenshot to Desktop"),
        Item(keys: ["?"], action: "Show shortcuts"),
        Item(keys: ["Esc"], action: "Close panel · back to browsing"),
    ]

    static let app: [Item] = [
        Item(keys: ["⌘1", "⌘2", "⌘3"], action: "Live TV / Movies / Series"),
        Item(keys: ["⌃⌘1", "⌃⌘2", "⌃⌘3"], action: "Grid / List / Compact layout"),
        Item(keys: ["⇥", "⇧⇥"], action: "Next / previous column (sidebar · categories · content)"),
        Item(keys: ["→", "Return"], action: "Into the next column · open / play in content"),
        Item(keys: ["←", "Esc"], action: "Back to the previous column · Esc leaves a detail page"),
        Item(keys: ["↑", "↓"], action: "Move within a column · ↑ at the top reaches filter / search"),
        Item(keys: ["⌘["], action: "Back"),
        Item(keys: ["⌘F"], action: "Search"),
        Item(keys: ["⌘R"], action: "Refresh playlist"),
        Item(keys: ["⇧⌘N"], action: "Add playlist"),
        Item(keys: ["⌘L"], action: "Lock categories again"),
        Item(keys: ["⌘,"], action: "Settings"),
        Item(keys: ["⌃⌘F"], action: "Full screen"),
        Item(keys: ["⌘/"], action: "Show shortcuts"),
    ]
}

struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Keyboard Shortcuts").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .top, spacing: 36) {
                section("Player", ShortcutCatalog.player)
                section("App", ShortcutCatalog.app)
            }
        }
        .padding(26)
        .frame(width: 860)
    }

    private func section(_ title: String, _ items: [ShortcutCatalog.Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                ForEach(items) { item in
                    GridRow {
                        HStack(spacing: 4) { ForEach(item.keys, id: \.self, content: KeyCap.init) }
                            .gridColumnAlignment(.trailing)
                        Text(item.action).font(.callout)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KeyCap: View {
    let label: String

    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .frame(minWidth: 26)
            .background(.quaternary, in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.tertiary, lineWidth: 0.5))
    }
}
