import SwiftUI
import GameKit

/// Game Center: sign-in comes from the Apple ID, so Tangent has no accounts of its own.
@Observable final class GameCenter {
    static let shared = GameCenter()
    static let board = "tangent.words" // must match the leaderboard ID in App Store Connect

    enum State { case idle, signedOut, failed, ready }
    struct Row: Identifiable { let id: String; let rank: Int; let name: String; let score: Int; let isMe: Bool; let player: GKPlayer? }

    var state = State.idle
    var rows: [Row] = []
    var me: Row?

    func start() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoBoard") { demo(); return }
        #endif
        GKLocalPlayer.local.authenticateHandler = { vc, error in
            if let vc { Self.present(vc); return }
            if GKLocalPlayer.local.isAuthenticated {
                self.state = .ready
                Task { await self.load() }
            } else {
                let code = (error as? GKError)?.code
                self.state = error == nil || code == .notAuthenticated || code == .cancelled ? .signedOut : .failed
            }
        }
    }

    func submit(_ n: Int) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        Task {
            try? await GKLeaderboard.submitScore(n, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Self.board])
            await load()
        }
    }

    func load() async {
        do {
            guard let lb = try await GKLeaderboard.loadLeaderboards(IDs: [Self.board]).first else { state = .failed; return }
            let (local, entries, _) = try await lb.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 50))
            let myID = GKLocalPlayer.local.gamePlayerID
            func row(_ e: GKLeaderboard.Entry) -> Row {
                Row(id: e.player.gamePlayerID, rank: e.rank, name: e.player.displayName, score: e.score, isMe: e.player.gamePlayerID == myID, player: e.player)
            }
            rows = entries.map(row)
            me = local.map(row)
            state = .ready
        } catch { state = .failed }
    }

    private static func present(_ vc: UIViewController) {
        var top = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        while let p = top?.presentedViewController { top = p }
        top?.present(vc, animated: true)
    }

    #if DEBUG
    private func demo() {
        let names = ["Meera", "Arjun", "Tara", "Noor", "Kabir", "Isha", "Rohan", "Anaya", "Vikram", "Zoya", "Dev", "Leela"]
        rows = names.enumerated().map { i, n in Row(id: n, rank: i + 1, name: n, score: 1480 - i * i * 9 - i * 37, isMe: i == 6, player: nil) }
        me = rows[6]; state = .ready
    }
    #endif
}

struct BoardView: View {
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal
    private var gc: GameCenter { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Board · Most words found").label().foregroundStyle(pal.ink3)
                switch gc.state {
                case .idle where store.joined:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                case .idle, .signedOut, .failed:
                    offline.padding(.top, 20)
                case .ready:
                    if let me = gc.me { you(me).padding(.top, 20) }
                    LazyVStack(spacing: 0) {
                        ForEach(gc.rows) { r in
                            BoardRow(r: r)
                                .overlay(alignment: .top) { if r.rank > 1 { Rectangle().fill(pal.rule).frame(height: 1) } }
                        }
                    }
                    .padding(.top, 18)
                }
                Text("Ranked by the number of different words each person has found. Every word counts once.")
                    .sans(13, .footnote).foregroundStyle(pal.ink3)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 32)
        }
        .background(PaperBackground())
        .navigationTitle("Board")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Wordmark() }.sharedBackgroundVisibility(.hidden) }
        .refreshable { if gc.state == .ready { await gc.load() } }
    }

    private func you(_ r: GameCenter.Row) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your place").label(10).foregroundStyle(pal.ink3)
                Text("No. \(r.rank)").serif(40, .largeTitle, weight: .medium, italic: true).foregroundStyle(pal.ink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("Words").label(10).foregroundStyle(pal.ink3)
                Text(r.score, format: .number).serif(40, .largeTitle, weight: .medium).monospacedDigit().foregroundStyle(pal.ink)
            }
        }
        .padding(20)
        .background(pal.surface, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    private var offline: some View {
        let failed = gc.state == .failed
        return VStack(alignment: .leading, spacing: 0) {
            Text(store.book.count, format: .number).serif(96, .largeTitle, weight: .medium).monospacedDigit().foregroundStyle(pal.ink)
                .minimumScaleFactor(0.5).lineLimit(1).padding(.top, 14)
            Text(failed ? "words in your book. Game Center is out of reach for now. Your count reaches the Board when it is back."
                        : "words in your book. See where they rank against players everywhere.")
                .sans(17, .body).foregroundStyle(pal.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            Button(failed || gc.state == .signedOut ? "Try again" : "Join the Board") { store.joined = true; store.save(); gc.start() }
                .buttonStyle(.plain)
                .sans(16, .callout, weight: .semibold).foregroundStyle(pal.bg)
                .padding(.horizontal, 24).frame(height: 50).background(pal.ink, in: .capsule)
                .padding(.top, 28)
            Text(gc.state == .signedOut // they said yes but no sign-in appeared; the system stops asking after a refusal
                 ? "No sign-in prompt? Sign in to Game Center in Settings, then try again."
                 : "Signs in with Game Center. Everything else works without it.")
                .sans(13, .footnote).foregroundStyle(pal.ink3).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
        }
    }
}

private struct BoardRow: View {
    let r: GameCenter.Row
    @Environment(\.pal) private var pal
    @State private var photo: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Text("\(r.rank)").font(.system(.subheadline, design: .monospaced, weight: .medium)).monospacedDigit()
                .foregroundStyle(r.rank <= 3 ? pal.ink : pal.ink3)
                .frame(width: 26, alignment: .trailing)
            Group {
                if let photo { Image(uiImage: photo).resizable().scaledToFill() }
                else { Text(String(r.name.prefix(1))).serif(17, .headline, weight: .medium, italic: true).foregroundStyle(pal.ink2) }
            }
            .frame(width: 38, height: 38)
            .background(pal.surface)
            .clipShape(.circle)
            Text(r.isMe ? "\(r.name) (you)" : r.name).sans(16, weight: r.isMe ? .semibold : .regular).foregroundStyle(pal.ink).lineLimit(1)
            Spacer(minLength: 8)
            Text(r.score, format: .number).serif(22, .title3, weight: .medium).monospacedDigit().foregroundStyle(pal.ink)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, r.isMe ? 12 : 0)
        .background(r.isMe ? pal.hl[0].opacity(0.45) : .clear, in: .rect(cornerRadius: 14))
        .padding(.horizontal, r.isMe ? -12 : 0)
        .task { if let p = r.player { photo = try? await p.loadPhoto(for: .small) } }
        .accessibilityElement(children: .combine)
    }
}
