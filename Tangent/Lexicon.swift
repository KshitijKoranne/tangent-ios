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
        "A tram rattled past the bakery and the whole window of loaves trembled.",
        "The archivist wore cotton gloves to turn pages older than the city itself.",
        "Rain gathered in the gutters and carried a paper boat towards the sea.",
        "The cobbler's shop smelled of leather, polish and patient afternoons.",
        "A heron stood in the shallows like a question nobody had answered.",
        "The orchard keeper wrapped each young tree in burlap before the first frost.",
        "Somebody left a piano on the pier, and strangers took turns to play it.",
        "The cartographer drew the coastline twice because the tide kept changing her mind.",
        "Steam curled from the teapot while the cards were dealt in silence.",
        "A kite tugged at its string as if it remembered being a bird.",
        "The stonemason carved his initials where only the gargoyles would see them.",
        "Fireflies blinked above the paddy fields like a slow and gentle code.",
        "The ferryman knew every current of the river by the colour of the water.",
        "A bookshop cat slept on the poetry shelf and nobody dared to move her.",
        "The chemist mixed two clear liquids and the beaker blushed a sudden crimson.",
        "Lanterns floated down the canal, each one carrying somebody's quiet wish.",
        "The blacksmith quenched the blade and the forge hissed like an angry dragon.",
        "A shepherd counted his flock at dusk and always came up one short.",
        "The weaver threaded indigo through the loom until the cloth looked like evening.",
        "Pebbles on the beach had been polished smooth by centuries of restless waves.",
        "The conductor raised his baton and the whole hall seemed to inhale.",
        "A sparrow built its nest inside the letter O of the old cinema sign.",
        "The geologist split the rock and found a tiny fern pressed inside it.",
        "Her diary had a lock, but the key hung openly on a ribbon beside it.",
        "The night train hummed through villages whose names nobody on board could pronounce.",
        "A gardener whistled to the tomatoes, convinced that they grew faster for it.",
        "The clock tower was ten minutes slow, and the whole town politely agreed.",
        "Wind combed the wheat into long golden waves that never reached the shore.",
        "The magician's rabbit had quietly retired and now lived in a hatbox.",
        "An old sailor tied knots for children and named each one after a storm.",
        "The surveyor's compass spun wildly near the iron hills, refusing to choose.",
        "Pigeons strutted across the square like magistrates inspecting a market.",
        "The calligrapher waited for her ink to settle before the first stroke.",
        "A canoe slid through the mangroves where the roots knelt into the water.",
        "The botanist pressed a violet between the pages of a borrowed encyclopaedia.",
        "Snow muffled the city until even the traffic seemed to whisper.",
        "The goldsmith weighed the ring on a balance so delicate it trembled at breath.",
        "A street vendor fanned the coals and the smell of roasting corn drifted uptown.",
        "The puppeteer's hands vanished into shadow and the marionettes began to dance.",
        "Dew clung to the spider's web, turning a trap into a chandelier.",
        "The cellist rested her cheek on the instrument as though it might confide in her.",
        "A camel caravan crossed the dunes, following stars older than any map.",
        "The printer set each letter backwards so the page would read the right way.",
        "An owl watched the farmhouse from the barn roof, unblinking and unimpressed.",
        "The lifeguard read a novel between glances at the restless swimmers.",
        "Copper pans hung in the kitchen like a row of small and polished moons.",
        "The explorer's journal ended mid-sentence, and the rest of the page was blank.",
        "A gust of wind stole the umbrella and carried it proudly over the rooftops.",
        "The glassblower turned a molten bead into a swan before the crowd could blink.",
        "Tea pickers moved along the slopes, their baskets filling with green.",
        "The judge adjusted her spectacles and the courtroom held its breath.",
        "A lighthouse beam swept across the bay, counting ships the way it always had.",
        "The baker's apprentice burned the first batch and learned more than any recipe could teach.",
        "Bats poured from the cave at dusk like smoke from a hidden chimney.",
        "The tailor's mannequin wore a different hat each day, and the street noticed.",
        "A sunflower turned its heavy face to follow the afternoon across the field.",
        "The jeweller held the opal to the light and a small storm moved inside it.",
        "Waves erased the sandcastle slowly, as though they were sorry to do it.",
        "The mapmaker's apprentice added a dragon simply because the corner looked empty.",
        "A bicycle bell rang twice and the whole flock of geese stepped aside.",
        "The monk swept the courtyard every morning, though the leaves always returned.",
        "Embers drifted upward from the bonfire and joined the scattered constellations.",
        "The ice cream van played its tune slightly out of key all summer long.",
        "A pearl diver surfaced, gasped once, and smiled at the gift in her palm.",
        "The architect sketched a bridge on a napkin that later crossed a river.",
        "Crickets tuned their instruments in the long grass as the porch light flickered.",
        "The postman knew which dogs to greet and which gates to approach with caution.",
        "An avalanche of laughter tumbled out of the classroom when the bell rang.",
        "The violin maker tapped the spruce and listened for the music trapped inside.",
        "Moonlight silvered the rooftops, and somewhere a window opened to let it in.",
    ]
}
