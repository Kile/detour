import Foundation

/// Safety net behind the generation prompt. Rules:
/// - only legal, safe, public, accessible places; no trespassing, restricted areas, dangerous
///   activities, or isolated places at night;
/// - never require photographing strangers or their faces (talking to people is fine);
/// - no alcohol, gambling or age-restricted items; don't disrupt businesses or staff;
/// - at a venue, respect the event: no staff-only areas, no interrupting talks.
///
/// Rules are negation-aware ("don't climb the fence" passes). `safety_notes` is not scanned
/// because it naturally names the hazards it warns about.
enum SafetyValidator {
    struct Context: Sendable {
        var scope: QuestScope
        var isNightTime: Bool
        /// People quests: chatting with others is allowed and people may appear in photos
        /// (faces are blurred on-device before upload).
        var allowPeople: Bool = false
    }

    /// Possessives and compounds that are about things, not people ("the barista's latte art",
    /// "staff picks", "speaker schedule").
    private static let notAPerson = #"(?!'s|'|-|\s+(picks?|recommend\w*|favourites?|schedule|list|line-?up|board|badges?|signs?|notes?|corner|wall|area|room|entrance|toilets?))"#

    static let peopleRules: [PhraseRule] = [
        PhraseRule("photo-people",
                   #"\b(photo\w*|pictures?|pics?|snap\w*|shoot|shots?|capture\w*|selfies?)\b[^.]{0,40}?\b(strangers?|people|persons?|someone|somebody|passers?-?by|crowds?|staff|employees?|workers?|baristas?|cashiers?|shopkeepers?|waiters?|waitress(es)?|attendees?|speakers?|presenters?|children|kids|bab(y|ies)|volunteers?|organi[sz]ers?)\b"# + notAPerson,
                   message: "asks the player to photograph people"),
        PhraseRule("selfie-with",
                   #"\bselfies?\s+with\s+(a\s+|an\s+|the\s+|some\s+)?(strangers?|persons?|someone|somebody|staff|employees?|locals?|attendees?|speakers?|new friends?|friends?|volunteers?|organi[sz]ers?)\b"#,
                   message: "asks for a selfie with another person"),
    ]

    /// Solo mode: success criteria must never need a person in the frame.
    static let personInCriteriaRule = PhraseRule(
        "criteria-person",
        #"\b(persons?|people|someone|somebody|strangers?|crowds?|staff members?|employees?|attendees?|presenters?|human faces?)\b"# + notAPerson,
        message: "needs a person to be visible in the photo")

    /// Faces are blurred before upload and identity is never checked, so proof can't depend on them.
    static let identityRule = PhraseRule(
        "identity",
        #"\b(human faces?|their faces?|(person|someone|somebody|people)'?s? faces?|faces? (is|are) (visible|showing|clear)|facial\w*|smil(e|es|ing)|eye contact|identity|identif(y|ies|ied|ying)\s+(the |a |each |every )?(who|person|people|someone|somebody|them|him|her|attendees?|hackers?|faces?)|recogni[sz]\w*\s+(the |a |each |every )?(person|people|someone|somebody|them|him|her|attendees?|hackers?|faces?)|(person|people|someone|somebody|they|he|she|faces?) (is|are) (recogni[sz]able|identifiable)|their (full )?names?|name (badge|tag|card|lanyard)s?|lanyards?|phone numbers?|email address\w*|home address\w*)\b"#,
        message: "relies on faces, names or personal details (faces are blurred and identity is never checked)")

    /// Solo mode: the quest must not need anyone else.
    static let interactionRule = PhraseRule(
        "needs-people",
        #"\b(ask (a|an|some|someone|somebody|a stranger|staff|the staff|a person|people|another|other|them|fellow)|talk(ing)? to (someone|somebody|a|an|people|other|another|staff|fellow)|chat(ting)? (with|to) (someone|somebody|a|an|people|other|another|fellow)|interview\w*|find (someone|somebody|a person|a stranger|people|an attendee|a hacker|a team|another (person|attendee|hacker|team))|get (someone|somebody|a stranger|people|\d+|two|three|four|five) (people )?to|high[- ]fives?|fist[- ]bumps?|introduce yourself|team up with|recruit\w*)\b"#,
        message: "needs other people, but people quests are turned off")

    /// People mode: photos that include someone (or their things) need their OK first.
    static let consentRegex = try! NSRegularExpression(
        pattern: #"\b(ask(ing)?|permission|consent|okay with|ok with|happy (to|with)|if they('re| are)? (up for|agree|happy)|agree\w*|with their (ok|okay|blessing))\b"#,
        options: [.caseInsensitive])

    /// Never involve children, in any mode.
    static let childrenRule = PhraseRule(
        "children",
        #"\b(children|child|kids?|bab(y|ies)|toddlers?|minors?|teenagers?|teens?|schoolkids?|pupils?)\b"# + notAPerson,
        message: "involves children")

