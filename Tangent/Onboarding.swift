import SwiftUI

/// First run, one screen. The sentence is live: tap a word and its page grows under it, tap a word on that page and it grows again.
/// A line follows the path and leaves the screen at a tangent. Nothing is saved; the real book, ink and Board stay untouched.
/// The Board sign-in is asked later, from the Board tab, at the moment it is useful.
struct OnboardingView: View {
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var practice = Store.blank()   // throwaway book: tapped words light up here, nothing is saved
    @State private var trail: [String] = []
    @State private var drops = 10                 // demo ink only; the real ink is untouched

    var body: some View {
        ZStack {
            PaperBackground().contentShape(.rect)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Start anywhere.\nWander everywhere.").serif(22, .title3, weight: .medium).foregroundStyle(pal.ink2)
                        Prose(text: "The lighthouse keeper counted every wave.", size: 34, style: .largeTitle, lineHeight: 1.34, id: "ob")
                            .foregroundStyle(pal.ink).padding(.top, 22)
                        if trail.isEmpty {
                            Text("Tap an underlined word.").sans(15, .subheadline).foregroundStyle(pal.ink2).padding(.top, 22)
                        }
                        ForEach(Array(trail.enumerated()), id: \.offset) { i, w in
                            Stop(word: w, i: i, last: i == trail.count - 1).padding(.top, i == 0 ? 18 : 0)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: trail.count) { withAnimation(Motion.soft) { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { footer }
        .environment(practice)
        .environment(\.openWord) { w, _ in hop(w) }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: trail.count)
        .accessibilityAddTraits(.isModal)
        #if DEBUG
        .task { // -obhop lantern,light: walk a trail for checking in the Simulator
            for w in (UserDefaults.standard.string(forKey: "obhop") ?? "").split(separator: ",") { try? await Task.sleep(for: .seconds(0.9)); hop(String(w)) }
        }
        #endif
    }

    private var header: some View {
        HStack {
            if trail.count < 2 {
                Button { finish() } label: { Text("Skip").frame(minWidth: 44, minHeight: 44, alignment: .leading).contentShape(.rect) }
                    .sans(15, .subheadline).foregroundStyle(pal.ink3)
            }
            Spacer()
            HStack(spacing: 5) {
                InkDrop(fill: Double(drops) / 10)
                Text("\(drops)").monospacedDigit().contentTransition(.numericText(value: Double(drops)))
            }
            .sans(15, .subheadline, weight: .medium).foregroundStyle(pal.ink)
            .accessibilityElement(children: .ignore).accessibilityLabel("Ink: \(drops) of 10 drops")
        }
        .frame(height: 44).padding(.horizontal, 24).padding(.vertical, 8)
        .background(pal.bg.ignoresSafeArea(edges: .top)) // words scroll under it, not through it
    }

    @ViewBuilder private var footer: some View {
        if trail.count >= 2 {
            Button(action: finish) {
                Text("Start wandering").sans(17, weight: .semibold).foregroundStyle(pal.bg)
                    .frame(maxWidth: .infinity).frame(height: 54).background(pal.ink, in: .capsule)
            }
            .buttonStyle(.plain).padding(.horizontal, 24).padding(.vertical, 8)
            .background(pal.bg.ignoresSafeArea(edges: .bottom))
            .transition(.opacity.combined(with: .offset(y: 12)))
        }
    }

    private func finish() {
        withAnimation(Motion.soft) { store.onboarded = true }
        store.save()
    }

    private func hop(_ w: String) {
        if trail.last == w { return }
        withAnimation(still ? nil : Motion.land) {
            if practice.book[w] == nil { drops = max(0, drops - 1) }
            practice.book[w] = Found(day: Store.today, tier: Lexicon.shared.tier[w] ?? 0)
            trail.append(w)
        }
        AccessibilityNotification.Announcement("\(w), \(Lexicon.tierNames[Lexicon.shared.tier[w] ?? 0])").post()
    }
}

/// One stop on the path: the word on its highlighter, its first meaning with tappable words, and the line that got here.
private struct Stop: View {
    let word: String, i: Int, last: Bool
    @Environment(\.pal) private var pal
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var swipe: CGFloat = 0
    @State private var draw: CGFloat = 0

    private func x(_ n: Int) -> CGFloat { 6 + CGFloat(min(max(n, 0), 3)) * 16 }

    var body: some View {
        let lex = Lexicon.shared, tier = lex.tier[word] ?? 0, sense = lex.senses(word).first
        VStack(alignment: .leading, spacing: 8) {
            Text(word).serif(34, .largeTitle, weight: .medium, italic: true)
                .lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(pal.ink).band(pal.hl[tier], swipe)
            if let sense { Prose(text: sense.def, size: 17, lead: sense.pos, id: "ob\(i)").foregroundStyle(pal.ink2) }
        }
        .padding(.leading, x(i) + 9).padding(.bottom, last ? 96 : 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            Segment(from: i == 0 ? x(0) : x(i - 1), to: x(i), mid: 24, tail: last ? 70 : 0).trim(from: 0, to: draw)
                .stroke(pal.ink, style: .init(lineWidth: 1.6, lineCap: .round))
        }
        .overlay(alignment: .bottomLeading) {
            if last { Exit(from: x(i)).trim(from: 0, to: draw).stroke(pal.ink, style: .init(lineWidth: 1.6, lineCap: .round)).frame(height: 70) }
        }
        .onAppear {
            withAnimation(still ? nil : Motion.swipe) { draw = 1 }
            withAnimation(still ? nil : Motion.swipe.delay(0.2)) { swipe = 1 }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The line from the previous word, curving into this one and running down to the next.
private struct Segment: Shape {
    let from: CGFloat, to: CGFloat, mid: CGFloat, tail: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: from, y: 0))
        p.addCurve(to: CGPoint(x: to, y: mid), control1: CGPoint(x: from, y: mid * 0.75), control2: CGPoint(x: to, y: mid * 0.25))
        p.addLine(to: CGPoint(x: to, y: r.maxY - tail)); return p
    }
}

/// The last stretch: the line leaves the screen on the right. The tangent.
private struct Exit: Shape {
    let from: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: from, y: 0))
        p.addCurve(to: CGPoint(x: r.maxX + 24, y: r.maxY * 0.55), control1: CGPoint(x: from, y: r.maxY * 0.7), control2: CGPoint(x: r.maxX * 0.4, y: r.maxY * 0.8))
        return p
    }
}
