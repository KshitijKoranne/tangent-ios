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
                EntryView(hop: hop, trail: path.prefix(hop.depth - 1).map(\.word), rootName: rootName, nudge: nudge)
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
        path.append(Hop(word: w, src: src, visit: store.visit(w), depth: path.count + 1))
        if path.count > store.best { store.best = path.count; store.save() }
    }
}

// MARK: - Today

struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal

    var body: some View {
        GeometryReader { g in
            TimelineView(.everyMinute) { ctx in // the page turns at midnight even if the app stays open
                let day = Store.day(ctx.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let date = ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.init(identifier: "en_GB")))
                        ViewThatFits(in: .horizontal) { // one line, or stacked at the largest text sizes
                            HStack { Text(date).fixedSize(); Spacer(minLength: 12); Text("No. \(Store.number)").fixedSize() }
                            VStack(alignment: .leading, spacing: 4) { Text(date); Text("No. \(Store.number)") }
                        }
                        .label().foregroundStyle(pal.ink3)

                        Spacer(minLength: 28).frame(maxHeight: g.size.height * 0.12) // the sentence sits a little lower, like a title page
                        Prose(text: Store.sentence(day), size: 34, style: .largeTitle, lineHeight: 1.34, id: "today.\(day)")
                            .foregroundStyle(pal.ink)

                        Spacer(minLength: 48)
                        if store.book.isEmpty { hint } else {
                            if !store.todayTrail.isEmpty { trailCard.padding(.bottom, 28) }
                            stats
                            yesterday(day - 1).padding(.top, 36)
                        }
                        Button { store.onboarded = false } label: {
                            Text("How Tangent works").label(11).underline(color: pal.ink3.opacity(0.5))
                                .frame(minHeight: 44).contentShape(.rect)
                        }
                        .foregroundStyle(pal.ink3).padding(.top, 20)
                    }
                    .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
                    .frame(minHeight: g.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
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
                Text("Tap an underlined word and see where it leads.")
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
                Stat(n: store.streak, label: store.streak == 1 ? "Day streak" : "Days in a row", lit: store.foundToday > 0)
                Stat(n: store.book.count, label: "In your book")
            }
        }
    }

    /// Today's finds in the order they were found, each one tappable, and the share button.
    private var trailCard: some View {
        let t = store.todayTrail
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's trail").label().foregroundStyle(pal.ink3)
                Spacer()
                ShareLink(item: store.shareText) {
                    Label("Share", systemImage: "square.and.arrow.up").sans(14, .subheadline, weight: .semibold)
                        .frame(minHeight: 44).contentShape(.rect)
                }
                .foregroundStyle(pal.ink)
            }
            Flow(gap: 6, leading: 8) {
                ForEach(Array(t.enumerated()), id: \.offset) { i, w in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        WordButton(text: w, lemma: w, src: "trail.\(i)")
                        if i < t.count - 1 { Text("→").foregroundStyle(pal.ink3).accessibilityHidden(true) }
                    }
                }
            }
            .serif(19, .body, italic: true)
            .foregroundStyle(pal.ink)
        }
        .padding(18)
        .background(pal.surface, in: .rect(cornerRadius: 20))
    }

    /// Yesterday's sentence, small. Words found from it keep their highlighter.
    private func yesterday(_ day: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Yesterday").label().foregroundStyle(pal.ink3)
            Prose(text: Store.sentence(day), size: 17, style: .callout, lineHeight: 1.4, id: "yesterday.\(day)")
                .foregroundStyle(pal.ink2)
        }
    }
}

