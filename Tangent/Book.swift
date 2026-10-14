import SwiftUI

struct BookView: View {
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal
    @Environment(\.openWord) private var open
    @Environment(\.zoom) private var zoom
    @State private var q = ""

    var body: some View {
        let key = q.trimmingCharacters(in: .whitespaces).lowercased()
        let words = store.book.keys.filter { key.isEmpty || $0.contains(key) }.sorted()
        let groups = Dictionary(grouping: words) { String($0.prefix(1)) }
        let letters = groups.keys.sorted()

        Group {
            if store.book.isEmpty { empty } else {
                List {
                    header
                        .listRowInsets(.init(top: 8, leading: 24, bottom: 20, trailing: 24))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    if words.isEmpty {
                        Text("No word in your book matches “\(q)”.")
                            .serif(17, italic: true).foregroundStyle(pal.ink3)
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                            .listRowInsets(.init(top: 16, leading: 24, bottom: 16, trailing: 24))
                    }
                    ForEach(letters, id: \.self) { l in
                        Section {
                            ForEach(groups[l] ?? [], id: \.self) { row($0) }
                        } header: {
                            Text(l.uppercased()).serif(26, .title2, weight: .medium, italic: true).foregroundStyle(pal.ink)
                                .padding(.top, 14).padding(.bottom, 2)
                        }
                        .sectionIndexLabel(l.uppercased())
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listSectionIndexVisibility(.visible)
                .searchable(text: $q, prompt: "Find a word in your book")
            }
        }
        .background(PaperBackground())
        .navigationTitle("Book")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Wordmark() }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.sheet = .themes } label: { Image(systemName: "paintpalette") }
                    .accessibilityLabel("Themes")
            }
        }
    }

    private func row(_ w: String) -> some View {
        let f = store.book[w]
        return Button { open(w, "book.\(w)") } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(w).serif(20, .title3).foregroundStyle(pal.ink)
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.solid[f?.tier ?? 0]).frame(width: 7, height: 7)
                    Text(Store.date(f?.day ?? Store.today)).label(10)
                }
                .foregroundStyle(pal.ink3)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .modifier(ZoomSource(id: "book.\(w)", ns: zoom))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(pal.rule)
        .listRowInsets(.init(top: 13, leading: 24, bottom: 13, trailing: 34))
    }

    private var header: some View {
        let counts = store.tierCounts
        return VStack(alignment: .leading, spacing: 20) {
            Text("Your book").label().foregroundStyle(pal.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(store.book.count, format: .number).serif(72, .largeTitle, weight: .medium).monospacedDigit()
                    .contentTransition(.numericText(value: Double(store.book.count)))
                    .foregroundStyle(pal.ink)
                Text("words found,\nout of \(Lexicon.shared.count.formatted())")
                    .serif(17, italic: true).foregroundStyle(pal.ink2)
            }
            RarityBar(counts: counts)
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<4) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(counts[t], format: .number).serif(20, .title3, weight: .medium).monospacedDigit().foregroundStyle(pal.ink)
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(Palette.solid[t]).frame(width: 7, height: 7)
                            Text(Lexicon.tierNames[t]).label(11).lineLimit(1)
                        }
                        .foregroundStyle(pal.ink3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            HStack(spacing: 14) {
                Button {
                    if store.isPro { store.say("Review arrives in the next update.", 0) }
                    else { store.openPro("Review builds short quizzes from your own book, so each word sticks.") }
                } label: {
                    HStack(spacing: 8) {
                        Text("Review my words")
                        if !store.isPro { ProTag() }
                    }
                }
                .buttonStyle(InkButton(compact: true))
                .fixedSize()
                Text(store.best == 1 ? "Longest trail: 1 hop" : "Longest trail: \(store.best) hops")
                    .sans(13, .footnote).foregroundStyle(pal.ink3)
            }
            .padding(.top, 4)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your book").label().foregroundStyle(pal.ink3)
            Text("Nothing here yet. Tap a word in today's sentence and it lands on this page.")
                .serif(24, .title2).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
            Button("Open today's sentence") { store.tab = 0 }
                .buttonStyle(InkButton(compact: true)).fixedSize()
                .padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 24).padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Words by rarity, as one bar split in four.
struct RarityBar: View {
    let counts: [Int]
    @Environment(\.pal) private var pal
    var body: some View {
        GeometryReader { g in
            let total = max(1, counts.reduce(0, +)), shown = counts.filter { $0 > 0 }.count
            let w = g.size.width - CGFloat(max(0, shown - 1)) * 2
            HStack(spacing: 2) {
                ForEach(0..<4) { t in
                    if counts[t] > 0 { Rectangle().fill(Palette.solid[t]).frame(width: w * CGFloat(counts[t]) / CGFloat(total)) }
                }
            }
            .frame(width: g.size.width, alignment: .leading)
            .background(pal.surface)
            .clipShape(.capsule)
            .animation(Motion.swipe, value: counts)
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("Words by rarity")
    }
}

struct ProTag: View {
    var body: some View {
        Text("Pro").label(9).foregroundStyle(Color(hex: 0x15171C))
            .padding(.horizontal, 5).frame(height: 17)
            .background(Palette.solid[3], in: .rect(cornerRadius: 4))
    }
}

/// The one solid button style: ink on paper.
struct InkButton: ButtonStyle {
    var compact = false
    func makeBody(configuration c: Configuration) -> some View { InkLabel(c: c, compact: compact) }
    private struct InkLabel: View {
        let c: ButtonStyleConfiguration, compact: Bool
        @Environment(\.pal) private var pal
        var body: some View {
            c.label
                .sans(compact ? 15 : 17, .headline, weight: .semibold)
                .foregroundStyle(pal.bg)
                .padding(.horizontal, compact ? 16 : 20)
                .frame(maxWidth: compact ? nil : .infinity)
                .frame(height: compact ? 42 : 54)
                .background(pal.ink, in: .capsule)
                .scaleEffect(c.isPressed ? 0.97 : 1)
                .opacity(c.isPressed ? 0.88 : 1)
                .animation(Motion.snap, value: c.isPressed)
        }
    }
}