    static let placeRules: [PhraseRule] = [
        PhraseRule("trespass",
                   #"\b(trespass\w*|restricted areas?|staff[- ]only|employees? only|authori[sz]ed personnel|private (property|land|garden|road)|behind the (counter|bar|desk|scenes)|backstage|back of house|green room|server rooms?|off[- ]limits|construction sites?|building sites?|scaffolding|railway (lines?|tracks?)|train tracks?|abandoned|derelict|sewers?|storm drains?|locked (doors?|gates?|rooms?))\b"#,
                   message: "involves a restricted or private area"),
        PhraseRule("roof", #"\b(on|onto|up to|up on|climb\w*)\s+(the\s+|a\s+)?(roofs?|rooftops?)\b"#, message: "involves going onto a roof"),
        PhraseRule("climb",
                   #"\bclimb\w*\s+(on|onto|up|over|into)\b(?!\s+(the\s+)?(stairs|steps|staircase))|\bclimb\w*\s+(a\s+|the\s+)?(trees?|walls?|fences?|railings?|statues?|lamp ?posts?|scaffolding|gates?|monuments?)\b"#,
                   message: "involves climbing"),
        PhraseRule("danger",
                   #"\b(jump\w*|leap\w*)\s+(off|over|from|across|into)\b|\b(swim\w*|wad(e|ing)|paddl(e|ing))\b|\b(stand\w*|lie|lying|sit\w*|walk\w*)\s+(in|on)\s+(the\s+)?(road|traffic|carriageway|tracks?)\b|\binto\s+traffic\b|\bedge of (the\s+)?(cliff|platform|roof|bridge)\b|\bledges?\b|\bfireworks?\b|\b(knife|knives|weapons?|guns?|firearms?)\b|\b(break\w*|sneak\w*)\s+(in|into)\b|\bpick\w*\s+(a\s+)?locks?\b|\b(steal\w*|shoplift\w*)\b|\b(spray[- ]?paint\w*|deface\w*|vandal\w*)\b|\bdrones?\b|\bdumpster\w*\b|\bhitch-?hik\w*\b"#,
                   message: "involves a dangerous or illegal activity"),
        PhraseRule("isolated",
                   #"\b(secluded|isolated|deserted)\b|\bremote\s+(spot|area|location|corner|place|path)s?\b|\bempty\s+(car parks?|lots?|streets?|alleys?)\b|\balone at night\b"#,
                   message: "sends the player somewhere isolated"),
    ]

    static let nightRules: [PhraseRule] = [
        PhraseRule("night-isolated",
                   #"\b(parks?|woods?|woodlands?|forests?|alley(way)?s?|towpaths?|underpass(es)?|subways?|cemeter(y|ies)|graveyards?|churchyards?|beach(es)?|trails?|riverbanks?|canals?|canalside|footpaths?|car parks?)\b"#,
                   message: "sends the player somewhere that may be dark or isolated at night"),
    ]

    static let ageRestrictedRules: [PhraseRule] = [
        PhraseRule("alcohol",
                   #"\b(alcohol\w*|beers?|wines?|pints?|cocktails?|vodka|whisk(e)?y|gin|rum|liquor|booze|boozy|brewer(y|ies)|winer(y|ies)|distiller(y|ies)|pubs?|pub crawl|bar crawl|happy hour|off[- ]licen[cs]es?|liquor stores?|prosecco|champagne|cider|lager|ale)\b"#,
                   message: "involves alcohol or a pub/bar"),
        PhraseRule("gambling",
                   #"\b(casinos?|gambl\w*|betting|bookmakers?|bookies|lotter(y|ies)|scratch ?cards?|slot machines?|fruit machines?|poker|roulette|blackjack)\b"#,
                   message: "involves gambling"),
        PhraseRule("age-restricted",
                   #"\b(cigarettes?|cigars?|tobacco\w*|vap(e|es|ing)|e-cigarettes?|shisha|hookah|cannabis|marijuana|nightclubs?|strip clubs?|sex shops?|adult shops?)\b"#,
                   message: "involves an age-restricted item or place"),
    ]

    static let disruptionRules: [PhraseRule] = [
        PhraseRule("disrupt",
                   #"\b(rearrang\w*|re-arrang\w*|pranks?|interrupt\w*|disrupt\w*|shout(s|ed|ing)?|yell(s|ed|ing)?|scream(s|ed|ing)?)\b|\bmove\s+(the|their|any|some)\s+(items?|products?|stock|displays?|merchandise|chairs?|tables?|signs?)\b|\bblock\w*\s+(the\s+|a\s+)?(door(way)?s?|entrances?|exits?|fire exits?|aisles?|paths?|queues?)\b|\bstand\w*\s+on\s+(a\s+|the\s+)?(tables?|chairs?|benches?|counters?)\b|\btouch\w*\s+(the\s+)?exhibits?\b|\b(handle|handling|open\w*)\s+(the\s+)?(merchandise|stock|packaging|boxes)\b"#,
                   message: "could disrupt a business, staff or other people"),
    ]

    static let venueRules: [PhraseRule] = [
        PhraseRule("venue-stage",
                   #"\b(go|get|walk|step|climb|jump|hop)\w*\s+(on|onto|up on)\s+(the\s+)?stage\b|\b(grab|take|borrow|use)\s+(the\s+)?(mic|microphone)\b|\bduring\s+(a|the)\s+(talk|keynote|session|presentation|workshop|demo|pitch)\b|\b(speaker|judge|organi[sz]er)s?'?\s+(laptop|notes|room|office|desk|table)\b"#,
                   message: "doesn't respect the event (stage, talks, organiser areas)"),
    ]

    /// Words that look like "bar" but are harmless (chocolate bar, salad bar…).
    static let harmlessBarPrefixes: Set<String> = [
        "chocolate", "candy", "snack", "salad", "cereal", "granola", "protein", "energy", "breakfast", "juice",
        "coffee", "espresso", "smoothie", "progress", "sand", "monkey", "grab", "crow", "menu", "status", "tab",
        "space", "nav", "navigation", "tool", "side", "search", "title", "health", "soap", "gold", "iron", "metal",
        "towel", "handle", "pull", "high", "low", "salt", "milkshake", "ice cream", "dessert", "noodle", "sushi",
        "poke", "taco", "hot chocolate", "brow", "nail", "oxygen", "bike", "handle", "lego", "pinch",
    ]

    static func validate(_ quest: Quest, context: Context) -> [QuestViolation] {
        var violations: [QuestViolation] = []
        let fields: [(name: String, text: String)] = [
            ("title", quest.title), ("description", quest.description), ("target_place", quest.targetPlace),
            ("photo_instructions", quest.photoInstructions), ("free_path", quest.freePath),
        ] + quest.successCriteria.map { ("success_criteria", $0) }

        var rules = placeRules + ageRestrictedRules + disruptionRules + [childrenRule]
        if context.isNightTime { rules += nightRules }
        if context.scope == .venue { rules += venueRules }
        // Solo mode keeps people out of the photo and out of the quest entirely.
        if !context.allowPeople { rules += peopleRules + [interactionRule] }

        for field in fields {
            for rule in rules {
                if let hit = rule.firstViolation(in: field.text) {
                    violations.append(QuestViolation(rule: .safety, message: "\(field.name) \(rule.message) (\"\(hit)\")"))
                }
            }
            if let hit = barMention(in: field.text) {
                violations.append(QuestViolation(rule: .safety, message: "\(field.name) involves a bar (\"\(hit)\")"))
            }
        }

        let proofFields = quest.successCriteria.map { ("success_criteria", $0) } + [("photo_instructions", quest.photoInstructions)]
        for (name, text) in proofFields {
            if let hit = identityRule.firstViolation(in: text) {
                violations.append(QuestViolation(rule: .safety, message: "\(name) \(identityRule.message) (\"\(hit)\")"))
            }
        }

        if context.allowPeople {
            // Anyone who ends up in the photo, or whose things do, must be asked first.
            let photographsPeople = quest.involvesPeople
                || fields.contains { field in peopleRules.contains { $0.firstViolation(in: field.text) != nil } }
            if photographsPeople {
                let allText = TextRules.normalize(quest.allText.joined(separator: " "))
                if consentRegex.firstMatch(in: allText, range: NSRange(allText.startIndex..., in: allText)) == nil {
                    violations.append(QuestViolation(rule: .safety, message: "involves other people but never tells the player to ask their permission first"))
                }
            }
        } else {
            if quest.involvesPeople {
                violations.append(QuestViolation(rule: .safety, message: "involves_people is true, but people quests are turned off"))
            }
            for criterion in quest.successCriteria {
                if let hit = personInCriteriaRule.firstViolation(in: criterion) {
                    violations.append(QuestViolation(rule: .safety, message: "success_criteria \(personInCriteriaRule.message) (\"\(hit)\")"))
                }
            }
        }
        return violations
    }

    private static let barRegex = try! NSRegularExpression(pattern: #"(\b[\w-]+\s+)?(\b[\w-]+\s+)?\bbars?\b"#, options: [.caseInsensitive])

    /// Finds "bar"/"bars" used as a drinking venue, ignoring "chocolate bar", "salad bar", etc.
    static func barMention(in text: String) -> String? {
        for clause in TextRules.clauses(of: text) where !TextRules.isNegated(clause) {
            let range = NSRange(clause.startIndex..., in: clause)
            for match in barRegex.matches(in: clause, range: range) {
                let previous = [match.range(at: 1), match.range(at: 2)].compactMap { r -> String? in
                    guard let rr = Range(r, in: clause) else { return nil }
                    return clause[rr].trimmingCharacters(in: .whitespaces).lowercased()
                }
                let lastWord = previous.last ?? ""
                let lastTwo = previous.joined(separator: " ")
                if harmlessBarPrefixes.contains(lastWord) || harmlessBarPrefixes.contains(lastTwo) { continue }
                if let r = Range(match.range, in: clause) { return String(clause[r]) }
            }
        }
        return nil
    }
}
