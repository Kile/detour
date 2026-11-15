import Foundation

/// Enforces the money rules:
/// - `requires_purchase` must always be false (every quest is completable for free);
/// - money OFF: no mention of buying, paying, tickets, fees or anything that costs money, and a cost of 0;
/// - money ON: at most one optional purchase, never above the cap, with a real free path;
/// - never pressure the player to spend, and spending must never earn more points or be needed to pass.
enum MoneyRulesValidator {
    /// Anything that implies spending money. Not negation-aware: with money off, we don't even
    /// want "no need to buy anything".
    static let purchaseRules: [PhraseRule] = [
        PhraseRule("buy", #"\b(buy|buys|buying|bought)\b"#, message: "mentions buying", negationAware: false),
        PhraseRule("purchase", #"\bpurchas(e|es|ed|ing)\b"#, message: "mentions a purchase", negationAware: false),
        PhraseRule("pay", #"\b(pay|pays|paying)\b(?!\s+(attention|a visit|close attention|tribute|homage|respects?))"#,
                   message: "mentions paying", negationAware: false),
        PhraseRule("paid", #"\bpaid\b(?!\s+(attention|a visit|tribute|homage))"#, message: "mentions paying", negationAware: false),
        PhraseRule("ticket", #"\btickets?\b|\bticketed\b"#, message: "mentions tickets", negationAware: false),
        PhraseRule("fee", #"\bfees?\b|\b(entry|entrance|admission|cover)\s+(charge|price)s?\b"#,
                   message: "mentions a fee", negationAware: false),
        PhraseRule("currency", #"[£$€]\s?\d|\b\d+(\.\d+)?\s?(pence|pounds?|quid|dollars?|euros?)\b|\b\d+p\b"#,
                   message: "mentions an amount of money", negationAware: false),
        PhraseRule("money", #"\b(money|cash|contactless|card payment)\b"#, message: "mentions money", negationAware: false),
        PhraseRule("spend", #"\b(spend|spending|spent)\s+(money|cash|[£$€]|\d+\s?(p|pence|pounds?|quid))"#,
                   message: "mentions spending", negationAware: false),
        PhraseRule("cost", #"\bcosts?\s+(money|[£$€]|\d|a few|about|around|under|less)\b|\bfree of charge\b"#,
                   message: "mentions what something costs", negationAware: false),
        PhraseRule("order", #"\border\s+(a|an|one|some|your|yourself|something)\b"#, message: "mentions ordering", negationAware: false),
        PhraseRule("donate", #"\bdonat(e|es|ed|ing|ion|ions)\b"#, message: "mentions donating", negationAware: false),
        PhraseRule("receipt", #"\breceipts?\b|\btill\s+(slip|receipt)\b|\bcheckout\b"#, message: "mentions a receipt or checkout", negationAware: false),
        PhraseRule("rent", #"\b(rent|hire)\s+(a|an|one|some)\b"#, message: "mentions renting or hiring", negationAware: false),
        PhraseRule("grab", #"\bgrab\s+(a|an|some)\s+(coffee|drink|snack|bite|pastry|tea|treat|ice cream)\b"#,
                   message: "implies buying food or drink", negationAware: false),
        PhraseRule("treat", #"\btreat\s+yourself\b"#, message: "implies buying a treat", negationAware: false),
    ]

    /// Pressure to spend — forbidden in every mode.
    static let pressureRules: [PhraseRule] = [
        PhraseRule("must-buy", #"\b(must|need to|needs to|have to|has to|required to|should|be sure to|make sure to|don't forget to|you'll want to)\s+(buy|purchase|pay|spend|order|grab)\b"#,
                   message: "pressures the player to spend", negationAware: false),
        PhraseRule("treat-yourself", #"\btreat\s+yourself\b|\bsplurge\b|\bgo on\b.{0,20}\b(buy|get one|treat)\b|\bwhy not\b.{0,20}\b(buy|purchase|treat)\b"#,
                   message: "nudges the player to spend", negationAware: false),
        PhraseRule("fomo", #"\bdon't miss out\b|\blimited[- ]time\b|\bwhile stocks last\b|\bworth (every penny|the money|the price)\b|\b(only|just)\s+[£$€]\s?\d"#,
                   message: "uses sales pressure", negationAware: false),
        PhraseRule("support-by-buying", #"\bsupport\b.{0,30}\bby\s+(buying|purchasing|spending)\b"#,
                   message: "guilt-trips the player into spending", negationAware: false),
        PhraseRule("pay-to-win", #"\b(bonus|extra|more|double|additional)\s+(points?|xp)\b.{0,60}\b(buy|bought|purchas\w*|pay|paid|spend\w*)\b|\b(buy|bought|purchas\w*|pay|paid|spend\w*)\b.{0,60}\b(bonus|extra|more|double|additional)\s+(points?|xp)\b"#,
                   message: "rewards spending with extra points (no pay-to-win)", negationAware: false),
    ]

    static func validate(_ quest: Quest, settings: MoneySettings) -> [QuestViolation] {
        var violations: [QuestViolation] = []
        func add(_ message: String) { violations.append(QuestViolation(rule: .money, message: message)) }

        if quest.requiresPurchase {
            add("requires_purchase must be false — every quest must be completable for free")
        }
        if !quest.optionalCostEstimate.isFinite || quest.optionalCostEstimate < 0 {
            add("optional_cost_estimate must be 0 or more")
        }
        if quest.freePath.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
            add("free_path is missing — explain how to complete the quest without spending anything")
        }

        let fields: [(name: String, text: String)] = [
            ("title", quest.title), ("description", quest.description),
            ("photo_instructions", quest.photoInstructions), ("free_path", quest.freePath),
            ("safety_notes", quest.safetyNotes), ("target_place", quest.targetPlace),
        ] + quest.successCriteria.map { ("success_criteria", $0) }

        // Pressure is never allowed.
        for field in fields {
            for rule in pressureRules {
                if let hit = rule.firstViolation(in: field.text) {
                    add("\(field.name) \(rule.message) (\"\(hit)\")")
                }
            }
        }

        if !settings.enabled {
            if quest.optionalCostEstimate != 0 {
                add("optional_cost_estimate must be 0 because money is turned off")
            }
            for field in fields {
                if let (rule, hit) = firstPurchaseMention(in: field.text) {
                    add("\(field.name) \(rule.message) (\"\(hit)\") but money is turned off — do not mention money at all")
                }
            }
        } else {
            let cap = settings.effectiveCap
            if quest.optionalCostEstimate > cap + 0.001 {
                add(String(format: "optional_cost_estimate £%.2f is above the £%.0f limit", quest.optionalCostEstimate, cap))
            }
            // The free path must itself be free.
            if let (rule, hit) = firstPurchaseMention(in: quest.freePath) {
                add("free_path \(rule.message) (\"\(hit)\") — the free path must not involve spending")
            }
            // Passing must never depend on buying something.
            for criterion in quest.successCriteria {
                if let (rule, hit) = firstPurchaseMention(in: criterion) {
                    add("success_criteria \(rule.message) (\"\(hit)\") — criteria must be achievable on the free path")
                }
            }
            // Any amount stated in the text must respect the cap.
            for amount in statedAmounts(in: quest.allText.joined(separator: " ")) where amount > cap + 0.001 {
                add(String(format: "mentions £%.2f which is above the £%.0f limit", amount, cap))
            }
            // If the quest talks about buying, the estimate must be declared so the cap can be checked.
            let mentionsPurchase = [quest.title, quest.description, quest.photoInstructions]
                .contains { firstPurchaseMention(in: $0) != nil }
            if mentionsPurchase && quest.optionalCostEstimate == 0 && cap > 0 {
                add("mentions an optional purchase but optional_cost_estimate is 0 — give an estimate")
            }
            if mentionsPurchase && cap == 0 {
                add("mentions a purchase but the spending limit is £0")
            }
        }
        return violations
    }

    static func firstPurchaseMention(in text: String) -> (PhraseRule, String)? {
        for rule in purchaseRules {
            if let hit = rule.firstViolation(in: text) { return (rule, hit) }
        }
        return nil
    }

    private static let amountRegex = try! NSRegularExpression(
        pattern: #"[£$€]\s?(\d+(?:\.\d{1,2})?)|\b(\d+(?:\.\d{1,2})?)\s?(?:pounds?|quid)\b"#, options: [.caseInsensitive])

    /// Amounts in pounds mentioned in the text (e.g. "£3.50", "4 quid").
    static func statedAmounts(in text: String) -> [Double] {
        let range = NSRange(text.startIndex..., in: text)
        return amountRegex.matches(in: text, range: range).compactMap { match in
            for group in 1...2 {
                if let r = Range(match.range(at: group), in: text), let value = Double(text[r]) { return value }
            }
            return nil
        }
    }
}
