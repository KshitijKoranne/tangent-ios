import SwiftUI

@main
struct TangentApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup { RootView().environment(store) }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var phase

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.tab) {
            Tab("Wander", systemImage: "arrow.triangle.branch", value: 0) {
                TrailStack(rootName: "today's sentence") { TodayView() }
            }
            Tab("Book", systemImage: "book.closed", value: 1) {
                TrailStack(rootName: "your book") { BookView() }
            }
            Tab("Board", systemImage: "trophy", value: 2) {
                NavigationStack { BoardView() }
            }
        }
        .modifier(Themed())
        .accessibilityHidden(!store.onboarded)
        .overlay {
            if !store.onboarded {
                OnboardingView().modifier(Themed()).dynamicTypeSize(...DynamicTypeSize.accessibility3).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: store.onboarded)
        .overlay(alignment: .top) { if store.sheet == nil { ToastView().modifier(Themed()) } }
        .sheet(item: $store.sheet) { s in
            Group {
                switch s {
                case .ink: InkSheet()
                case .themes: ThemesSheet()
                case .pro: ProSheet()
                }
            }
            .overlay(alignment: .top) { ToastView() } // above the sheet, where the user is looking
            .modifier(Themed())
        }
        .sensoryFeedback(trigger: store.hapticTick) { _, _ in store.haptic }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .onChange(of: GameCenter.shared.state) { _, s in if s == .ready { GameCenter.shared.submit(store.book.count) } }
        .onChange(of: phase) { _, p in if p == .background { GameCenter.shared.submit(store.book.count) } } // one upload per session, not per word
        .task { if store.joined { GameCenter.shared.start() } } // the sign-in prompt only follows a yes to "Join the Board"
    }
}

/// Applies the chosen theme: palette, tint and colour scheme.
struct Themed: ViewModifier {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let s = store.shownSkin, p = Palette.of(s, s.scheme ?? scheme)
        content
            .environment(\.pal, p)
            .tint(p.ink)
            .preferredColorScheme(s.scheme)
            .animation(.easeInOut(duration: 0.35), value: s)
    }
}

struct ToastView: View {
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        ZStack {
            if let t = store.toast {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2.5).fill(Palette.solid[t.tier]).frame(width: 9, height: 9)
                    Text(t.text).sans(14, .subheadline, weight: .medium).foregroundStyle(pal.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18).padding(.vertical, 13)
                .frame(maxWidth: 420, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .padding(.horizontal, 12)
                .onTapGesture { store.toast = nil }
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(t.id)
                .task(id: t.id) {
                    try? await Task.sleep(for: .seconds(t.seconds))
                    if store.toast == t { store.toast = nil }
                }
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(still ? .easeOut(duration: 0.2) : Motion.land, value: store.toast)
        .onChange(of: store.toast) { _, t in
            if let t { AccessibilityNotification.Announcement(t.text).post() }
        }
    }
}
