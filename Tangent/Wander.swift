import SwiftUI
import AVFoundation

/// A navigation stack where every tapped word opens a page. The stack is the trail:
/// swipe back to retrace it, long-press Back to jump anywhere on it.
struct TrailStack<Root: View>: View {
    let rootName: String
    @ViewBuilder var root: Root
    @Environment(Store.self) private var store
    @State private var path: [Hop] = []
    @State private var nudge = 0
    @Namespace private var ns

    var body: some View {
        NavigationStack(path: $path) {
            root.navigationDestination(for: Hop.self) { hop in
                let i = path.firstIndex { $0.word == hop.word } ?? max(0, path.count - 1)
                EntryView(hop: hop, depth: i + 1, from: i > 0 ? path[i - 1].word : nil, rootName: rootName, nudge: nudge)
                    .navigationTransition(.zoom(sourceID: hop.src, in: ns))
            }
        }
        .environment(\.zoom, ns)
        .environment(\.openWord) { w, src in open(w, src) }
        #if DEBUG
        .task { // -open word -src id -openDelay s [-open2 word -src2 id]: walk a trail on launch, for checking in the Simulator
            let d = UserDefaults.standard
            guard rootName == "today's sentence", let w = d.string(forKey: "open") else { return }
            try? await Task.sleep(for: .seconds(max(0.3, d.double(forKey: "openDelay"))))
            open(w, d.string(forKey: "src") ?? "demo")
            guard let w2 = d.string(forKey: "open2") else { return }
            try? await Task.sleep(for: .seconds(1.6))
            open(w2, d.string(forKey: "src2") ?? "demo2")
        }
        #endif
    }

    private func open(_ w: String, _ src: String) {
        if path.last?.word == w { nudge += 1; store.feel(.impact(flexibility: .rigid, intensity: 0.4)); return } // already on this page
        if let i = path.firstIndex(where: { $0.word == w }) { path.removeLast(path.count - i - 1); store.feel(.selection); return } // back up the trail, no extra hop
        _ = Lexicon.shared.senses(w) // read the page before it opens
        path.append(Hop(word: w, src: src, visit: store.visit(w)))
        if path.count > store.best { store.best = path.count; store.save() }
    }
}

// MARK: - Today

struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal

    var body: some View {
        GeometryReader { g in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let date = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.init(identifier: "en_GB")))
                    ViewThatFits(in: .horizontal) { // one line, or stacked at the largest text sizes
                        HStack { Text(date).fixedSize(); Spacer(minLength: 12); Text("Today's sentence").fixedSize() }
                        VStack(alignment: .leading, spacing: 4) { Text(date); Text("Today's sentence") }
                    }
                    .label().foregroundStyle(pal.ink3)

                    Spacer(minLength: 28).frame(maxHeight: g.size.height * 0.1) // the sentence sits a little lower, like a title page
                    Prose(text: Store.sentence, size: 31, style: .title, lineHeight: 1.36, id: "today")
                        .foregroundStyle(pal.ink)

                    Spacer(minLength: 56)
                    if store.book.isEmpty { hint } else { stats }
                    Button { store.onboarded = false } label: { Text("How Tangent works").label(10).underline(color: pal.ink3.opacity(0.5)) }
                        .foregroundStyle(pal.ink3).padding(.top, 28).padding(.bottom, 4)
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
                .frame(minHeight: g.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(PaperBackground())
        .navigationTitle("Today")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Wordmark() }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) { StatusPills() }
        }
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashedRule()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "hand.tap").foregroundStyle(pal.ink3)
                Text("Pick any underlined word and see where it leads.")
                    .foregroundStyle(pal.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .sans(15, .subheadline)
        }
    }

    private var stats: some View {
        VStack(spacing: 18) {
            Rectangle().fill(pal.rule).frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                Stat(n: store.foundToday, label: "Found today")
                Stat(n: store.book.count, label: "In your book")
                Stat(n: store.best, label: "Longest trail")
            }
        }
    }
}

