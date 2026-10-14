import SwiftUI

// MARK: - Skins

enum Skin: String, CaseIterable, Codable, Identifiable {
    case paper, blueprint, library, riso, chalk
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var isFree: Bool { self == .paper }
    /// Paper follows the system. The others fix the scheme so the system chrome matches.
    var scheme: ColorScheme? {
        switch self { case .paper: nil; case .riso: .light; default: .dark }
    }
}

struct Palette {
    var bg, surface, ink, ink2, ink3, rule: Color
    var hl: [Color]           // highlighter per rarity tier, at display strength
    var pattern = Pattern.none
    enum Pattern { case none, grid, glow, dots, chalk }
    /// Full-strength rarity colours for small marks: dots, bars, tags.
    static let solid = [0xFFE14D, 0x86E39A, 0x86BFFF, 0xFF97C6].map { Color(hex: $0) }

    static func of(_ s: Skin, _ scheme: ColorScheme) -> Palette {
        func hl(_ a: Double) -> [Color] { [0xFFE14D, 0x86E39A, 0x86BFFF, 0xFF97C6].map { Color(hex: $0).opacity(a) } }
        switch (s, scheme) {
        case (.paper, .dark):
            return .init(bg: .init(hex: 0x111214), surface: .init(hex: 0x1C1D21), ink: .init(hex: 0xECEAE4), ink2: .init(hex: 0xB2B1AB),
                         ink3: .init(hex: 0x7C7C79), rule: .init(hex: 0x2A2B30), hl: hl(0.32))
        case (.paper, _):
            return .init(bg: .init(hex: 0xFAF9F5), surface: .init(hex: 0xF0EFE9), ink: .init(hex: 0x15171C), ink2: .init(hex: 0x4B4F58),
                         ink3: .init(hex: 0x868A92), rule: .init(hex: 0xE2E1DA), hl: hl(0.8))
        case (.blueprint, _):
            return .init(bg: .init(hex: 0x1A3862), surface: .init(hex: 0x21457A), ink: .init(hex: 0xEAF2FF), ink2: .init(hex: 0xB8CAE6),
                         ink3: .init(hex: 0x86A0C6), rule: .init(hex: 0x2F5589), hl: hl(0.38), pattern: .grid)
        case (.library, _):
            return .init(bg: .init(hex: 0x17231C), surface: .init(hex: 0x213027), ink: .init(hex: 0xF0E9D8), ink2: .init(hex: 0xC7BFAA),
                         ink3: .init(hex: 0x948F7C), rule: .init(hex: 0x2D3E34), hl: hl(0.32), pattern: .glow)
        case (.riso, _):
            return .init(bg: .init(hex: 0xFFFDFB), surface: .init(hex: 0xF1EFF9), ink: .init(hex: 0x2430C2), ink2: .init(hex: 0x4B54C6),
                         ink3: .init(hex: 0x8B90D3), rule: .init(hex: 0xDDDDF2), hl: hl(0.8), pattern: .dots)
        case (.chalk, _):
            return .init(bg: .init(hex: 0x252B28), surface: .init(hex: 0x2F3733), ink: .init(hex: 0xF2F3EE), ink2: .init(hex: 0xC5C9C0),
                         ink3: .init(hex: 0x939A91), rule: .init(hex: 0x3A433E), hl: hl(0.32), pattern: .chalk)
        }
    }
}

extension EnvironmentValues {
    @Entry var pal = Palette.of(.paper, .light)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The page itself: flat paper, or a skin's pattern. Always full bleed.
struct PaperBackground: View {
    @Environment(\.pal) private var p
    var body: some View {
        p.bg.overlay {
            switch p.pattern {
            case .none: EmptyView()
            case .grid:
                Canvas { c, s in
                    var path = Path()
                    for x in stride(from: 0.5, to: s.width, by: 22) { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: s.height)) }
                    for y in stride(from: 0.5, to: s.height, by: 22) { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: s.width, y: y)) }
                    c.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 1)
                }
            case .dots:
                Canvas { c, s in
                    for x in stride(from: 4.5, to: s.width, by: 9) { for y in stride(from: 4.5, to: s.height, by: 9) {
                        c.fill(Path(ellipseIn: .init(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .color(p.ink.opacity(0.1)))
                    } }
                }
            case .glow:
                EllipticalGradient(colors: [Color(hex: 0xE9C46A).opacity(0.2), .clear], center: .init(x: 0.5, y: -0.08), startRadiusFraction: 0, endRadiusFraction: 0.75)
            case .chalk:
                ZStack {
                    RadialGradient(colors: [.white.opacity(0.05), .clear], center: .init(x: 0.18, y: 0.28), startRadius: 0, endRadius: 320)
                    RadialGradient(colors: [.white.opacity(0.035), .clear], center: .init(x: 0.82, y: 0.72), startRadius: 0, endRadius: 360)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Type
// New York for reading, SF Pro for controls, SF Mono for small labels. All scale with Dynamic Type.

private struct Face: ViewModifier {
    @ScaledMetric var size: CGFloat
    let design: Font.Design, weight: Font.Weight, italic: Bool
    init(_ size: CGFloat, _ style: Font.TextStyle, _ design: Font.Design, _ weight: Font.Weight, _ italic: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.design = design; self.weight = weight; self.italic = italic
    }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design)).italic(italic)
    }
}

extension View {
    func serif(_ size: CGFloat, _ style: Font.TextStyle = .body, weight: Font.Weight = .regular, italic: Bool = false) -> some View {
        modifier(Face(size, style, .serif, weight, italic))
    }
    func sans(_ size: CGFloat, _ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> some View {
        modifier(Face(size, style, .default, weight, false))
    }
    /// Small uppercase mono label: dates, counts, section names.
    func label(_ size: CGFloat = 11) -> some View {
        modifier(Face(size, .caption2, .monospaced, .medium, false)).tracking(0.9).textCase(.uppercase)
    }
}

// MARK: - Motion
// One vocabulary for the whole app: fast out, soft landing. Springs only where something lands.

enum Motion {
    static let soft = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
    static let swipe = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.62)
    static let land = Animation.spring(duration: 0.42, bounce: 0.38)
    static let snap = Animation.spring(duration: 0.3, bounce: 0.15)
}

// MARK: - Highlighter

/// A marker stroke: uneven ends, like a real highlighter swipe.
struct Band: Shape {
    func path(in r: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: r.height * 0.16, bottomLeadingRadius: r.height * 0.4,
                               bottomTrailingRadius: r.height * 0.2, topTrailingRadius: r.height * 0.48).path(in: r)
    }
}

extension View {
    /// Draws a highlighter band behind text, from x-height to just under the baseline. `progress` 0...1 swipes it in.
    func band(_ color: Color, _ progress: CGFloat = 1) -> some View {
        background {
            Band().fill(color)
                .padding(.horizontal, -3)
                .scaleEffect(x: progress, y: 0.54, anchor: UnitPoint(x: 0, y: 0.8))
        }
    }
}
