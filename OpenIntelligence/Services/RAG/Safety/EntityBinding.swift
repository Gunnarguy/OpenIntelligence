//
//  EntityBinding.swift
//  OpenIntelligence
//

import Foundation

/// Whether a value an answer states is bound, in the passages, to the thing the answer says it belongs to (5.8).
///
/// A value used to count as supported wherever its digits appeared in a passage. On the owner's iPhone on 2026-11-18
/// "What is the similarity floor in Standard mode?" was answered "The similarity floor in Standard mode is 0.20 [S2]."
/// and Fact Check marked it Supported at 90%: the cited passage is the guide's "Quality modes" list, one item per mode,
/// and 0.20 is in the Maximum item; Standard's item says 0.28. The same shape happens in any passage that lists several
/// things with one attribute each: a list of plans and prices, of models and sizes, of sections and their rules.
///
/// A passage is read as units, each with a label naming what it is about:
/// - a list item or a line that starts with a bold lead or a short "Name:" lead, the lead labelling the whole item
///   ("- **Maximum.** ... 50 candidates per step, a similarity floor of 0.20 ...");
/// - any other line under a Markdown heading, labelled by that heading ("## Pro plan", then "It costs $9.99.");
/// - an unlabelled sentence, which names whatever its own words name.
/// Table rows are units too, but whether a value sits in the asked row is `VerificationGateService.valuesFromOtherRows`'s
/// call (5.8, the DHA row), so a value a table row holds is left to it.
///
/// The names that tell the units apart are the label words not shared by every label. The claim's subject is the labels
/// it names, together with those the question names when the claim is about what was asked (see `placements`). A value
/// is bound elsewhere when every unit holding it that is about the claim's attribute is labelled with another subject of
/// the same kind (another item of the list, another section at the same level, another "Name:" line), while a unit
/// labelled with the claim's subject is in the passages. A value also held by a unit about the subject, by a unit of
/// another kind ("**Note:** ...", a line under the list's heading), or by a sentence that names no subject at all, is
/// left alone, so a passage that could be read either way never marks a claim down. Known gaps: a value stated by
/// reference ("**Deep Think.** Same floor as Standard") reads as Standard's, and a "Name:" list under per-subject
/// headings ("## Standard mode", "- Similarity floor: 0.28") is read by its items, not by its headings.
nonisolated enum EntityBinding {
    /// How a unit is labelled. A value is given to another subject only by a unit labelled the way the subject's own is.
    enum Kind: Hashable, Sendable {
        /// A list item with a lead ("- **Maximum.** ...").
        case itemLead
        /// A line with a lead, not in a list ("Coolant: 6.2 L").
        case lineLead
        /// A line under a heading of this level; 7 for a bold line or a "Name:" line that stands alone.
        case heading(Int)
        /// No label.
        case unlabelled
        /// A table row.
        case tableRow
    }

    struct Unit: Equatable, Sendable {
        /// The unit's text: a whole list item, a line or a sentence.
        let text: String
        /// What it is about: its lead's words, or its heading's; empty for an unlabelled sentence.
        let label: Set<String>
        /// Its label as written, for a verdict's explanation.
        let labelText: String
        let kind: Kind
        /// An unlabelled unit before any label in its passage: the passage starts inside something, whose name is in the
        /// passage before it ("Each step retrieves 35 candidates ...", the rest of Deep Think's item, then "- **Maximum.**").
        var isOrphan = false

        var isTableRow: Bool { kind == .tableRow }
        var labelIsHeading: Bool { if case .heading = kind { true } else { false } }
    }

    /// A value bound to another subject than the claim's, and that subject as the passage writes it.
    struct Misplaced: Equatable, Sendable {
        let value: String
        let owner: String
    }

    /// Words that name nothing, which a label or a claim can hold ("Generate and verify").
    private static let functionWords: Set<String> = [
        "and", "the", "for", "with", "that", "this", "from", "are", "was", "were", "its", "into", "than", "then",
        "not", "but", "you", "your", "our", "their", "all", "any", "each", "how", "what", "which", "who", "why",
        "when", "where", "has", "have", "can", "may", "will", "per", "also", "only", "about",
    ]

    /// Leads that mark a remark rather than name a subject ("**Note:** the default floor is 0.28 ..."): a line with one
    /// is read as if it had no lead.
    private static let remarkLeads: Set<String> = [
        "note", "notes", "tip", "tips", "example", "examples", "default", "defaults", "summary", "important", "warning",
        "caution", "overview", "info", "update", "result", "results", "takeaway", "aside", "see", "remember", "hint",
    ]

    private static let listMarker = #"^\s*(?:[-*•–]|\d{1,3}[.)])\s+"#
    private static let boldLead = #"^\*\*([^*\n]{1,60})\*\*"#
    private static let colonLead = #"^([^:.|\n]{1,40}):(?:\s|$)"#
    private static let heading = #"^(#{1,6})\s+(.+)$"#

    /// The units of one passage, in order.
    static func units(in passage: String) -> [Unit] {
        var result: [Unit] = []
        var headingLabel: (words: Set<String>, text: String, level: Int)?
        var seenLabel = false
        for line in EvidenceLineSplitter.lines(in: passage) {
            if let match = line.range(of: heading, options: .regularExpression) {
                let marks = line.prefix { $0 == "#" }.count
                let title = String(line[match]).replacingOccurrences(
                    of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\d{1,3}[.)]\s*"#, with: "", options: .regularExpression)
                headingLabel = (RAGService.lookupWords(in: title), title, marks)
                seenLabel = true
                continue
            }
            if line.range(of: #"^ROW \d+:"#, options: .regularExpression) != nil || line.contains(" | ") {
                let body = line.replacingOccurrences(of: #"^ROW \d+:\s*"#, with: "", options: .regularExpression)
                let first = body.components(separatedBy: " | ").first ?? body
                result.append(Unit(text: line, label: RAGService.lookupWords(in: first), labelText: first, kind: .tableRow))
                seenLabel = true
                continue
            }
            let isItem = line.range(of: listMarker, options: .regularExpression) != nil
            let body = line.replacingOccurrences(of: listMarker, with: "", options: .regularExpression)
            if let lead = self.lead(of: body) {
                seenLabel = true
                // A bold line or a "Name:" line with nothing after it names what follows, as a heading does.
                let rest = body.replacingOccurrences(of: #"^\*\*[^*\n]*\*\*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^[^:.|\n]{1,40}:"#, with: "", options: .regularExpression)
                if !isItem, rest.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces)).isEmpty {
                    headingLabel = (RAGService.lookupWords(in: lead), lead, 7)
                    continue
                }
                result.append(
                    Unit(
                        text: line, label: RAGService.lookupWords(in: lead), labelText: lead,
                        kind: isItem ? .itemLead : .lineLead))
                continue
            }
            if let headingLabel, !headingLabel.words.isEmpty {
                result.append(
                    Unit(
                        text: line, label: headingLabel.words, labelText: headingLabel.text,
                        kind: .heading(headingLabel.level)))
                continue
            }
            // An unlabelled list item is one unit; an unlabelled paragraph line is its sentences.
            for sentence in isItem ? [line] : EvidenceLineSplitter.units(in: line) {
                result.append(Unit(text: sentence, label: [], labelText: "", kind: .unlabelled, isOrphan: !seenLabel))
            }
        }
        return result
    }

    /// A line's lead: its bold opening ("**Maximum.**", "**Pro plan:**") or a short name before a colon
    /// ("Standard: 30 candidates"), without its closing mark. Nil when it has none, when the lead has no word, or when
    /// it marks a remark ("Note:").
    static func lead(of body: String) -> String? {
        var lead: String?
        if let range = body.range(of: boldLead, options: .regularExpression) {
            lead = String(body[range]).replacingOccurrences(of: "**", with: "")
        } else if let range = body.range(of: colonLead, options: .regularExpression) {
            lead = String(body[range]).trimmingCharacters(in: .whitespaces)
        }
        // A sentence in bold, or a clause before a colon, is not a name: at most five words ("Source cards and
        // citations"), where "**It runs on your device, and asks before it ever leaves.**" is a point being made.
        guard let trimmed = lead?.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces)),
            trimmed.split(separator: " ").count <= 5
        else { return nil }
        let words = RAGService.lookupWords(in: trimmed)
        guard !words.isEmpty, !words.isSubset(of: remarkLeads) else { return nil }
        return trimmed
    }

    /// Where one of a claim's values sits in the passages.
    enum Placement: Equatable, Sendable {
        /// In a unit about the claim's subject, labelled as written.
        case withSubject(String)
        /// Only in units about another subject, the first of them labelled as written.
        case elsewhere(String)
        /// In the passages, where nothing says whose it is, or the passages name no subjects to tell apart.
        case unattributed
        /// Not in the passages.
        case absent
    }

    /// Letters and digits only, lowercased, for finding one passage's text inside another's.
    private static func folded(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// The passages read once, for every claim checked against them.
    struct Reading: Sendable {
        /// Each passage's units, an orphan read as the labelled unit of another passage that holds its text.
        let units: [[Unit]]
        /// Each passage's names: the label words not shared by every label of that passage (a passage with one label
        /// has all its words), less function words. "mode" in "Standard mode" and "Maximum mode" names neither.
        let names: [Set<String>]
        /// The units with a number in them, by passage, and their numbers as evidence.
        let numbered: [(passage: Int, unit: Unit)]
        let evidence: [NumericValueExtractor.Evidence]
        /// The passages' numbers, whole, for a value no unit holds (a line of three characters or fewer is not a unit).
        let wholeEvidence: [NumericValueExtractor.Evidence]

        init(passages: [String]) {
            var byPassage = passages.map(EntityBinding.units(in:))
            // An orphan found inside a labelled unit of another passage (overlapping passages) takes that unit's label.
            let labelledTexts = byPassage.joined().filter { !$0.label.isEmpty && !$0.isTableRow }
                .map { (unit: $0, folded: EntityBinding.folded($0.text)) }
            for index in byPassage.indices {
                byPassage[index] = byPassage[index].map { unit in
                    guard unit.isOrphan else { return unit }
                    let text = EntityBinding.folded(unit.text)
                    guard text.count >= 20, let home = labelledTexts.first(where: { $0.folded.contains(text) })?.unit
                    else { return unit }
                    return Unit(text: unit.text, label: home.label, labelText: home.labelText, kind: home.kind)
                }
            }
            units = byPassage
            names = byPassage.map { units in
                let distinct = Set(units.filter { !$0.label.isEmpty && !$0.isTableRow }.map(\.label))
                guard !distinct.isEmpty else { return [] }
                var count: [String: Int] = [:]
                for label in distinct { for word in label { count[word, default: 0] += 1 } }
                return Set(count.filter { distinct.count == 1 || $0.value < distinct.count }.keys)
                    .subtracting(EntityBinding.functionWords)
            }
            numbered = byPassage.enumerated().flatMap { index, units in
                units.filter { $0.text.contains(where: \.isNumber) }.map { (passage: index, unit: $0) }
            }
            evidence = NumericValueExtractor.evidence(from: numbered.map(\.unit.text))
            wholeEvidence = NumericValueExtractor.evidence(from: passages)
        }

        /// The subject `text` names among the labels of the passages at `indices`: the name words of every label it
        /// names, an item's or a line's lead before a heading (`leads`). A label is named when the text holds all its
        /// name words, or, for a label of three or more, more than half of them: "Under each answer" is not named by
        /// "a hypothetical answer", and "Deep Think" is not named by "think".
        func subject(namedBy text: String, in indices: [Int], leads: Bool) -> Set<String> {
            let words = RAGService.lookupWords(in: text)
            var subject = Set<String>()
            for index in indices {
                for unit in units[index] where !unit.isTableRow && !unit.label.isEmpty && unit.labelIsHeading != leads {
                    let name = unit.label.intersection(names[index])
                    let held = name.intersection(words)
                    guard !held.isEmpty else { continue }
                    if held.count == name.count || (name.count >= 3 && held.count * 2 > name.count) {
                        subject.formUnion(held)
                    }
                }
            }
            return subject
        }
    }

    /// What a text says about its subject: its words less the subject's, function words and the words any value
    /// question uses (`RAGService.genericValueWords`).
    private static func attribute(of text: String, less subject: Set<String>) -> Set<String> {
        RAGService.lookupWords(in: text).subtracting(subject).subtracting(functionWords)
            .subtracting(RAGService.genericValueWords)
    }

    /// Where each of `values` sits in `passages`, for a claim answering `question`.
    static func placements(
        claim: String, question: String, values: [NumericValueExtractor.Mention], passages: [String]
    ) -> [(value: String, placement: Placement)] {
        placements(claim: claim, question: question, values: values, in: Reading(passages: passages))
    }

    /// Where each of `values` sits in the passages `reading` read.
    ///
    /// The subject is the labels the claim names, together with those the question names when the claim is about what
    /// was asked: it states nothing else about its subject ("It is 0.20."), or shares a word of the question's
    /// attribute. "This threshold is part of the same loop structure as Deep Think and Standard, but with a wider net
    /// of 50 candidates per step", answering "What is the verification confidence threshold in Maximum mode?", is about
    /// Maximum, and 50 is Maximum's; "Every mode then reranks the top 10", answering "How many candidates does Standard
    /// retrieve?", is not about Standard. Labels are read from the passages that hold the value first, item leads
    /// before headings: passages elsewhere in the library have leads of their own, and "**Retrieves candidate
    /// passages**" in another guide would make "candidate" a subject.
    static func placements(
        claim: String, question: String, values: [NumericValueExtractor.Mention], in reading: Reading
    ) -> [(value: String, placement: Placement)] {
        let plain = values.filter { $0.identifier == nil }
        guard !plain.isEmpty else { return [] }
        let all = Array(reading.units.indices)

        return plain.map { value in
            let found = zip(reading.numbered, reading.evidence)
                .filter { NumericValueExtractor.isSupported(value, by: [$1]) }.map(\.0)
            guard !found.isEmpty else {
                let anywhere = NumericValueExtractor.isSupported(value, by: reading.wholeEvidence)
                return (value.written, anywhere ? .unattributed : .absent)
            }
            // A table row's value is `VerificationGateService.valuesFromOtherRows`'s call.
            guard !found.contains(where: \.unit.isTableRow) else { return (value.written, .unattributed) }

            var indices: [Int] = []
            for entry in found where !indices.contains(entry.passage) { indices.append(entry.passage) }
            var subject = Set<String>()
            search: for scope in [indices, all] {
                for leads in [true, false] {
                    let claimNames = reading.subject(namedBy: claim, in: scope, leads: leads)
                    let questionNames = reading.subject(namedBy: question, in: scope, leads: leads)
                    let claimAttribute = attribute(of: claim, less: claimNames.union(questionNames))
                    let aboutQuestion = claimAttribute.isEmpty
                        || !claimAttribute.isDisjoint(with: attribute(of: question, less: questionNames))
                    subject = aboutQuestion ? claimNames.union(questionNames) : claimNames
                    if !subject.isEmpty { break search }
                }
            }
            // A subject with no item or section of its own in the passages has nothing to compare with.
            let ownKinds = Set(
                reading.units.joined().filter { !$0.isTableRow && !$0.label.isDisjoint(with: subject) }.map(\.kind))
            guard !subject.isEmpty, !ownKinds.isEmpty else { return (value.written, .unattributed) }

            // Only a unit about what the claim says of its subject holds its value: "up to 8 query variants" is not
            // in "a file over 8 MB". The claim's attribute, or the question's when the claim has none ("It is 0.20.").
            var about = attribute(of: claim, less: subject)
            if about.isEmpty { about = attribute(of: question, less: subject) }
            let held = about.isEmpty
                ? found
                : found.filter { !RAGService.lookupWords(in: $0.unit.text).union($0.unit.label).isDisjoint(with: about) }
            guard !held.isEmpty else { return (value.written, .unattributed) }

            if let own = held.first(where: { !$0.unit.label.isDisjoint(with: subject) }) {
                return (value.written, .withSubject(own.unit.labelText))
            }
            let ambiguous = held.contains { entry in
                let unit = entry.unit
                let named = RAGService.lookupWords(in: unit.text)
                if !named.isDisjoint(with: subject) { return true }
                // Labelled another way than the subject's own unit: a line under the list's heading.
                if !unit.label.isEmpty { return !ownKinds.contains(unit.kind) }
                // An unlabelled sentence is anyone's ("**Note:** the default floor is 0.28 in every mode but Maximum"),
                // except at the start of a passage: that belongs to what the passage before it names, so not to a
                // subject whose own item comes after it in this passage.
                return !(unit.isOrphan
                    && reading.units[entry.passage].contains(where: { !$0.isTableRow && !$0.label.isDisjoint(with: subject) }))
            }
            if ambiguous { return (value.written, .unattributed) }
            let owner = held.first(where: { !$0.unit.label.isEmpty })?.unit ?? held[0].unit
            return (value.written, .elsewhere(owner.labelText.isEmpty ? owner.text : owner.labelText))
        }
    }

    /// The values of `claim` that the passages bind to another subject than the claim's (see the type's comment).
    static func misplacedValues(
        claim: String, question: String, values: [NumericValueExtractor.Mention], passages: [String]
    ) -> [Misplaced] {
        misplacedValues(claim: claim, question: question, values: values, in: Reading(passages: passages))
    }

    static func misplacedValues(
        claim: String, question: String, values: [NumericValueExtractor.Mention], in reading: Reading
    ) -> [Misplaced] {
        placements(claim: claim, question: question, values: values, in: reading).compactMap { entry in
            guard case .elsewhere(let owner) = entry.placement else { return nil }
            return Misplaced(value: entry.value, owner: owner)
        }
    }

    /// What a cited passage says about the values of the answer sentences that cite it, for the line under "Passage
    /// found word for word in this document." (5.8). That line is about the passage: on 2026-11-18 it showed for "The
    /// similarity floor in Standard mode is 0.20 [S2]", whose passage gives 0.20 for Maximum. Nil when no sentence
    /// states a value. A warning first, whichever sentence it comes from.
    static func citationNote(claims: [String], passage: String) -> (text: String, isWarning: Bool)? {
        let reading = Reading(passages: [passage])
        let notes = claims.compactMap { citationNote(claim: $0, in: reading) }
        return notes.first { $0.isWarning } ?? notes.first
    }

    static func citationNote(claim: String, passage: String) -> (text: String, isWarning: Bool)? {
        citationNote(claim: claim, in: Reading(passages: [passage]))
    }

    private static func citationNote(claim: String, in reading: Reading) -> (text: String, isWarning: Bool)? {
        let values = NumericValueExtractor.mentions(inAnswer: claim).filter(NumericValueExtractor.isCountedByGate)
        let placed = placements(claim: claim, question: "", values: values, in: reading)
        guard !placed.isEmpty else { return nil }
        for entry in placed {
            if case .elsewhere(let owner) = entry.placement {
                return ("The answer's \(entry.value) is this passage's value for \(owner), not for what the answer says.", true)
            }
        }
        if let absent = placed.first(where: { $0.placement == .absent }) {
            return ("The answer's \(absent.value) is not in this passage.", true)
        }
        let owners = placed.compactMap { entry -> String? in
            if case .withSubject(let owner) = entry.placement { return owner }
            return nil
        }
        let written = placed.map(\.value).joined(separator: ", ")
        if owners.count == placed.count {
            if placed.count == 1 { return ("The answer's \(written) is stated here for \(owners[0]).", false) }
            let pairs = zip(placed, owners).map { "\($0.value) for \($1)" }.joined(separator: ", ")
            return ("The answer's values are stated here: \(pairs).", false)
        }
        return ("The answer's \(written) is in this passage.", false)
    }
}
