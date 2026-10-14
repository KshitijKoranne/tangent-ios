import SwiftUI

struct Found: Codable { var day: Int; var tier: Int }
struct Ink: Codable { var level: Double; var at: Date }

enum Visit: Hashable { case fresh, owned, dry }

/// One page on the trail. `src` is the word the page grew out of (for the zoom transition).
struct Hop: Hashable { let word: String; let src: String; var visit: Visit; var depth: Int }

struct Toast: Equatable, Identifiable { let id = UUID(); let text: String; let tier: Int; var seconds = 2.8 }

enum Sheet: String, Identifiable { case ink, themes, pro; var id: String { rawValue } }

/// Everything the player owns. Saved as one small JSON file.
@Observable final class Store {
    var book: [String: Found] = [:]
    var best = 0
    var ink = Ink(level: 10, at: .now)
    var isPro = false
    var skin = Skin.paper
    var proSeen = false
    var onboarded = false
    var scratch = false           // the onboarding practice store: never written to disk
    var joined = false            // said yes to the Board (Game Center); the sign-in prompt only ever follows a yes
    var trail: [String] = []      // words found today, in order: today's card and the share text
    var trailDay = 0

    // session state
    var tab = 0
    var sheet: Sheet?
    var proLine: String?
    var trySkin: Skin?            // a theme being tried in the Themes sheet
    var toast: Toast?
    var haptic: SensoryFeedback = .selection
    var hapticTick = 0
    var dryTold = false

    static let paywallAt = 50
    #if DEBUG
    static let sells = true
    #else
    static let sells = false // ponytail: flip when StoreKit products exist in App Store Connect
    #endif
    static let milestones: Set = [10, 25, 100, 250, 500, 1000, 2500, 5000]

