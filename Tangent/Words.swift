import SwiftUI

// Every dictionary word in a sentence or definition is its own button, laid out like running text.

extension EnvironmentValues {
    /// Opens a word's page. Arguments: the word, and the id of the view it was tapped in.
    @Entry var openWord: (String, String) -> Void = { _, _ in }
    @Entry var zoom: Namespace.ID? = nil
}

/// Wraps its children into lines like text, and lines them up on their baselines.
struct Flow: Layout {
    var gap: CGFloat
    var leading: CGFloat

    private struct Row { var items: [(i: Int, w: CGFloat, base: CGFloat)] = []; var asc: CGFloat = 0; var desc: CGFloat = 0; var width: CGFloat = 0 }

    private func rows(_ maxW: CGFloat, _ subs: Subviews) -> [Row] {
        var out: [Row] = [], cur = Row()
        for (i, s) in subs.enumerated() {
            let d = s.dimensions(in: .unspecified), b = d[.firstTextBaseline]
            let x = cur.items.isEmpty ? 0 : cur.width + gap
            if !cur.items.isEmpty, x + d.width > maxW + 0.5 { out.append(cur); cur = Row() }
            cur.width = (cur.items.isEmpty ? 0 : cur.width + gap) + d.width
            cur.items.append((i, d.width, b))
            cur.asc = max(cur.asc, b); cur.desc = max(cur.desc, d.height - b)
        }
        if !cur.items.isEmpty { out.append(cur) }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rs = rows(proposal.width ?? .infinity, subviews)
        let h = rs.reduce(0) { $0 + $1.asc + $1.desc } + leading * CGFloat(max(0, rs.count - 1))
        return CGSize(width: proposal.width ?? rs.map(\.width).max() ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for r in rows(bounds.width, subviews) {
            var x = bounds.minX
            for it in r.items {
                subviews[it.i].place(at: CGPoint(x: x, y: y + r.asc - it.base), proposal: .unspecified)
                x += it.w + gap
            }
            y += r.asc + r.desc + leading
        }
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline, let r = rows(bounds.width, subviews).first else { return nil }
        return bounds.minY + r.asc
    }
}

/// Running text where dictionary words can be tapped.
struct Prose: View {
    let text: String
    var size: CGFloat = 19
    var style: Font.TextStyle = .body
    var italic = false
    var lineHeight: CGFloat = 1.5
    var lead: String?                 // e.g. "noun", set in the margin style
    var id: String                    // unique per paragraph, for transition sources

    @ScaledMetric private var scale: CGFloat = 1
    @Environment(\.pal) private var pal

    var body: some View {
        let s = size * scale
        Flow(gap: s * 0.25, leading: s * (lineHeight - 1.2)) {
            if let lead { Text(lead).serif(size - 3, style, italic: true).foregroundStyle(pal.ink3).padding(.trailing, 3) }
            ForEach(Array(Self.chunks(text).enumerated()), id: \.offset) { i, parts in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { j, p in
                        if let l = p.lemma { WordButton(text: p.text, lemma: l, src: "\(id).\(i).\(j)") } else { Text(p.text) }
                    }
                }
                .fixedSize() // a word never shrinks to "pit…": it moves to the next line instead
            }
        }
        .serif(size, style, italic: italic)
    }

    /// "cartographer's" -> ["cartographer", "'", "s"], each with its dictionary form when it has one.
    static func chunks(_ s: String) -> [[(text: String, lemma: String?)]] {
        s.split(separator: " ").map { c in
            var parts: [(text: String, lemma: String?)] = [], cur = "", alpha: Bool?
            func flush() { if let a = alpha, !cur.isEmpty { parts.append((cur, a ? Lexicon.shared.lemma(cur) : nil)) } }
            for ch in c {
                let a = ch.isASCII && ch.isLetter
                if alpha != nil, a != alpha { flush(); cur = "" }
                cur.append(ch); alpha = a
            }
            flush()
            return parts
        }
    }
}

/// A list of related words with a small label: "SAME AS  mensural, mensurable"
struct Related: View {
    let label: String, words: [String], id: String
    @Environment(\.pal) private var pal
    var body: some View {
        Flow(gap: 5, leading: 6) {
            Text(label).label(10).foregroundStyle(pal.ink3).padding(.trailing, 6)
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    let shown = w.replacingOccurrences(of: "_", with: " ")
                    if Lexicon.shared.tier[w] != nil { WordButton(text: shown, lemma: w, src: "\(id).\(i)") } else { Text(shown) }
                    if i < words.count - 1 { Text(",") }
                }
            }
        }
        .serif(16, .callout)
    }
}

struct WordButton: View {
    let text: String, lemma: String, src: String
    @Environment(Store.self) private var store
    @Environment(\.pal) private var pal
    @Environment(\.openWord) private var open
    @Environment(\.zoom) private var zoom

    var body: some View {
        let tier = Lexicon.shared.tier[lemma] ?? 0
        Button { open(lemma, src) } label: {
            Text(text).underline(store.book[lemma] == nil, color: pal.ink3.opacity(0.55)).fixedSize()
        }
        .buttonStyle(WordStyle(color: pal.hl[tier], found: store.book[lemma] != nil))
        .modifier(ZoomSource(id: src, ns: zoom))
        .accessibilityHint(store.book[lemma] == nil ? "New word" : "In your book")
    }
}

private struct WordStyle: ButtonStyle {
    let color: Color, found: Bool
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .foregroundStyle(.primary)
            .band(color.opacity(found ? 1 : 0.5), found || c.isPressed ? 1 : 0)
            .scaleEffect(c.isPressed ? 0.96 : 1)
            .animation(c.isPressed ? .easeOut(duration: 0.08) : Motion.soft, value: c.isPressed)
            .contentShape(Rectangle().inset(by: -4))
    }
}

struct ZoomSource: ViewModifier {
    let id: String, ns: Namespace.ID?
    func body(content: Content) -> some View {
        if let ns { content.matchedTransitionSource(id: id, in: ns) } else { content }
    }
}
