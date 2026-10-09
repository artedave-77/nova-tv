import SwiftUI
import AVKit

struct Channel: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}

@MainActor
final class PlaylistStore: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var error: String?
    @Published var loading = false

    func load(_ input: String) async {
        guard let url = URL(string: input), url.scheme == "https" else {
            error = "Inserisci un URL HTTPS valido."
            return
        }
        loading = true
        defer { loading = false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  data.count < 5_000_000,
                  let text = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            var parsed: [Channel] = []
            var pendingName: String?
            for raw in text.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("#EXTINF:") {
                    pendingName = line.components(separatedBy: ",").dropFirst().joined(separator: ",")
                } else if !line.isEmpty && !line.hasPrefix("#") {
                    if let stream = URL(string: line),
                       stream.scheme == "https" || stream.scheme == "http" {
                        let name = pendingName.flatMap { $0.isEmpty ? nil : $0 } ?? "Canale"
                        parsed.append(Channel(name: name, url: stream))
                    }
                    pendingName = nil
                }
            }
            channels = parsed
            error = parsed.isEmpty ? "Nessun canale valido nella playlist." : nil
        } catch {
            self.error = "Impossibile caricare la playlist: \(error.localizedDescription)"
        }
    }
}

struct ContentView: View {
    @StateObject private var store = PlaylistStore()
    @State private var playlistURL = ""
    @State private var search = ""
    @State private var selected: Channel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("URL playlist M3U (HTTPS)", text: $playlistURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                Button("Importa playlist") {
                    Task { await store.load(playlistURL) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.loading)
                if store.loading { ProgressView() }
                if let error = store.error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
                List(filtered) { channel in
                    Button(channel.name) { selected = channel }
                }
                .searchable(text: $search, prompt: "Cerca un canale")
            }
            .padding(.horizontal)
            .navigationTitle("NOVA TV")
            .sheet(item: $selected) { channel in
                NavigationStack {
                    VideoScreen(url: channel.url)
                        .navigationTitle(channel.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Chiudi") { selected = nil }
                            }
                        }
                }
            }
        }
    }

    private var filtered: [Channel] {
        search.isEmpty ? store.channels : store.channels.filter {
            $0.name.localizedCaseInsensitiveContains(search)
        }
    }
}

struct VideoScreen: View {
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.play()
            }
            .onDisappear { player.pause() }
    }
}
