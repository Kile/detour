import Foundation

/// Offline provider with canned quests and verdicts. Default in the simulator and in demo mode,
/// so development doesn't spend API credit.
struct MockAIProvider: AIProvider {
    enum VerdictMode: String, CaseIterable, Codable, Identifiable, Sendable {
        /// Uses the outcome of the debug test photo you picked, otherwise passes.
        case auto, pass, fail, unsure
        var id: String { rawValue }
        var title: String { self == .auto ? "Auto (match test photo)" : rawValue.capitalized }
    }

    var verdictMode: VerdictMode = .auto
    /// Debug: make the first attempt of every quest invalid, to show the validators at work.
    var injectInvalidFirstQuest = false
    /// The expected outcome of the last debug test photo, if one was used.
    var testPhotoOutcome: @Sendable () -> Verdict.Outcome? = { nil }
    var latencySeconds: Double = 0.8
    var usage: AIUsageSink = { _ in }
    /// Debug/screenshots: always use the template with this title (if it fits the context).
    var forcedTitle: String? = nil
    /// Debug/screenshots: prefer a place whose name contains this text (several hints: "Opera|Theatre").
    var placeHint: String? = nil

    var kind: ProviderKind { .demo }
    var supportsStrongerRecheck: Bool { true }

    // MARK: AIProvider

    func research(venue: String) async throws -> VenueContext {
        try await pause()
        await usage(AICallRecord(kind: .research, model: "mock", inputTokens: 0, outputTokens: 0, webSearches: 0, costUSD: 0))
        let trimmed = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        // "HackLondon 2026 at Imperial College" → "HackLondon 2026"
        let shortName = trimmed.components(separatedBy: " at ").first?.components(separatedBy: ",").first ?? trimmed
        let name = shortName.isEmpty ? "Your venue" : String(shortName.prefix(40))
        return VenueContext(
            venueName: name,
            summary: "A busy indoor event space with hacking tables, talks and plenty of snacks. (Demo research — no web search was used.)",
            areas: [
                .init(name: "Main hall", description: "Rows of tables where teams hack."),
                .init(name: "Entrance & registration", description: "Welcome desk, signage and lanyards."),
                .init(name: "Food & drinks area", description: "Snacks, fruit, coffee and soft drinks."),
                .init(name: "Stage & talks area", description: "Screens and seating for talks and demos."),
                .init(name: "Chill-out zone", description: "Beanbags, board games and plants."),
                .init(name: "Sponsor stands", description: "Stands with banners, stickers and swag."),
            ],
            typicalThings: ["stickers", "whiteboards", "power strips", "banners", "plants", "directional signs", "snack table"],
            eventsAndHighlights: ["Opening talk", "Midnight snack drop", "Final demos"],
            sponsors: [],
            rulesAndEtiquette: ["Stay out of staff-only and organiser rooms", "Keep quiet near talks in progress"],
            sources: [],
            usedWebSearch: false)
    }

    func generateQuest(context: QuestContext) async throws -> Quest {
        try await pause()
        await usage(AICallRecord(kind: .generate, model: "mock", inputTokens: 0, outputTokens: 0, webSearches: 0, costUSD: 0))

        if injectInvalidFirstQuest && context.rejectionFeedback.isEmpty {
            return Self.invalidQuest
        }

        var templates = MockQuestCatalog.templates.filter {
            $0.scopes.contains(context.scope) && (context.allowPeople || !$0.involvesPeople)
                && $0.mode == context.mode && $0.weather.matches(context.weather, isNight: context.isNightTime)
        }
        // Match the requested difficulty (hard means hard, in demo mode too).
        let inRange = templates.filter { context.difficulty.range.contains($0.difficulty) }
        if !inRange.isEmpty { templates = inRange }
        // With people quests on, lean towards the social ones.
        if context.allowPeople {
            let social = templates.filter(\.involvesPeople)
            if !social.isEmpty && Bool.random() { templates = social }
        }
        if let theme = context.theme {
            let themed = templates.filter { $0.themes.contains(theme) }
            if !themed.isEmpty { templates = themed }
        }
        // Avoid repeats and anything that already failed validation this round.
        let recent = Set(context.recentQuestTitles)
        let fresh = templates.filter { !recent.contains($0.title) }
        if !fresh.isEmpty { templates = fresh }
        if context.places.isEmpty && context.scope != .venue {
            let placeless = templates.filter { !$0.needsPlace }
            if !placeless.isEmpty { templates = placeless }
        }
        if let forcedTitle, let forced = MockQuestCatalog.templates.first(where: { $0.title == forcedTitle }) {
            var context = context
            // Hints are tried in order: "Opera|Theatre|Market".
            let hints = (placeHint ?? "").lowercased().split(separator: "|").map(String.init)
            if let match = hints.lazy.compactMap({ hint in context.places.first { $0.name.lowercased().contains(hint) } }).first {
                context.places = [match]
            } else if placeHint != nil {
                // No match: at least pick a short, proper-looking name ("Seven Dials Market", not "mercatini"
                // or a holiday let's full listing title).
                let nice = context.places.filter { $0.name.first?.isUppercase == true && $0.name.contains(" ") && $0.name.count <= 28 }
                if let best = nice.max(by: { $0.name.count < $1.name.count }) { context.places = [best] }
            }
            return forced.makeQuest(context: context)
        }
        guard let template = templates.randomElement() ?? MockQuestCatalog.templates.first else {
            throw AIError.invalidResponse("No mock quests")
        }
        return template.makeQuest(context: context)
    }

