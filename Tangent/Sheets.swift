import SwiftUI

// MARK: - Ink

struct InkSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let n = store.inkNow(ctx.date), full = Int(n), cap = Int(store.cap)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Ink").serif(38, .largeTitle, weight: .medium, italic: true).foregroundStyle(pal.ink)
                        Text("Each new word you add to your book uses one drop. Reading is always free, so you can open any word at any time.")
                            .sans(15, .subheadline).foregroundStyle(pal.ink2).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, -12)

                        Flow(gap: cap > 10 ? 5 : 8, leading: 6) {
                            ForEach(0..<cap, id: \.self) { i in
                                InkDrop(fill: min(1, max(0, n - Double(i))))
                                    .font(.system(size: cap > 10 ? 15 : 22, weight: .semibold))
                                    .foregroundStyle(pal.ink.opacity(Double(i) < n.rounded(.up) ? 1 : 0.3))
                            }
                        }
                        .accessibilityHidden(true)

                        HStack(spacing: 10) {
                            tile("\(full) of \(cap)", "Drops left")
                            tile(n >= store.cap ? "Full" : "In \(Store.dur(store.nextDrop(ctx.date)))", "Next drop")
                        }

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 11) {
                            GridRow {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                Text("Free").label(10).foregroundStyle(pal.ink3).gridColumnAlignment(.trailing)
                                Text("Pro").label(10).foregroundStyle(pal.ink3).gridColumnAlignment(.trailing)
                            }
                            planRow("Inkwell", "10 drops", "30 drops")
                            planRow("One drop refills in", "24 min", "12 min")
                            planRow("Most words a day", "about 60", "about 150")
                        }
                        .sans(15, .subheadline).monospacedDigit()

                        Button(store.isPro ? "Turn off Pro preview" : "Get 3× the ink with Pro") {
                            if store.isPro { store.setPro(false); store.say("Pro preview is off.", 0) }
                            else { store.openPro("Pro holds 30 drops of ink, and each drop refills twice as fast.") }
                        }
                        .buttonStyle(InkButton())
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
        }
        .presentationDetents([.fraction(0.8), .large])
    }

    private func tile(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(v).serif(22, .title3, weight: .medium).monospacedDigit().foregroundStyle(pal.ink)
                .contentTransition(.numericText())
            Text(l).label(10).foregroundStyle(pal.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(pal.surface, in: .rect(cornerRadius: 14))
    }

    @ViewBuilder private func planRow(_ a: String, _ free: String, _ pro: String) -> some View {
        Rectangle().fill(pal.rule).frame(height: 1)
        GridRow {
            Text(a).foregroundStyle(pal.ink2)
            Text(free).fontWeight(store.isPro ? .regular : .semibold).foregroundStyle(store.isPro ? pal.ink3 : pal.ink)
            Text(pro).fontWeight(store.isPro ? .semibold : .regular).foregroundStyle(store.isPro ? pal.ink : pal.ink3)
        }
    }
}

// MARK: - Themes

