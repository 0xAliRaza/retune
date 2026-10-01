import LumenCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            PlaybackSettings().tabItem { Label("Playback", systemImage: "play.rectangle") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 520)
    }
}

private struct PlaybackSettings: View {
    @AppStorage(PlayerPreferences.liveFormatKey) private var liveFormat = PlayerPreferences.LiveFormat.automatic
    @AppStorage(PlayerPreferences.autoplayKey) private var autoplay = true

    var body: some View {
        Form {
            Picker("Live stream format", selection: $liveFormat) {
                ForEach(PlayerPreferences.LiveFormat.allCases) { Text($0.title).tag($0) }
            }
            Text("Try HLS if a channel keeps freezing; MPEG-TS starts faster.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Play next episode automatically", isOn: $autoplay)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 220)
    }
}

private struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false
    @State private var clearedArtwork = false

    var body: some View {
        Form {
            Section("Parental PIN") {
                if model.hasPIN {
                    HStack {
                        Label("PIN is set", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Change…") { model.changePIN() }
                        Button("Remove…") { model.removePIN() }
                    }
                } else {
                    HStack {
                        Text("Lock categories by right-clicking them in the category list.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Set PIN…") { model.createPINFromSettings() }
                    }
                }
            }

            Section("Hidden categories") {
                let hidden = LibrarySection.allCases.flatMap { section in
                    model.hiddenCategories(for: section).map { HiddenCategory(section: section, category: $0) }
                }
                if hidden.isEmpty {
                    Text("Right-click a category and choose Hide to tidy up the list.").foregroundStyle(.secondary)
                } else {
                    ForEach(hidden) { row in
                        let section = row.section, category = row.category
                        HStack {
                            Image(systemName: section.symbol).foregroundStyle(.secondary).frame(width: 18)
                            Text(category.name.trimmingCharacters(in: .whitespaces))
                            Spacer()
                            Button("Show") { model.unhide(category.id, in: section) }
                        }
                    }
                }
            }

            Section("History") {
                HStack {
                    Text("Continue Watching and Recently Watched for this playlist")
                    Spacer()
                    Button("Clear…", role: .destructive) { confirmClear = true }
                }
                HStack {
                    Text("Cached posters and logos")
                    Spacer()
                    Button(clearedArtwork ? "Cleared" : "Clear") {
                        Task { await ImagePipeline.shared.clear(); clearedArtwork = true }
                    }
                    .disabled(clearedArtwork)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 420)
        .confirmationDialog("Clear watch history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) {
                model.clearContinueWatching()
                model.clearRecentChannels()
            }
        } message: {
            Text("Favorites and watched marks are kept.")
        }
        .sheet(item: Binding(get: { model.pinRequest.flatMap { $0.fromSettings ? $0 : nil } },
                             set: { model.pinRequest = $0 })) { PINSheet(request: $0) }
    }
}

/// Live, VOD and series category ids overlap, so a hidden row's identity includes its section.
private struct HiddenCategory: Identifiable {
    let section: LibrarySection
    let category: MediaCategory

    var id: String { "\(section.rawValue)/\(category.id)" }
}