struct Stat: View {
    let n: Int, label: String
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(n, format: .number).serif(30, .title, weight: .medium).monospacedDigit()
                .contentTransition(.numericText(value: Double(n)))
                .foregroundStyle(pal.ink)
            Text(label).label(10).foregroundStyle(pal.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A word's page

struct EntryView: View {
    let hop: Hop, depth: Int, from: String?, rootName: String, nudge: Int
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var visit: Visit
    @State private var swipe: CGFloat
    @State private var stamped: Bool
    @State private var shown = false
    @State private var scrolled = false

    init(hop: Hop, depth: Int, from: String?, rootName: String, nudge: Int) {
        self.hop = hop; self.depth = depth; self.from = from; self.rootName = rootName; self.nudge = nudge
        _visit = State(initialValue: hop.visit)
        _swipe = State(initialValue: hop.visit == .fresh ? 0 : 1)
        _stamped = State(initialValue: hop.visit != .fresh)
    }

    var body: some View {
        let w = hop.word, lex = Lexicon.shared
        let tier = lex.tier[w] ?? 0, senses = lex.senses(w), (g1, g2) = lex.neighbours(w)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("Hop \(depth)").label()
                    Spacer(minLength: 0)
                    Text("\(g1)  ·  \(Text(w).fontWeight(.semibold).foregroundStyle(pal.ink2))  ·  \(g2)")
                        .serif(14, .footnote, italic: true).lineLimit(1)
                        .accessibilityLabel("Between \(g1) and \(g2)")
                }
                .foregroundStyle(pal.ink3)

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(w).serif(54, .largeTitle, weight: .medium, italic: true)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .foregroundStyle(pal.ink)
                        .band(pal.hl[tier], swipe)
                        .keyframeAnimator(initialValue: 1.0, trigger: nudge) { v, s in v.scaleEffect(s, anchor: .leading) } keyframes: { _ in
                            SpringKeyframe(1.06, duration: 0.12); SpringKeyframe(1, duration: 0.34, spring: .bouncy)
                        }
                        .accessibilityAddTraits(.isHeader)
                    SpeakButton(word: w)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
                    Spacer(minLength: 0)
                }
                .padding(.top, 24)

                meta(w, tier).padding(.top, 16)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(senses.enumerated()), id: \.offset) { i, s in
                        sense(s, i, w)
                            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 10)
                            .animation(still ? nil : Motion.soft.delay(0.1 + 0.05 * Double(min(i, 6))), value: shown)
                    }
                }
                .padding(.top, 14)

                footer.padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
        }
        .background(PaperBackground())
        #if DEBUG
        .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "scrolled") ? .bottom : .top)
        #endif
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 96 } action: { _, v in scrolled = v }
        .navigationTitle(w)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(w).serif(17, .headline, weight: .medium, italic: true).foregroundStyle(pal.ink)
                    .opacity(scrolled ? 1 : 0).offset(y: scrolled ? 0 : 6)
                    .animation(Motion.soft, value: scrolled)
            }
            ToolbarItem(placement: .topBarTrailing) { StatusPills() }
        }
        .onAppear(perform: enter)
    }

    private func enter() {
        guard !shown else { return }
        if still { shown = true; swipe = 1; stamped = true; return }
        shown = true
        if visit == .fresh, !stamped {
            withAnimation(Motion.swipe.delay(0.32)) { swipe = 1 }
            withAnimation(Motion.land.delay(0.72)) { stamped = true }
        }
    }

    @ViewBuilder private func meta(_ w: String, _ tier: Int) -> some View {
        HStack(spacing: 10) {
            Chip(text: Lexicon.tierNames[tier], fill: pal.hl[tier])
            switch visit {
            case .fresh:
                Text("New · +1").label(10)
                    .padding(.horizontal, 8).frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(pal.ink, lineWidth: 1))
                    .foregroundStyle(pal.ink)
                    .scaleEffect(stamped ? 1 : 1.7).rotationEffect(.degrees(stamped ? 0 : -9)).opacity(stamped ? 1 : 0)
            case .owned:
                let d = store.book[w]?.day ?? Store.today
                Text(d == Store.today ? "In your book since today" : "In your book since \(Store.date(d))")
                    .sans(13, .footnote).foregroundStyle(pal.ink3)
            case .dry:
                Chip(text: "Out of ink", fill: pal.hl[3])
                TimelineView(.periodic(from: .now, by: 10)) { ctx in
                    if store.inkNow(ctx.date) >= 1 {
                        Button("Add to book") { add(w) }.sans(13, .footnote, weight: .semibold).foregroundStyle(pal.ink)
                    } else {
                        Button { store.sheet = .ink } label: {
                            Text("Next drop in \(Store.dur(store.nextDrop(ctx.date)))").underline(color: pal.ink3.opacity(0.5))
                        }
                        .sans(13, .footnote).foregroundStyle(pal.ink3)
                    }
                }
            }
        }
    }

    private func add(_ w: String) {
        let v = store.visit(w)
        guard v == .fresh else { return }
        swipe = 0; stamped = false; visit = .fresh
        withAnimation(Motion.swipe) { swipe = 1 }
        withAnimation(Motion.land.delay(0.4)) { stamped = true }
    }

    private func sense(_ s: Sense, _ i: Int, _ w: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(i + 1)").font(.system(.caption, design: .monospaced, weight: .medium)).foregroundStyle(pal.ink3)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 12) {
                Prose(text: s.def, lead: s.pos, id: "\(w).\(i).d").foregroundStyle(pal.ink)
                if !s.ex.isEmpty {
                    Prose(text: "“\(s.ex)”", size: 17, style: .callout, italic: true, id: "\(w).\(i).e")
                        .foregroundStyle(pal.ink2)
                        .padding(.leading, 13)
                        .overlay(alignment: .leading) { Capsule().fill(pal.rule).frame(width: 2).padding(.vertical, 3) }
                }
                if !s.same.isEmpty || !s.typeOf.isEmpty || !s.types.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !s.same.isEmpty { Related(label: "Same as", words: s.same, id: "\(w).\(i).s") }
                        if !s.typeOf.isEmpty { Related(label: "A kind of", words: s.typeOf, id: "\(w).\(i).k") }
                        if !s.types.isEmpty { Related(label: "Kinds", words: Array(s.types.prefix(12)), id: "\(w).\(i).t") }
                    }
                    .foregroundStyle(pal.ink2)
                }
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(pal.rule).frame(height: 1) } }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            DashedRule()
            HStack(alignment: .firstTextBaseline) {
                Text("From").label(10)
                Button { dismiss() } label: { Text(from ?? rootName).serif(15, .subheadline, italic: true).underline(color: pal.ink3.opacity(0.5)) }
                    .foregroundStyle(pal.ink2)
                Spacer()
                Text(depth == 1 ? "1 hop" : "\(depth) hops").label(10)
            }
            .foregroundStyle(pal.ink3)
        }
    }
}