struct ThemesSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Themes").serif(38, .largeTitle, weight: .medium, italic: true).foregroundStyle(pal.ink)
                    Text("Paper is free and follows light and dark mode. The others come with Pro. Tap one to try it.")
                        .sans(15, .subheadline).foregroundStyle(pal.ink2).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, -12)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                        ForEach(Skin.allCases) { k in card(k) }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .safeAreaBar(edge: .bottom) {
                if let t = store.trySkin, !t.isFree, !store.isPro {
                    Button("Keep \(t.name) with Pro") { store.openPro("\(t.name) comes with Pro, along with every other theme.") }
                        .buttonStyle(InkButton())
                        .padding(.horizontal, 24).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.snap, value: store.trySkin)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.selection, trigger: store.shownSkin)
        .onDisappear {
            guard store.sheet != .pro else { return } // keep the preview behind the paywall
            if let t = store.trySkin, t.isFree || store.isPro { store.skin = t; store.save() }
            store.trySkin = nil
        }
    }

    private func card(_ k: Skin) -> some View {
        let p = Palette.of(k, k.scheme ?? (store.skin.scheme == nil ? scheme : .light))
        let on = store.shownSkin == k
        return Button { store.trySkin = k == store.skin ? nil : k } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    PaperBackground().environment(\.pal, p)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("lantern").serif(22, .title3, weight: .medium, italic: true).foregroundStyle(p.ink).band(p.hl[2])
                        Capsule().fill(p.ink3.opacity(0.5)).frame(height: 4)
                        Capsule().fill(p.ink3.opacity(0.5)).frame(width: 56, height: 4)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(p.surface, in: .rect(cornerRadius: 9))
                    .padding(12)
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(on ? pal.ink : pal.rule, lineWidth: on ? 2 : 1))
                HStack {
                    Text(k.name).sans(15, weight: .medium).foregroundStyle(pal.ink)
                    Spacer()
                    if k.isFree { Text("Free").label(9).foregroundStyle(pal.ink3) } else if !store.isPro { ProTag() }
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Pro

struct ProSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var plan = Plan.year
    @State private var swipe: CGFloat = 0

    enum Plan: CaseIterable, Identifiable {
        case year, month, life
        var id: Self { self }
        var title: String { switch self { case .year: "Yearly"; case .month: "Monthly"; case .life: "Lifetime" } }
        var note: String { switch self { case .year: "₹108 a month · 7 days free"; case .month: "Cancel any time"; case .life: "Pay once, keep it" } }
        var inr: String { switch self { case .year: "₹1,299"; case .month: "₹249"; case .life: "₹2,499" } }
        var usd: String { switch self { case .year: "$14.99"; case .month: "$2.99"; case .life: "$29.99" } }
        var cta: String { self == .life ? "Buy Lifetime for ₹2,499" : "Try Pro free for 7 days" }
        var fine: String {
            switch self {
            case .year: "Then ₹1,299 ($14.99) a year. Cancel in Settings any time."
            case .month: "Then ₹249 ($2.99) a month. Cancel in Settings any time."
            case .life: "One payment of ₹2,499 ($29.99). No subscription."
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Keep the words")
                            Text("you find.").band(pal.hl[3], swipe)
                        }
                        .serif(40, .largeTitle, weight: .medium, italic: true).foregroundStyle(pal.ink)
                        Text(store.proLine ?? "Tangent Pro turns your book into words you actually remember.")
                            .sans(16, .callout).foregroundStyle(pal.ink2).fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        feature("drop.fill", nil, "3× the ink", "Hold 30 drops instead of 10, and each drop refills twice as fast.")
                        feature("rectangle.on.rectangle.angled", 0, "Review", "Short quizzes built from your own book, spaced out so each word sticks.")
                        feature("leaf", 1, "Word origins", "Where each word came from and what it first meant.")
                        feature("waveform", 2, "Natural voice", "Hear every word said by a real narrator.")
                        feature("paintpalette", 3, "Themes", "Blueprint, Library, Riso and Chalk.")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose a plan").label(10).foregroundStyle(pal.ink3)
                        ForEach(Plan.allCases) { planRow($0) }
                    }

                    Text("Wandering, your book and the board stay free. Always.")
                        .serif(16, .callout, italic: true).foregroundStyle(pal.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 24).padding(.bottom, 16)
            }
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: 10) {
                    Button(plan.cta, action: buy).buttonStyle(InkButton())
                        .contentTransition(.opacity)
                    Text(plan.fine).sans(12, .caption).foregroundStyle(pal.ink3).multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 6)
                .animation(Motion.soft, value: plan)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Restore") { store.say("Nothing to restore yet.", 0) }.sans(15, .subheadline) }
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.selection, trigger: plan)
        .onAppear { withAnimation(Motion.swipe.delay(0.35)) { swipe = 1 } }
        .onDisappear {
            if let t = store.trySkin, store.isPro { store.skin = t; store.save() }
            store.trySkin = nil
        }
    }

    private func buy() {
        #if DEBUG
        store.setPro(true) // ponytail: preview until StoreKit products exist in App Store Connect
        dismiss()
        store.say("Pro preview is on for this device. No payment was taken.", 3, 3.8)
        #else
        store.say("Purchases open with the App Store release.", 0)
        #endif
    }

    private func feature(_ icon: String, _ tier: Int?, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tier == nil ? pal.bg : Color(hex: 0x15171C))
                .frame(width: 32, height: 32)
                .background(tier.map { Palette.solid[$0] } ?? pal.ink, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).sans(16, .callout, weight: .semibold).foregroundStyle(pal.ink)
                Text(text).sans(14, .subheadline).foregroundStyle(pal.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func planRow(_ p: Plan) -> some View {
        let on = plan == p
        return Button { plan = p } label: {
            HStack(spacing: 14) {
                Circle().strokeBorder(on ? pal.ink : pal.ink3, lineWidth: 1.5).frame(width: 20, height: 20)
                    .overlay { Circle().fill(pal.ink).frame(width: 10, height: 10).scaleEffect(on ? 1 : 0.01) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).sans(16, .callout, weight: .semibold).foregroundStyle(pal.ink)
                    Text(p.note).sans(13, .footnote).foregroundStyle(pal.ink3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(p.inr).sans(16, .callout, weight: .semibold).monospacedDigit().foregroundStyle(pal.ink)
                    Text(p.usd).font(.system(.caption2, design: .monospaced)).foregroundStyle(pal.ink3)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(on ? pal.surface : .clear, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(on ? pal.ink : pal.rule, lineWidth: on ? 1.5 : 1))
            .overlay(alignment: .topTrailing) {
                if p == .year {
                    Text("Best value").label(9).foregroundStyle(Color(hex: 0x15171C))
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(Palette.solid[0], in: .rect(cornerRadius: 4))
                        .offset(x: -14, y: -9)
                }
            }
            .contentShape(.rect)
            .animation(Motion.snap, value: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