    func verify(photos: [Data], criteria: [String], quest: Quest, useStrongerModel: Bool) async throws -> Verdict {
        try await pause()
        await usage(AICallRecord(kind: useStrongerModel ? .recheck : .verify, model: "mock",
                                 inputTokens: 0, outputTokens: 0, webSearches: 0, costUSD: 0))
        var outcome: Verdict.Outcome
        switch verdictMode {
        case .auto: outcome = testPhotoOutcome() ?? .pass
        case .pass: outcome = .pass
        case .fail: outcome = .fail
        case .unsure: outcome = .unsure
        }
        // The "stronger model" settles unsure photos in demo mode.
        if useStrongerModel && outcome == .unsure { outcome = .pass }
        var verdict = Self.cannedVerdict(outcome, criteria: criteria)
        verdict.recheckedWithStrongerModel = useStrongerModel ? true : nil
        return verdict
    }

    // MARK: Canned data

    static func cannedVerdict(_ outcome: Verdict.Outcome, criteria: [String]) -> Verdict {
        let list = criteria.isEmpty ? ["The photo matches the quest"] : criteria
        switch outcome {
        case .pass:
            return Verdict(verdict: .pass,
                           criteria: list.map { .init(criterion: $0, met: true, reason: "Clearly visible in the photo.") },
                           confidence: 0.92,
                           feedback: "Nailed it! That's a textbook quest shot. 🎉")
        case .unsure:
            return Verdict(verdict: .unsure,
                           criteria: list.enumerated().map { index, text in
                               .init(criterion: text, met: index == 0,
                                     reason: index == 0 ? "Looks right." : "Hard to tell from this angle.")
                           },
                           confidence: 0.45,
                           feedback: "Close! I can't quite make everything out — a closer, steadier shot would settle it.")
        case .fail:
            return Verdict(verdict: .fail,
                           criteria: list.map { .init(criterion: $0, met: false, reason: "I can't see this in the photo.") },
                           confidence: 0.9,
                           feedback: "Hmm, this doesn't look like the quest target. Have another look around and try again!")
        }
    }

    /// Deliberately breaks the money rules (and pressures the player) so the validator rejects it.
    static let invalidQuest = Quest(
        title: "Fancy Coffee Run",
        description: "You must buy the most expensive coffee you can find and treat yourself!",
        targetPlace: "any",
        successCriteria: ["A receipt for the coffee is visible"],
        photoInstructions: "Photograph your coffee next to the receipt.",
        difficulty: 2, points: 30, estimatedTimeMinutes: 15,
        requiresPurchase: true, optionalCostEstimate: 6,
        freePath: "", safetyNotes: "Mind the hot drink.")

    private func pause() async throws {
        guard latencySeconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(latencySeconds * 1_000_000_000))
    }
}