// MARK: - Small parts

struct Chip: View {
    let text: String, fill: Color
    @Environment(\.pal) private var pal
    var body: some View {
        Text(text).label(10).foregroundStyle(pal.ink)
            .padding(.horizontal, 8).frame(height: 22)
            .background(fill, in: .rect(cornerRadius: 5))
    }
}

struct DashedRule: View {
    @Environment(\.pal) private var pal
    var body: some View {
        Line().stroke(pal.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { $0.move(to: .init(x: 0, y: r.midY)); $0.addLine(to: .init(x: r.maxX, y: r.midY)) } }
    }
}

struct Wordmark: View {
    @Environment(\.pal) private var pal
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1.5) {
            Text("tangent").serif(25, .title2, weight: .medium, italic: true).foregroundStyle(pal.ink)
            Circle().fill(Color(hex: 0xFF97C6)).frame(width: 6.5, height: 6.5)
        }
        .fixedSize()
        .accessibilityLabel("Tangent")
    }
}

/// Words in the book and ink left. Top right on every Wander page.
struct StatusPills: View {
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let n = store.inkNow(ctx.date), full = Int(n)
            HStack(spacing: 0) {
                Button { store.tab = 1 } label: {
                    HStack(spacing: 7) {
                        TierDots()
                        Text(store.book.count, format: .number).monospacedDigit()
                            .contentTransition(.numericText(value: Double(store.book.count)))
                    }
                    .padding(.leading, 12).padding(.trailing, 10).frame(height: 36)
                }
                .accessibilityLabel("\(store.book.count) words in your book")
                Rectangle().fill(pal.ink3.opacity(0.3)).frame(width: 1, height: 16)
                Button { store.sheet = .ink } label: {
                    HStack(spacing: 5) {
                        InkDrop(fill: n / store.cap).foregroundStyle(full < 1 ? Color(hex: 0xE0529A) : pal.ink)
                        Text("\(full)").monospacedDigit().contentTransition(.numericText(value: Double(full)))
                    }
                    .padding(.leading, 10).padding(.trailing, 12).frame(height: 36)
                }
                .accessibilityLabel("Ink: \(full) of \(Int(store.cap)) drops")
            }
            .sans(15, .subheadline, weight: .medium)
            .foregroundStyle(pal.ink)
            .buttonStyle(.plain)
            .fixedSize()
            .animation(Motion.snap, value: store.book.count)
            .animation(Motion.snap, value: full)
        }
    }
}

struct TierDots: View {
    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<4) { RoundedRectangle(cornerRadius: 1.5).fill(Palette.solid[$0]).frame(width: 5.5, height: 5.5) }
        }
    }
}

/// A drop that fills with the ink level.
struct InkDrop: View {
    var fill: Double
    var body: some View {
        Image(systemName: "drop")
            .overlay {
                Image(systemName: "drop.fill").mask {
                    GeometryReader { g in Rectangle().frame(height: g.size.height * fill).frame(maxHeight: .infinity, alignment: .bottom) }
                }
            }
            .font(.system(size: 13, weight: .semibold))
    }
}

struct SpeakButton: View {
    let word: String
    @State private var taps = 0
    @Environment(\.pal) private var pal
    var body: some View {
        Button { Voice.say(word); taps += 1 } label: {
            Image(systemName: "speaker.wave.2").font(.system(size: 15, weight: .medium))
                .symbolEffect(.bounce, value: taps)
                .frame(width: 40, height: 40)
                .foregroundStyle(pal.ink2)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Say \(word)")
    }
}

enum Voice {
    static let synth = AVSpeechSynthesizer()
    static func say(_ w: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: w)
        u.voice = AVSpeechSynthesisVoice(language: "en-GB")
        u.rate = 0.42
        synth.speak(u)
    }
}