struct Stat: View {
    let n: Int, label: String
    var lit: Bool? = nil // a streak: the dot is solid once today has a find
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n, format: .number).serif(28, .title, weight: .medium).monospacedDigit()
                    .contentTransition(.numericText(value: Double(n)))
                if let lit {
                    Circle().fill(lit ? Palette.solid[0] : .clear).overlay(Circle().strokeBorder(lit ? .clear : pal.ink3, lineWidth: 1.2)).frame(width: 7, height: 7)
                        .accessibilityLabel(lit ? "Today counts" : "Find a word today to keep it")
                }
            }
            .foregroundStyle(pal.ink)
            Text(label).label(11).foregroundStyle(pal.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A word's page

struct EntryView: View {
    let hop: Hop, trail: [String], rootName: String, nudge: Int
    private var depth: Int { hop.depth }
    private var from: String? { trail.last }
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var visit: Visit
    @State private var swipe: CGFloat
    @State private var stamped: Bool
    @State private var shown = false
    @State private var scrolled = false

    init(hop: Hop, trail: [String], rootName: String, nudge: Int) {
        self.hop = hop; self.trail = trail; self.rootName = rootName; self.nudge = nudge
        _visit = State(initialValue: hop.visit)
        _swipe = State(initialValue: hop.visit == .fresh ? 0 : 1)
        _stamped = State(initialValue: hop.visit != .fresh)
    }

    var body: some View {
        let w = hop.word, lex = Lexicon.shared
        let tier = lex.tier[w] ?? 0, senses = lex.senses(w)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TrailStrip(root: rootName, trail: trail, word: w)

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(w).serif(54, .largeTitle, weight: .medium, italic: true)
                        .lineLimit(2).minimumScaleFactor(0.6)
                        .foregroundStyle(pal.ink)
                        .band(pal.hl[tier], swipe)
                        .keyframeAnimator(initialValue: 1.0, trigger: still ? 0 : nudge) { v, s in v.scaleEffect(s, anchor: .leading) } keyframes: { _ in
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
                Text("New · +1").label(11)
                    .padding(.horizontal, 8).frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(pal.ink, lineWidth: 1))
                    .foregroundStyle(pal.ink)
                    .scaleEffect(stamped || still ? 1 : 1.7).rotationEffect(.degrees(stamped || still ? 0 : -9)).opacity(stamped ? 1 : 0)
            case .owned:
                let d = store.book[w]?.day ?? Store.today
                Text(d == Store.today ? "In your book since today" : "In your book since \(Store.date(d))")
                    .sans(13, .footnote).foregroundStyle(pal.ink3)
            case .dry:
                Text("Out of ink").label(11).foregroundStyle(pal.ink2) // outlined: running dry is not a prize, so no highlighter colour
                    .padding(.horizontal, 8).frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(pal.ink3, lineWidth: 1))
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
        guard v == .fresh else { if v == .owned { visit = .owned }; return } // found on another trail meanwhile
        visit = .fresh
        if still { swipe = 1; stamped = true; return }
        swipe = 0; stamped = false
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
                        if !s.types.isEmpty { Related(label: "Kinds", words: Array(s.types.prefix(6)), id: "\(w).\(i).t") }
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
                Text("From").label(11)
                Button { dismiss() } label: { Text(from ?? rootName).serif(15, .subheadline, italic: true).underline(color: pal.ink3.opacity(0.5)) }
                    .foregroundStyle(pal.ink2)
                Spacer()
                Text(depth == 1 ? "1 hop" : "\(depth) hops").label(11)
            }
            .foregroundStyle(pal.ink3)
        }
    }
}

// MARK: - Small parts

/// The way here, at the top of every page: today's sentence → tower → beacon → this word. Tap a step to go back to it.
struct TrailStrip: View {
    let root: String, trail: [String], word: String
    @Environment(\.pal) private var pal
    @Environment(\.openWord) private var open

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(root).label(11)
                ForEach(Array(trail.enumerated()), id: \.offset) { i, w in
                    dot
                    Button { open(w, "strip.\(i)") } label: {
                        Text(w).serif(15, .subheadline, italic: true).band(pal.hl[Lexicon.shared.tier[w] ?? 0].opacity(0.5))
                            .frame(minHeight: 44).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Goes back to this page")
                }
                dot
                Text(word).serif(15, .subheadline, weight: .semibold, italic: true).foregroundStyle(pal.ink)
            }
            .foregroundStyle(pal.ink3)
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.trailing)
        .padding(.horizontal, -24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trail")
    }

    private var dot: some View {
        Capsule().fill(pal.ink3.opacity(0.6)).frame(width: 14, height: 1.5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
            .accessibilityHidden(true)
    }
}

struct Chip: View {
    let text: String, fill: Color
    @Environment(\.pal) private var pal
    var body: some View {
        Text(text).label(11).foregroundStyle(pal.ink)
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
                    .padding(.leading, 12).padding(.trailing, 10).frame(height: 44)
                }
                .accessibilityLabel("\(store.book.count) words in your book")
                Rectangle().fill(pal.ink3.opacity(0.3)).frame(width: 1, height: 16)
                Button { store.sheet = .ink } label: {
                    HStack(spacing: 5) {
                        InkDrop(fill: n / store.cap).foregroundStyle(full < 1 ? pal.ink3 : pal.ink)
                        Text("\(full)").monospacedDigit().contentTransition(.numericText(value: Double(full)))
                    }
                    .padding(.leading, 10).padding(.trailing, 12).frame(height: 44)
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
                .frame(width: 44, height: 44)
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
