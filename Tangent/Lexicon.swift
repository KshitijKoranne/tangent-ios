import Foundation

/// One meaning of a word: part of speech, definition, example, and three lists of related words.
struct Sense {
    let pos: String, def: String, ex: String
    let same: [String], typeOf: [String], types: [String]
}

/// WordNet 3.0, bundled. 77k words in 64 hash shards, loaded on first use.
final class Lexicon {
    static let shared = Lexicon() // ponytail: one read-only dictionary for the whole app

    private(set) var tier: [String: Int] = [:]   // word -> 0 common, 1 uncommon, 2 rare, 3 obscure
    private var exc: [String: String] = [:]     // irregular forms: mice -> mouse
    private var shards: [Int: [String: Any]] = [:]
    private var cache: [String: [Sense]] = [:]
    private var sortedWords: [String]?
    var count: Int { tier.count }

    private init() {
        if let u = Bundle.main.url(forResource: "w", withExtension: "txt"), let s = try? String(contentsOf: u, encoding: .utf8) {
            tier.reserveCapacity(78_000)
            for (t, line) in s.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for w in line.split(separator: " ") { tier[String(w)] = t }
            }
        }
        if let u = Bundle.main.url(forResource: "x", withExtension: "json"), let d = try? Data(contentsOf: u) {
            exc = (try? JSONDecoder().decode([String: String].self, from: d)) ?? [:]
        }
    }

    /// "running" -> "run", "mice" -> "mouse". nil for stop words and words not in the book.
    func lemma(_ token: String) -> String? {
        let t = token.lowercased()
        if Self.stop.contains(t) { return nil }
        if tier[t] != nil { return t }
        if let e = exc[t], tier[e] != nil { return e }
        for (a, b) in Self.rules where t.hasSuffix(a) && t.count > a.count + 1 {
            let c = String(t.dropLast(a.count)) + b
            if tier[c] != nil { return c }
            if c.count > 2, c.last == c.dropLast().last, tier[String(c.dropLast())] != nil { return String(c.dropLast()) } // stopped -> stop
        }
        return nil
    }

    func senses(_ w: String) -> [Sense] {
        if let c = cache[w] { return c }
        let n = Self.shard(w)
        if shards[n] == nil, let u = Bundle.main.url(forResource: "\(n)", withExtension: "json"),
           let d = try? Data(contentsOf: u), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            shards[n] = o
        }
        let raw = shards[n]?[w] as? [[Any]] ?? []
        let list = raw.map { a in
            Sense(pos: Self.pos[a[0] as? String ?? ""] ?? "", def: a.count > 1 ? a[1] as? String ?? "" : "",
                  ex: a.count > 2 ? a[2] as? String ?? "" : "",
                  same: a.count > 3 ? a[3] as? [String] ?? [] : [],
                  typeOf: a.count > 4 ? a[4] as? [String] ?? [] : [],
                  types: a.count > 5 ? a[5] as? [String] ?? [] : [])
        }
        cache[w] = list
        return list
    }

    /// The words either side, as printed at the top of a dictionary page.
    func neighbours(_ w: String) -> (String, String) {
        if sortedWords == nil { sortedWords = tier.keys.sorted() }
        let s = sortedWords!
        var lo = 0, hi = s.count
        while lo < hi { let m = (lo + hi) / 2; if s[m] < w { lo = m + 1 } else { hi = m } }
        return (lo > 0 ? s[lo - 1] : "", lo + 1 < s.count ? s[lo + 1] : "")
    }

    /// djb2 hash, must match build.py
    static func shard(_ w: String) -> Int {
        var h: UInt32 = 5381
        for c in w.unicodeScalars { h = h &* 33 &+ c.value }
        return Int(h % 64)
    }

    static let tierNames = ["Common", "Uncommon", "Rare", "Obscure"]
    private static let pos = ["n": "noun", "v": "verb", "a": "adjective", "s": "adjective", "r": "adverb"]
    // WordNet morphy detachment rules, tried in order
    private static let rules = [("ies", "y"), ("ses", "s"), ("xes", "x"), ("zes", "z"), ("ches", "ch"), ("shes", "sh"), ("men", "man"),
                                ("es", "e"), ("es", ""), ("ed", "e"), ("ed", ""), ("ing", "e"), ("ing", ""), ("er", ""), ("est", ""),
                                ("er", "e"), ("est", "e"), ("s", "")]
    private static let stop = Set("a an the and or but nor so yet if of in on at to by for from with into onto upon as than then that this these those there here is am are was were be been being do does did doing done have has had having will would shall should can could may might must i me my mine we us our ours you your yours he him his she her hers it its they them their theirs who whom whose which what not no s t o very just also too each every either neither both all any some such own same other another more most less least about above across after against along among around before behind below beneath beside between beyond during except inside near off out over past since through throughout till toward towards under underneath until up via within without when where why how while whether because although though unless once ever never nothing something anything everything one ones someone anyone everyone nobody somebody anybody everybody himself herself itself themselves myself yourself ourselves".split(separator: " ").map(String.init))

    static let seeds = [
        "The lighthouse keeper counted every wave as if the sea owed him money.",
        "A quiet library at dusk smells faintly of dust, glue and forgotten afternoons.",
        "Her grandmother kept buttons in a biscuit tin and stories in every button.",
        "The monsoon arrived late, drumming on tin roofs like an impatient guest.",
        "Somewhere a clockmaker is repairing the hour you wasted yesterday.",
        "The fox paused at the edge of the orchard, weighing hunger against caution.",
        "Old maps drew sea serpents wherever the cartographer's knowledge ran thin.",
        "A single lantern swayed above the harbour while the fishermen mended their nets.",
        "The astronomer whispered to the telescope as though the stars could overhear.",
        "Bread rises slowly in a warm kitchen, patient as a sleeping cat.",
        "The river carved the canyon grain by grain over a million indifferent years.",
        "He wrote letters he never posted and kept them folded inside an atlas.",
        "Frost etched ferns across the window before anyone in the house was awake.",
        "The market was a riot of saffron, cardamom and bargaining voices.",
        "A violinist tuned her instrument while the audience settled like falling snow.",
        "The glacier retreated a little each summer, leaving boulders stranded in meadows.",
        "Children built a fortress of cushions and defended it with remarkable ferocity.",
        "The mechanic listened to the engine the way a doctor listens to a heartbeat.",
        "Moss softened the ancient steps that pilgrims had climbed for centuries.",
        "A migrating flock stitched a ragged line across the pale autumn sky.",
        "The potter's wheel hummed as the clay rose into a trembling bowl.",
        "Thunder rolled over the valley and the cattle gathered beneath the oak.",
        "Every museum hides a storeroom full of treasures nobody has catalogued.",
        "The tailor measured twice, cut once, and hummed an unfamiliar melody.",
        "A comet returns every few decades, punctual as a ghost with an appointment.",
        "The orchestra fell silent and a single cough echoed through the hall.",
        "Salt crystals glittered on the rocks where the tide had briefly retreated.",
        "The beekeeper moved slowly, trusting the swarm to recognise her calm.",
        "An abandoned railway station still announces trains that never arrive.",
        "The detective noticed the muddy boots, the wet umbrella and the nervous smile.",
    ]
}