/// A canned quest with placeholders: {place} is replaced by a real place from the context, {venue}
/// by the venue name.
struct MockQuestTemplate: Sendable {
    var title: String
    var description: String
    var criteria: [String]
    var photo: String
    var themes: [QuestTheme]
    var scopes: [QuestScope]
    var difficulty: Int
    var points: Int
    var minutes: Int
    var safety: String
    var freePath: String
    /// Optional purchase sentence (money on only), with its cost in GBP.
    var optionalExtra: (sentence: String, cost: Double)? = nil
    /// Needs other people (only offered when people quests are on).
    var involvesPeople = false
    /// Photos to take (one per find).
    var photoCount = 1
    /// Quest or photo challenge.
    var mode: QuestMode = .quest
    /// When this template makes sense (photo challenges lean on the current weather and light).
    var weather: WeatherFit = .any

    enum WeatherFit: Sendable {
        case any, wet, sunny, dark

        func matches(_ weather: WeatherSnapshot?, isNight: Bool) -> Bool {
            switch self {
            case .any: return true
            case .wet: return weather?.isWet == true
            case .sunny: return weather?.isSunny == true && !isNight
            case .dark: return isNight || weather?.isDay == false
            }
        }
    }

    var needsPlace: Bool { description.contains("{place}") }

    func makeQuest(context: QuestContext) -> Quest {
        var target = "any"
        var placeName = "somewhere nearby"
        switch context.scope {
        case .venue:
            placeName = context.venue?.venueName ?? "the venue"
        case .nearby, .city:
            if needsPlace, let place = context.places.randomElement() {
                target = place.name
                placeName = place.name
            }
        }
        func fill(_ text: String) -> String {
            text.replacingOccurrences(of: "{place}", with: placeName)
                .replacingOccurrences(of: "{venue}", with: context.venue?.venueName ?? "the venue")
        }
        var description = fill(self.description)
        var cost = 0.0
        if context.money.enabled, let extra = optionalExtra, extra.cost <= context.money.effectiveCap {
            description += " " + extra.sentence
            cost = extra.cost
        }
        let range = context.difficulty.range
        return Quest(
            title: title,
            description: description,
            targetPlace: target,
            successCriteria: criteria.map(fill),
            photoInstructions: fill(photo),
            difficulty: min(max(difficulty, range.lowerBound), range.upperBound),
            points: points,
            estimatedTimeMinutes: minutes,
            requiresPurchase: false,
            optionalCostEstimate: cost,
            freePath: fill(freePath),
            safetyNotes: safety,
            involvesPeople: involvesPeople,
            photoCount: photoCount,
            isPhotoChallenge: mode == .photo)
    }
}