    /// Local calendar day number, so the sentence changes at the user's midnight.
    static var today: Int { day(.now) }
    static func day(_ d: Date) -> Int { Int((d.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: d))) / 86_400) }
    /// Day 1 is launch day. The stride walks all seeds in an order that does not line up with the calendar.
    static let launch = 20_740 // 14 Oct 2026
    static var number: Int { max(1, today - launch + 1) }
    static func sentence(_ day: Int = today) -> String { Lexicon.seeds[(day * 37) % Lexicon.seeds.count] } // ponytail: 37 is coprime with 100 seeds

    var shownSkin: Skin { trySkin ?? skin }
    var foundToday: Int { let d = Self.today; return book.values.lazy.filter { $0.day == d }.count }
    var tierCounts: [Int] { book.values.reduce(into: [0, 0, 0, 0]) { $0[$1.tier] += 1 } }
    var todayTrail: [String] { trailDay == Self.today ? trail : [] }

    /// Days in a row with at least one find. Today still counts as alive until midnight.
    var streak: Int {
        let days = Set(book.values.map(\.day))
        var d = days.contains(Self.today) ? Self.today : Self.today - 1, n = 0
        while days.contains(d) { n += 1; d -= 1 }
        return n
    }

    /// Wordle-style result: squares by rarity, no words, so the trail stays a surprise.
    var shareText: String {
        let sq = ["🟨", "🟩", "🟦", "🟪"], t = todayTrail, lex = Lexicon.shared
        let rare = t.filter { (lex.tier[$0] ?? 0) >= 2 }.count
        var s = "Tangent No. \(Self.number)\n" + t.map { sq[lex.tier[$0] ?? 0] }.joined()
        s += "\n\(t.count) new " + (t.count == 1 ? "word" : "words")
        if rare > 0 { s += " · \(rare) rare" }
        if streak > 1 { s += " · \(streak)-day streak" }
        return s
    }

    // MARK: ink — each new word costs a drop; drops refill one at a time

    var cap: Double { isPro ? 30 : 10 }
    var refill: TimeInterval { isPro ? 12 * 60 : 24 * 60 }
    /// The inkwell is full again at local midnight, with the new sentence.
    func inkNow(_ now: Date = .now) -> Double {
        if Self.day(ink.at) < Self.day(now) { return cap }
        return min(cap, max(0, ink.level + max(0, now.timeIntervalSince(ink.at)) / refill)) // clock set back: no negative ink
    }
    func nextDrop(_ now: Date = .now) -> TimeInterval {
        let n = inkNow(now)
        return n >= cap ? 0 : (1 - n.truncatingRemainder(dividingBy: 1)) * refill
    }
    private func spend() -> Bool {
        let n = inkNow()
        guard n >= 1 else { return false }
        ink = Ink(level: n - 1, at: .now)
        return true
    }

    // MARK: finding words

    /// Called when a page opens. Adds the word to the book if it is new and there is ink.
    func visit(_ w: String) -> Visit {
        if book[w] != nil { feel(.selection); return .owned }
        guard spend() else {
            feel(.warning)
            if !dryTold {
                dryTold = true
                if Self.sells, !proSeen, !isPro { later { self.openPro("Out of ink. Pro holds 30 drops, and each one refills twice as fast.") } }
                else { say("Out of ink. Keep reading. New words wait for the next drop in \(Self.dur(nextDrop())).", 0, 4.2) }
            }
            save(); return .dry
        }
        let t = Lexicon.shared.tier[w] ?? 0
        book[w] = Found(day: Self.today, tier: t)
        if trailDay != Self.today { trail = []; trailDay = Self.today }
        trail.append(w)
        feel(t >= 2 ? .success : .impact(flexibility: .soft, intensity: 0.7))
        if Self.milestones.contains(book.count) { say("\(book.count) words in your book.", t) }
        else if t == 2 { say("Rare find. “\(w)” turns up about once in a million words.", 2) }
        else if t == 3 { say("Obscure find. “\(w)” turns up less than once in ten million words.", 3, 3.6) }
        else if trail.count == 1, streak > 1 { say("Day \(streak) in a row. Fresh sentence, full inkwell.", 0) }
        if Self.sells, book.count == Self.paywallAt, !proSeen, !isPro { later { self.openPro("You've found \(Self.paywallAt) words. Pro lets you find three times as many each day.") } }
        save()
        return .fresh
    }

    /// Opens the paywall after the page lands, and never on top of another sheet.
    private func later(_ f: @escaping () -> Void) {
        Task { try? await Task.sleep(for: .seconds(1.6)); if self.sheet == nil { f() } }
    }

    func openPro(_ line: String? = nil) {
        guard Self.sells else { say("Pro opens with a later update. Everything here is free until then.", 0, 3.6); return }
        proLine = line; proSeen = true; sheet = .pro; save()
    }

    func setPro(_ on: Bool) { // ponytail: preview switch until StoreKit products exist in App Store Connect
        let n = inkNow(); isPro = on
        ink = Ink(level: on ? 30 : min(n, 10), at: .now)
        if !on { skin = .paper }
        save()
    }

    func feel(_ f: SensoryFeedback) { haptic = f; hapticTick += 1 }
    func say(_ text: String, _ tier: Int, _ seconds: Double = 2.8) { toast = Toast(text: text, tier: tier, seconds: seconds) }

    static func dur(_ s: TimeInterval) -> String {
        let m = max(1, Int((s / 60).rounded(.up)))
        return m < 60 ? "\(m) min" : "\(m / 60) h" + (m % 60 > 0 ? " \(m % 60) min" : "")
    }
    static func date(_ day: Int) -> String {
        guard day != today else { return "Today" }
        var f = Date.FormatStyle.dateTime.day().month(.abbreviated)
        f.timeZone = .gmt; f.locale = Locale(identifier: "en_GB")
        return Date(timeIntervalSince1970: Double(day) * 86_400).formatted(f)
    }

    // MARK: saving

    // New fields must be optional, so an older file still decodes.
    private struct Saved: Codable { var book: [String: Found]; var best: Int; var ink: Ink; var isPro: Bool; var skin: Skin?; var proSeen: Bool; var onboarded: Bool?; var joined: Bool?; var trail: [String]?; var trailDay: Int? }

    /// An empty store that is never saved. The onboarding uses it so tapped words light up without touching the real book.
    static func blank() -> Store { Store(scratch: true) }
    private static let url = URL.documentsDirectory.appending(path: "tangent.json")

    init(scratch: Bool = false) {
        self.scratch = scratch
        guard !scratch else { return }
        if let d = try? Data(contentsOf: Self.url) {
            if let s = try? JSONDecoder().decode(Saved.self, from: d) {
                book = s.book; best = s.best; ink = s.ink; isPro = s.isPro; skin = s.isPro ? s.skin ?? .paper : .paper; proSeen = s.proSeen
                onboarded = s.onboarded ?? false; joined = s.joined ?? false; trail = s.trail ?? []; trailDay = s.trailDay ?? 0
            } else { // never overwrite a book we could not read: keep a copy first
                try? d.write(to: URL.documentsDirectory.appending(path: "tangent-\(Int(Date.now.timeIntervalSince1970)).bak.json"))
            }
        }
        #if DEBUG
        Demo.apply(self)
        #endif
    }

    func save() {
        guard !scratch else { return }
        let s = Saved(book: book, best: best, ink: ink, isPro: isPro, skin: skin, proSeen: proSeen, onboarded: onboarded, joined: joined, trail: trail, trailDay: trailDay)
        try? JSONEncoder().encode(s).write(to: Self.url, options: .atomic)
    }
}

#if DEBUG
/// Launch arguments for checking screens in the Simulator, e.g. `-demo 60 -tab 1 -sheet pro -skin blueprint -open lantern`.
enum Demo {
    static let d = UserDefaults.standard
    static func apply(_ s: Store) {
        s.onboarded = !d.bool(forKey: "onboard") // the tour only shows in debug runs started with -onboard 1
        if d.bool(forKey: "joined") { s.joined = true }
        if d.bool(forKey: "fresh") { s.book = [:]; s.best = 0; s.ink = Ink(level: 10, at: .now); s.isPro = false; s.skin = .paper; s.proSeen = false }
        let n = d.integer(forKey: "demo")
        if n > 0 {
            let lex = Lexicon.shared
            let pool = lex.tier.keys.sorted()
            for i in 0..<n {
                let w = pool[(i * 7919 + 1301) % pool.count]
                s.book[w] = Found(day: Store.today - (i % 9 == 0 ? 0 : i / 6), tier: lex.tier[w] ?? 0)
            }
            s.best = 14; s.proSeen = true
        }
        if let v = d.string(forKey: "ink"), let l = Double(v) { s.ink = Ink(level: l, at: .now) }
        if d.bool(forKey: "pro") { s.isPro = true }
        if let v = d.string(forKey: "skin"), let k = Skin(rawValue: v) { s.skin = k; if !k.isFree { s.isPro = true } }
        s.tab = d.integer(forKey: "tab")
        if let v = d.string(forKey: "sheet") { s.sheet = Sheet(rawValue: v) }
        if let v = d.string(forKey: "toast") { s.say(v, 2, 60) }
    }
}
#endif
