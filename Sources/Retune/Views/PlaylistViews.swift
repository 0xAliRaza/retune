import RetuneCore
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("Welcome to Retune").font(.largeTitle.weight(.bold))
            Text("Add your IPTV subscription to start watching live TV, movies and series.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { model.isAddingPlaylist = true } label: {
                Label("Add Playlist", systemImage: "plus").padding(.horizontal, 12).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            HStack(spacing: 28) {
                hint("server.rack", "Xtream Codes", "Server, username & password")
                hint("link", "M3U URL", "A playlist link from your provider")
                hint("doc", "M3U File", "A .m3u file on your Mac")
            }
            .padding(.top, 10)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hint(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 170)
    }
}

struct PlaylistEditor: View {
    enum Kind: String, CaseIterable, Identifiable {
        case xtream = "Xtream Codes", m3uURL = "M3U URL", m3uFile = "M3U File"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: Playlist?

    @State private var kind: Kind = .xtream
    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var m3uURL = ""
    @State private var fileURL: URL?
    @State private var isImportingFile = false
    @State private var isVerifying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(existing == nil ? "Add Playlist" : "Edit Playlist").font(.title2.weight(.semibold))
                Text("Your details are stored on this Mac only. Nothing is sent anywhere except your provider.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 24)

            Form {
                if existing == nil {
                    Picker("Type", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                }
                TextField("Name", text: $name, prompt: Text("e.g. My IPTV"))
                switch kind {
                case .xtream:
                    TextField("Server URL", text: $server, prompt: Text("http://example.com:8080"))
                        .onChange(of: server) { autofillFromPastedLink() }
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password, prompt: existing == nil ? nil : Text("Unchanged"))
                    if XtreamCredentials.usesPlainHTTP(server) { plainHTTPWarning }
                case .m3uURL:
                    TextField("Playlist URL", text: $m3uURL, prompt: Text("http://…/get.php?username=…&type=m3u_plus"))
                    if XtreamCredentials.usesPlainHTTP(m3uURL) { plainHTTPWarning }
                    if XtreamCredentials.parse(fromPlaylistURL: m3uURL) != nil {
                        Label("This is an Xtream link — switching to Xtream Codes gives you series, posters and EPG.", systemImage: "sparkles")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Use Xtream Codes Instead") { kind = .xtream; server = m3uURL }
                    }
                case .m3uFile:
                    HStack {
                        Text(fileURL?.lastPathComponent ?? "No file chosen").foregroundStyle(fileURL == nil ? .secondary : .primary)
                        Spacer()
                        Button("Choose…") { isImportingFile = true }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout).padding(.horizontal, 24)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button { Task { await save() } } label: {
                    if isVerifying { ProgressView().controlSize(.small).padding(.horizontal, 18) } else { Text(existing == nil ? "Add" : "Save") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isVerifying)
            }
            .padding(24)
        }
        .frame(width: 520)
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [UTType(filenameExtension: "m3u") ?? .plainText, UTType(filenameExtension: "m3u8") ?? .plainText, .plainText]) { result in
            if case .success(let url) = result { fileURL = url; if name.isEmpty { name = url.deletingPathExtension().lastPathComponent } }
        }
        .onAppear(perform: populate)
    }

    private var plainHTTPWarning: some View {
        Label("This address uses plain HTTP, so your login travels unencrypted. Use an https:// address if your provider offers one.",
              systemImage: "lock.open")
            .font(.callout).foregroundStyle(.secondary)
    }

    private var isValid: Bool {
        switch kind {
        case .xtream: XtreamCredentials.normalizeServer(server) != nil && !username.isEmpty && (!password.isEmpty || existing != nil)
        case .m3uURL: URL(lenient: m3uURL) != nil
        case .m3uFile: fileURL != nil
        }
    }

    private func populate() {
        guard let existing else { return }
        name = existing.name
        switch existing.source {
        case let .xtream(serverURL, user):
            kind = .xtream
            server = serverURL.absoluteString
            username = user
        case .m3u(let url):
            kind = url.isFileURL ? .m3uFile : .m3uURL
            if url.isFileURL { fileURL = url } else { m3uURL = url.absoluteString }
        }
    }

    /// Pasting a full provider link into the server field fills in every field.
    private func autofillFromPastedLink() {
        guard let credentials = XtreamCredentials.parse(fromPlaylistURL: server) else { return }
        server = credentials.server.absoluteString
        username = credentials.username
        password = credentials.password
    }

    private func save() async {
        errorMessage = nil
        let id = existing?.id ?? UUID()
        let displayName = name.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .xtream:
            guard let serverURL = XtreamCredentials.normalizeServer(server) else { errorMessage = RetuneError.invalidServer.errorDescription; return }
            let user = username.trimmingCharacters(in: .whitespaces)
            let secret = password.isEmpty ? (model.secrets.get(id.uuidString) ?? "") : password
            isVerifying = true
            defer { isVerifying = false }
            do {
                _ = try await XtreamClient(credentials: XtreamCredentials(server: serverURL, username: user, password: secret)).authenticate()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            let playlist = Playlist(id: id, name: displayName.isEmpty ? (serverURL.host() ?? "Xtream") : displayName,
                                    source: .xtream(server: serverURL, username: user), createdAt: existing?.createdAt ?? .now)
            do {
                try model.addPlaylist(playlist, password: secret)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        case .m3uURL, .m3uFile:
            guard let url = kind == .m3uFile ? fileURL : URL(lenient: m3uURL) else { return }
            let fallbackName = kind == .m3uFile ? url.deletingPathExtension().lastPathComponent : (url.host() ?? "Playlist")
            try? model.addPlaylist(Playlist(id: id, name: displayName.isEmpty ? fallbackName : displayName, source: .m3u(url),
                                            createdAt: existing?.createdAt ?? .now), password: nil)
        }
        dismiss()
    }
}