enum MockQuestCatalog {
    static let templates: [MockQuestTemplate] = [
        // MARK: Venue
        MockQuestTemplate(
            title: "Sticker Safari",
            description: "Events like {venue} are sticker heaven. Track down a swag table or sticker sheet and find the boldest sticker design going.",
            criteria: ["At least one sticker is clearly visible", "The sticker has a logo, character or bold design"],
            photo: "Get close so the sticker fills most of the frame.",
            themes: [.creative, .explore], scopes: [.venue], difficulty: 1, points: 15, minutes: 10,
            safety: "Only look at stickers that are out on display.",
            freePath: "Just find and photograph a sticker — looking is all it takes."),
        MockQuestTemplate(
            title: "Wayfinder",
            description: "Find a sign at {venue} that points the way to a room or area. Arrows earn style points from the judges (us).",
            criteria: ["A directional sign is visible", "The sign shows an arrow or the name of a room or area"],
            photo: "Shoot the sign straight on so the words are readable.",
            themes: [.explore, .history], scopes: [.venue], difficulty: 1, points: 10, minutes: 5,
            safety: "Stay in public areas and keep corridors clear.",
            freePath: "Walk the public corridors until you spot a sign."),
        MockQuestTemplate(
            title: "Snack Scout",
            description: "Track down the food area and find the most colourful snack on offer — admiring it counts.",
            criteria: ["Food or snacks are visible", "At least two different colours of food are visible"],
            photo: "Fill the frame with the snacks.",
            themes: [.food, .social], scopes: [.venue], difficulty: 1, points: 15, minutes: 10,
            safety: "Leave the snacks tidy for the next hungry hacker.",
            freePath: "Find the snack area and photograph the spread."),
        MockQuestTemplate(
            title: "Whiteboard Wisdom",
            description: "Find a whiteboard, flipchart or wall of sticky notes in a shared area with a doodle or diagram on it.",
            criteria: ["A whiteboard, flipchart or sticky notes are visible", "There is handwriting or a drawing on it"],
            photo: "Frame the board so the drawing fills the shot.",
            themes: [.social, .creative], scopes: [.venue], difficulty: 2, points: 20, minutes: 10,
            safety: "Only photograph boards in shared areas, not a team's private work.",
            freePath: "Find a board in a shared area and snap it."),
        MockQuestTemplate(
            title: "Indoor Jungle",
            description: "Find a plant somewhere at {venue} — real or plastic — and photograph it next to something techy for scale.",
            criteria: ["A plant (real or artificial) is visible", "A tech object is visible next to it for scale"],
            photo: "Get both the plant and the tech object in the frame.",
            themes: [.explore, .creative], scopes: [.venue], difficulty: 2, points: 20, minutes: 10,
            safety: "Leave the plants where they are.",
            freePath: "Find a plant and use your own phone charger or laptop for scale."),
        MockQuestTemplate(
            title: "Colour Trio",
            description: "Find three things of the same colour within arm's reach and fit them all into one photo.",
            criteria: ["At least three objects are visible", "The objects share a similar colour"],
            photo: "Arrange the shot so all three objects are clearly visible. Use your own things.",
            themes: [.creative], scopes: [.venue, .nearby], difficulty: 2, points: 20, minutes: 10,
            safety: "Use your own belongings or things on public display.",
            freePath: "Use your own belongings or things you spot around you."),
        MockQuestTemplate(
            title: "Logo Hunter",
            description: "Find a sponsor or partner logo on a banner, stand or screen and photograph just the logo.",
            criteria: ["A company logo or banner is visible", "The logo is readable"],
            photo: "Frame the logo or banner so it's readable.",
            themes: [.social], scopes: [.venue], difficulty: 2, points: 20, minutes: 15,
            safety: "Don't interrupt demos at the stands.",
            freePath: "Look around the stands and photograph a logo."),

        // MARK: Nearby
        MockQuestTemplate(
            title: "Window Wonders",
            description: "Stroll over to {place} and find the most eye-catching thing in a window display nearby. Reflections welcome!",
            criteria: ["A shop window or display is visible", "One item stands out as the main subject"],
            photo: "Shoot through the glass at a slight angle to cut glare.",
            themes: [.explore, .creative], scopes: [.nearby], difficulty: 2, points: 20, minutes: 15,
            safety: "Stay on the pavement and don't block shop doorways.",
            freePath: "Window-gaze from the pavement — it's all free."),
        MockQuestTemplate(
            title: "Antique Hunter",
            description: "Find an antique or vintage shop window and spot a vase that looks at least 50 years old.",
            criteria: ["A vase is the main subject", "The vase looks old or vintage", "A label or price tag is visible"],
            photo: "Photograph the vase together with its label or price tag.",
            themes: [.history, .explore], scopes: [.nearby, .city], difficulty: 3, points: 30, minutes: 25,
            safety: "Look, don't touch — ask staff if you want a closer look.",
            freePath: "Photograph the vase from the window or shop floor.",
            optionalExtra: ("Optional: the shop may have a vintage postcard for about £2 if one catches your eye — but the vase photo is all you need.", 2)),
        MockQuestTemplate(
            title: "Bench Detective",
            description: "Find a bench with a memorial plaque or inscription and photograph the words.",
            criteria: ["A bench is visible", "A plaque or inscription is visible and mostly readable"],
            photo: "Get close enough that the inscription is readable.",
            themes: [.history, .explore], scopes: [.nearby], difficulty: 2, points: 20, minutes: 20,
            safety: "Stick to busy, well-lit streets.",
            freePath: "Walk around until you spot a bench with a plaque."),
        MockQuestTemplate(
            title: "Door Collector",
            description: "Find the most colourful front door within a few streets and photograph it straight on.",
            criteria: ["A door is the main subject", "The door is brightly coloured"],
            photo: "Stand on the pavement opposite and shoot it straight on.",
            themes: [.creative, .explore], scopes: [.nearby], difficulty: 1, points: 15, minutes: 15,
            safety: "Stay on public pavements and don't step onto doorsteps.",
            freePath: "Wander nearby streets and photograph a door from the pavement."),
        MockQuestTemplate(
            title: "Menu Poet",
            description: "Find a menu board outside {place} or another café and photograph the most unusual dish name on it.",
            criteria: ["A menu or menu board is visible", "Dish names are readable"],
            photo: "Shoot the board straight on so the words are sharp.",
            themes: [.food], scopes: [.nearby, .city], difficulty: 1, points: 15, minutes: 10,
            safety: "Don't block the entrance while you read.",
            freePath: "Read and photograph a menu board from the pavement.",
            optionalExtra: ("If the dish tempts you, you could buy it (around £4) — but the menu photo is all you need.", 4)),
        MockQuestTemplate(
            title: "Plaque Hunter",
            description: "Look for a blue plaque or historic marker on a building around {place} and photograph it so the text is readable.",
            criteria: ["A plaque or historic marker is visible", "The text on it is readable"],
            photo: "Zoom in a little so the plaque fills the frame.",
            themes: [.history], scopes: [.nearby, .city], difficulty: 3, points: 30, minutes: 25,
            safety: "Stay on the pavement and watch for traffic.",
            freePath: "Walk the streets around the area and look up!"),
        MockQuestTemplate(
            title: "Leaf Peeper",
            description: "Find a leaf, flower or tree near {place} with an unusual shape or colour and photograph it up close.",
            criteria: ["A leaf, flower or tree is the main subject", "The shape or colour is distinctive"],
            photo: "Get close and tap to focus on the plant.",
            themes: [.explore, .creative], scopes: [.nearby], difficulty: 1, points: 15, minutes: 15,
            safety: "Don't pick plants from gardens.",
            freePath: "Find a plant on a public street or square."),

        // MARK: City
        MockQuestTemplate(
            title: "Postcard Remix",
            description: "Head to {place} and recreate a classic postcard view — but from a surprising angle: low, high, or through something.",
            criteria: ["A landmark or notable building is visible", "The photo uses an unusual angle or framing"],
            photo: "Try crouching low or framing the landmark through an archway.",
            themes: [.creative, .explore], scopes: [.city], difficulty: 3, points: 30, minutes: 40,
            safety: "Stay aware of traffic and other people while framing your shot.",
            freePath: "Travel on foot or however you like, and photograph the view from a public spot."),
        MockQuestTemplate(
            title: "Market Rainbow",
            description: "Find a market stall or food display around {place} and photograph produce in at least three colours.",
            criteria: ["Food or produce is visible", "At least three distinct colours are visible"],
            photo: "Shoot from above or straight on.",
            themes: [.food, .creative], scopes: [.city], difficulty: 2, points: 25, minutes: 30,
            safety: "Ask the stallholder before taking photos up close.",
            freePath: "Admire and photograph a stall display — looking is free.",
            optionalExtra: ("You could also buy a piece of fruit from the rainbow (around £1), entirely optional.", 1)),
        MockQuestTemplate(
            title: "Clock Watcher",
            description: "Find a public clock in the city and photograph it so the time is readable.",
            criteria: ["A clock is visible", "The clock face is readable"],
            photo: "Zoom in so the clock face fills most of the frame.",
            themes: [.history, .explore], scopes: [.city], difficulty: 2, points: 20, minutes: 30,
            safety: "Stay on the pavement and look out for traffic.",
            freePath: "Look up at stations, churches and town halls."),
        MockQuestTemplate(
            title: "Street Art Safari",
            description: "Find a mural or piece of street art and photograph the most surprising detail in it.",
            criteria: ["A mural or street art is visible", "A specific detail is the focus of the photo"],
            photo: "Get close to one detail rather than the whole wall.",
            themes: [.creative], scopes: [.nearby, .city], difficulty: 2, points: 25, minutes: 25,
            safety: "Stick to busy streets and don't step onto the road.",
            freePath: "Explore public streets and squares to find art."),

        // MARK: Hard (difficulty 4-5)
        MockQuestTemplate(
            title: "Can Mountain",
            description: "Somewhere at {venue} there's a table drowning in drinks. Find one with at least 15 cans on it and capture the whole glorious mess in one shot.",
            criteria: ["At least 15 cans are visible", "The cans are all on the same table", "The whole table top fits in the frame"],
            photo: "Step back until every can is in frame. Count them before you shoot!",
            themes: [.explore, .food], scopes: [.venue], difficulty: 5, points: 50, minutes: 30,
            safety: "Don't move or take anyone's drinks.",
            freePath: "Walk the whole venue until you find the can-iest table."),
        MockQuestTemplate(
            title: "Sponsor Bingo",
            description: "Hunt down three different sponsor or partner logos around {venue} — banners, screens, stands or swag all count. One photo each.",
            criteria: ["3 different company logos appear across the photos", "Each logo is readable", "Each logo is on a banner, screen, stand or piece of swag"],
            photo: "Take one photo per logo, close enough that it's readable.",
            themes: [.explore, .social], scopes: [.venue], difficulty: 4, points: 40, minutes: 25,
            safety: "Stay out of stand areas that are closed off.",
            freePath: "Explore the stands and banners.",
            photoCount: 3),
        MockQuestTemplate(
            title: "Diagram Detective",
            description: "Hunt down a whiteboard or flipchart in a shared area with a proper architecture diagram: at least 5 boxes joined by arrows.",
            criteria: ["A whiteboard or flipchart is visible", "At least 5 boxes or shapes are drawn on it", "At least 4 arrows or lines connect them"],
            photo: "Shoot straight on so every box and arrow is readable.",
            themes: [.creative, .explore], scopes: [.venue], difficulty: 4, points: 40, minutes: 25,
            safety: "Only photograph boards in shared areas, not a team's private work.",
            freePath: "Check every room and corridor for a busy whiteboard."),
        MockQuestTemplate(
            title: "Power Strip Bingo",
            description: "Find a power strip where every single socket is in use — and it has at least 6 sockets.",
            criteria: ["A power strip is the main subject", "It has at least 6 sockets", "Every socket has a plug in it"],
            photo: "Get close enough that each socket and plug is clearly visible.",
            themes: [.explore], scopes: [.venue], difficulty: 4, points: 40, minutes: 20,
            safety: "Look, don't touch — never unplug anything.",
            freePath: "Check under the hacking tables."),
        MockQuestTemplate(
            title: "Door Rainbow",
            description: "Collect four front doors in four different colours: red, blue, green and yellow. One photo per door.",
            criteria: ["4 doors appear across the photos", "The doors are 4 different colours", "There is a red, a blue, a green and a yellow door"],
            photo: "Shoot each door straight on from the opposite pavement.",
            themes: [.creative, .explore], scopes: [.nearby], difficulty: 5, points: 50, minutes: 45,
            safety: "Stay on public pavements and watch for traffic.",
            freePath: "Wander residential streets.",
            photoCount: 4),
        MockQuestTemplate(
            title: "Clock Collector",
            description: "Find three different public clocks around the city — on a station, a church, a shopfront, anywhere. One photo per clock.",
            criteria: ["3 different clocks appear across the photos", "Each clock face is readable", "Each clock is on a building or street"],
            photo: "Zoom in so each clock face fills most of the frame.",
            themes: [.history, .explore], scopes: [.city], difficulty: 4, points: 45, minutes: 45,
            safety: "Look up from the pavement and watch for traffic.",
            freePath: "Look up at stations, churches and town halls as you go.",
            photoCount: 3),
        MockQuestTemplate(
            title: "Bike Rack Census",
            description: "Find a bike rack with at least 10 bikes locked to it, including at least one with a basket.",
            criteria: ["A bike rack is visible", "At least 10 bikes are locked to it", "At least one bike has a basket"],
            photo: "Shoot from the end of the rack so you can count every bike.",
            themes: [.explore], scopes: [.nearby, .city], difficulty: 4, points: 40, minutes: 30,
            safety: "Don't touch the bikes or block the pavement.",
            freePath: "Check outside stations, offices and libraries."),
        MockQuestTemplate(
            title: "Date Stone Hunter",
            description: "Find a building with a date carved or painted on it that's older than 1850, and photograph the date.",
            criteria: ["A date is carved or painted on a building", "The date is before 1850", "The digits are readable"],
            photo: "Zoom in until the date fills the frame.",
            themes: [.history], scopes: [.nearby, .city], difficulty: 5, points: 50, minutes: 45,
            safety: "Look up from the pavement — don't climb for a closer look.",
            freePath: "Walk the oldest streets and look up at the rooflines."),

        // MARK: Photo challenges (photographer mode)
        MockQuestTemplate(
            title: "Green Machine",
            description: "Find something green and get close enough that green fills at least half of your frame.",
            criteria: ["Something green is the main subject", "Green fills at least half of the frame"],
            photo: "Get close and tap to focus on the green.",
            themes: [.creative, .explore], scopes: [.venue, .nearby, .city], difficulty: 1, points: 15, minutes: 5,
            safety: "Watch where you're walking while you look for green.",
            freePath: "Look around you: plants, signs, bottles, clothes on display.", mode: .photo),
        MockQuestTemplate(
            title: "Circle Spotter",
            description: "Find at least three circles in a single scene: wheels, lights, clocks, plates, anything round.",
            criteria: ["At least 3 circles are visible", "The circles are the main subject"],
            photo: "Step back until all three circles sit in the frame.",
            themes: [.creative], scopes: [.venue, .nearby, .city], difficulty: 2, points: 20, minutes: 10,
            safety: "Stay out of the way of doors and walkways.",
            freePath: "Look for round things all around you.", mode: .photo),
        MockQuestTemplate(
            title: "Leading Lines",
            description: "Find lines that pull the eye into the picture (a railing, a corridor, a row of tables) and shoot along them towards something interesting.",
            criteria: ["Clear lines lead into the frame", "The lines point towards a subject"],
            photo: "Crouch a little and shoot along the lines, not across them.",
            themes: [.creative, .explore], scopes: [.venue, .nearby, .city], difficulty: 3, points: 30, minutes: 15,
            safety: "Stay on public paths and out of walkways while you line up the shot.",
            freePath: "Corridors, pavements and rows of seats all work.", mode: .photo),
        MockQuestTemplate(
            title: "Frame Within a Frame",
            description: "Shoot something through a doorway, window or arch so it frames your subject.",
            criteria: ["A doorway, window or arch frames the shot", "A clear subject sits inside the frame"],
            photo: "Step back until the doorway's edges surround your subject.",
            themes: [.creative], scopes: [.venue, .nearby, .city], difficulty: 3, points: 30, minutes: 15,
            safety: "Don't block doorways while you shoot.",
            freePath: "Any open doorway or window into a public space works.", mode: .photo),
        MockQuestTemplate(
            title: "Symmetry Hunt",
            description: "Find a perfectly symmetrical scene at {venue} (a corridor, a stage, a row of chairs) and shoot it dead centre.",
            criteria: ["The scene is symmetrical", "The camera is centred on the line of symmetry", "Both halves mirror each other"],
            photo: "Stand exactly in the middle and hold the phone level.",
            themes: [.creative, .explore], scopes: [.venue], difficulty: 4, points: 40, minutes: 20,
            safety: "Don't stand in walkways or on the stage.",
            freePath: "Walk the venue and look for mirrored layouts.", mode: .photo),
        MockQuestTemplate(
            title: "Double Exposure",
            description: "Find a shop window near {place} that reflects the street, and line up a shot where the reflection and what's behind the glass overlap.",
            criteria: ["A shop window fills most of the frame", "A reflection of the street is visible in the glass", "Something behind the glass shows through the reflection"],
            photo: "Shoot at a slight angle and move until both layers line up.",
            themes: [.creative, .explore], scopes: [.nearby, .city], difficulty: 4, points: 40, minutes: 20,
            safety: "Stay on the pavement and don't block the shop entrance.",
            freePath: "Any shop window works; looking is free.", mode: .photo),
        MockQuestTemplate(
            title: "Umbrella Street",
            description: "Street photography by {place}: get an umbrella into the frame (yours or one in the scene) and shoot from a low angle.",
            criteria: ["An umbrella is clearly visible", "The street or surroundings are recognisable", "The photo is taken from a low angle"],
            photo: "Crouch down and shoot upwards so the umbrella stands out against the sky.",
            themes: [.creative, .explore], scopes: [.nearby, .city], difficulty: 4, points: 45, minutes: 20,
            safety: "Stay on the pavement and keep an eye on traffic while you crouch.",
            freePath: "Use your own umbrella in the frame, or wait for one to pass.", mode: .photo, weather: .wet),
        MockQuestTemplate(
            title: "Puddle Mirror",
            description: "Find a puddle near {place} that reflects a building or sign, and shoot the reflection, not the real thing.",
            criteria: ["A reflection in water is the main subject", "A building, sign or light is reflected", "The real object is mostly out of frame"],
            photo: "Get your phone close to the puddle's edge and tilt until the reflection lines up.",
            themes: [.creative], scopes: [.nearby, .city], difficulty: 4, points: 45, minutes: 20,
            safety: "Keep to the pavement, away from the kerb.",
            freePath: "Any puddle on a pavement will do.", mode: .photo, weather: .wet),
        MockQuestTemplate(
            title: "Long Shadows",
            description: "Use the low sun near {place} to make a shadow the star of the shot: a long shadow stretching across the ground.",
            criteria: ["A long shadow is clearly visible", "The shadow is the main subject", "Strong, directional sunlight is visible"],
            photo: "Shoot with the sun to your side so the shadow stretches across the frame.",
            themes: [.creative, .explore], scopes: [.nearby, .city], difficulty: 4, points: 40, minutes: 20,
            safety: "Never look straight at the sun.",
            freePath: "Your own shadow counts.", mode: .photo, weather: .sunny),
        MockQuestTemplate(
            title: "Night Glow",
            description: "Find a lit sign or bright window near {place} and make its glow the whole story of the shot.",
            criteria: ["A lit sign or window is the main subject", "The light glows against a dark background", "The photo is sharp, not blurred"],
            photo: "Brace your phone against a wall or post to keep it steady.",
            themes: [.creative], scopes: [.nearby, .city], difficulty: 4, points: 40, minutes: 15,
            safety: "Stick to busy, well-lit streets.",
            freePath: "Shop signs and lit windows are everywhere after dark.", mode: .photo, weather: .dark),

        // MARK: People quests (only when people quests are on)
        MockQuestTemplate(
            title: "Monster Census",
            description: "Find someone who has already had 5 Monster energy drinks today. Ask if they're up for a photo of the evidence: their 5 empty cans with their thumbs up next to them.",
            criteria: ["At least 5 empty Monster cans are visible", "The cans are grouped together", "A hand giving a thumbs up is next to the cans"],
            photo: "Ask permission first, then frame the cans and their hand. Faces get blurred automatically.",
            themes: [.social, .food], scopes: [.venue], difficulty: 5, points: 50, minutes: 30,
            safety: "Keep it friendly — if someone isn't keen, move on.",
            freePath: "Chat your way around the tables until you find the champion.",
            involvesPeople: true),
        MockQuestTemplate(
            title: "Sticky Note Census",
            description: "Ask 5 hackers from different teams to write their favourite programming language on a sticky note, then line the notes up for one photo.",
            criteria: ["At least 5 sticky notes are visible", "Each note has a programming language written on it", "At least 3 different languages appear"],
            photo: "Stick the notes in a row on a wall or table and shoot them straight on. No names on the notes.",
            themes: [.social, .creative], scopes: [.venue], difficulty: 4, points: 45, minutes: 30,
            safety: "Ask nicely and don't interrupt anyone mid-demo.",
            freePath: "Borrow sticky notes from the supplies table.",
            involvesPeople: true),
        MockQuestTemplate(
            title: "Fist Bump Trio",
            description: "Get three people from three different teams to join you in a four-way fist bump, and photograph the fists meeting.",
            criteria: ["At least 4 fists are visible", "The fists are touching in the middle", "The fists belong to different people"],
            photo: "Ask everyone if they're okay with a hands-only photo, then shoot from above.",
            themes: [.social], scopes: [.venue], difficulty: 4, points: 40, minutes: 20,
            safety: "Keep it gentle and only with people who are happy to join in.",
            freePath: "Introduce yourself to a few teams near you.",
            involvesPeople: true),
        MockQuestTemplate(
            title: "Sticker Champion",
            description: "Find the laptop with the most stickers in the room — at least 20 — and ask its owner if you can photograph the lid.",
            criteria: ["A laptop lid is the main subject", "At least 20 stickers are on it", "The stickers cover most of the lid"],
            photo: "With the owner's permission, shoot the closed lid straight on.",
            themes: [.social, .creative], scopes: [.venue], difficulty: 4, points: 40, minutes: 25,
            safety: "Never touch someone's laptop — ask them to hold it up or close it themselves.",
            freePath: "Wander the hacking tables and compare stickers.",
            involvesPeople: true),
    ]
}
