//
//  GlossaryTests.swift
//  OpenIntelligenceTests
//
//  Keeps the two registers of every definition actually distinct, and keeps the plain one
//  plain.
//
//  Why this needs a test at all. The glossary exists because unexplained jargon on the
//  onboarding completion card risks losing the user it was built to convince. The failure
//  mode is not a crash. It is a plain definition slowly acquiring mechanism until it reads
//  like the technical one, at which point the app has two technical registers and no plain
//  one, and nobody notices because both still render. `testPlainRegisterStaysPlain` is the
//  guard: it fails the suite when a code identifier, model name or framework name appears
//  in the register written for someone who has met none of them.
//

@testable import OpenIntelligence
import XCTest

final class GlossaryTests: XCTestCase {
    // MARK: - Completeness

    /// Both registers exist for every term, and neither is a copy of the other.
    ///
    /// The switch in `GlossaryTermID.definition` is exhaustive, so the compiler already
    /// guarantees a term cannot be missing. What it cannot guarantee is that both strings
    /// were actually written, which is what a placeholder or a copy-paste leaves behind.
    func testEveryTermDefinesBothRegisters() {
        for term in Glossary.all {
            XCTAssertFalse(
                term.plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(term.id.rawValue) has no plain definition"
            )
            XCTAssertFalse(
                term.technical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(term.id.rawValue) has no technical definition"
            )
            XCTAssertNotEqual(
                term.plain, term.technical,
                "\(term.id.rawValue) uses the same text for both registers, which defeats having two"
            )
            XCTAssertFalse(
                term.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(term.id.rawValue) has no display name"
            )
            XCTAssertFalse(
                term.icon.isEmpty,
                "\(term.id.rawValue) has no icon, so its rows will render a blank column"
            )
        }

        XCTAssertEqual(
            Glossary.all.count, GlossaryTermID.allCases.count,
            "The registry dropped a term between the enum and Glossary.all"
        )
    }

    /// No two terms share a display name, which would make the glossary list ambiguous.
    func testDisplayNamesAreUnique() {
        let names = Glossary.all.map(\.term)
        XCTAssertEqual(
            Set(names).count, names.count,
            "Two terms share a display name: \(names.sorted())"
        )
    }

    /// Every section has at least one term, so no empty header can ship.
    func testEverySectionHasTerms() {
        for section in GlossarySection.allCases {
            XCTAssertFalse(
                Glossary.terms(in: section).isEmpty,
                "Section \(section.rawValue) renders a header with nothing under it"
            )
        }

        let sectioned = GlossarySection.allCases.flatMap { Glossary.terms(in: $0) }
        XCTAssertEqual(
            sectioned.count, Glossary.all.count,
            "A term belongs to no section and would never appear on the glossary screen"
        )
    }

    // MARK: - The plain register stays plain

    /// Vocabulary that belongs to the technical register and nowhere near the plain one.
    ///
    /// Deliberately identifiers, model names and framework names rather than concepts.
    /// Checking for concepts would fire on ordinary English: `hybridSearch` legitimately
    /// says "exact words find" in its plain register, and "words" happens to also be a
    /// defined term. Identifiers have no such ambiguity, and they are the actual thing
    /// that leaks when someone edits a plain definition while looking at code.
    private static let technicalOnlyVocabulary = [
        "MiniLM", "TinyBERT", "BM25", "FTS5", "vDSP", "BNNS", "HNSW", "RRF",
        "CoreML", "Core ML", "PDFKit", "ProcessInfo", "mlpackage", "TN3193",
        "cosine", "cross-encoder", "reciprocal rank", "dimensions", "tokenizer",
        "SQLite", "Metal", "threadgroup", "concurrency", "amortise", "amortize",
    ]

    func testPlainRegisterStaysPlain() {
        for term in Glossary.all {
            for jargon in Self.technicalOnlyVocabulary {
                XCTAssertFalse(
                    term.plain.localizedCaseInsensitiveContains(jargon),
                    "The plain definition of \(term.id.rawValue) contains \"\(jargon)\". That belongs in the technical register."
                )
            }

            XCTAssertFalse(
                term.plain.contains("`"),
                "The plain definition of \(term.id.rawValue) uses code voice. Backticks belong in the technical register."
            )
        }
    }

    /// The plain register stays short enough to read on a phone without scrolling.
    ///
    /// Not a style preference. These render inside a sheet at `.medium` detent and in
    /// two-line list rows, and a plain definition that overflows both is one a user
    /// abandons, which is the same outcome as not having written it.
    func testPlainRegisterStaysScannable() {
        for term in Glossary.all {
            XCTAssertLessThanOrEqual(
                term.plain.count, 360,
                "The plain definition of \(term.id.rawValue) is \(term.plain.count) characters. Cut it or move detail to the technical register."
            )
        }
    }

    // MARK: - Standing product rules

    /// No em-dashes, anywhere a user can read.
    ///
    /// A standing rule in this repository rather than a preference, and this file is
    /// user-facing copy in the same sense `USER_CHANGELOG.md` became once it started
    /// rendering in the app.
    func testNoEmDashesInAnyDefinition() {
        let forbidden: [Character] = ["\u{2014}", "\u{2015}"]

        for term in Glossary.all {
            for text in [term.term, term.plain, term.technical] {
                for character in forbidden where text.contains(character) {
                    XCTFail("\(term.id.rawValue) contains an em-dash: \(text)")
                }
            }
        }

        for section in GlossarySection.allCases {
            for character in forbidden where section.title.contains(character) {
                XCTFail("Section \(section.rawValue) title contains an em-dash")
            }
        }
    }

    // MARK: - Cross-references

    /// Related terms point somewhere real and never at themselves.
    ///
    /// `seeAlso` is typed as `[GlossaryTermID]`, so a reference cannot dangle the way a
    /// string key could. What is still possible is a term listing itself, which renders a
    /// row that navigates to the screen it is already on.
    func testRelatedTermsAreUsable() {
        for term in Glossary.all {
            XCTAssertFalse(
                term.seeAlso.contains(term.id),
                "\(term.id.rawValue) lists itself as a related term"
            )
            XCTAssertEqual(
                Set(term.seeAlso).count, term.seeAlso.count,
                "\(term.id.rawValue) lists the same related term twice"
            )
        }
    }

    /// Every term is reachable from at least one other term, or from a section.
    ///
    /// Sections make every term reachable by browsing, so this is a softer check than it
    /// looks: it exists to catch a term that was added to the enum and then never linked
    /// from the definitions it actually relates to.
    func testNoTermIsOrphanedFromTheGraph() {
        let referenced = Set(Glossary.all.flatMap(\.seeAlso))
        let unreferenced = GlossaryTermID.allCases.filter { !referenced.contains($0) }

        XCTAssertTrue(
            unreferenced.isEmpty,
            "These terms are never listed as related to anything, so nothing links to them: \(unreferenced.map(\.rawValue))"
        )
    }

    // MARK: - Search

    /// A term is findable by its own name.
    func testSearchFindsEveryTermByName() {
        for term in Glossary.all {
            let hits = Glossary.search(term.term)
            XCTAssertTrue(
                hits.contains(where: { $0.id == term.id }),
                "Searching \"\(term.term)\" does not return \(term.id.rawValue)"
            )
        }
    }

    /// Every synonym finds the term it was written for.
    ///
    /// Synonyms exist because the label on screen and the word in someone's head are often
    /// different: the completion card says "32/batch" and a user searches "batch". A
    /// synonym that matches nothing is dead weight that reads as coverage.
    func testEverySynonymFindsItsTerm() {
        for term in Glossary.all {
            for synonym in term.synonyms {
                let hits = Glossary.search(synonym)
                XCTAssertTrue(
                    hits.contains(where: { $0.id == term.id }),
                    "Synonym \"\(synonym)\" does not return \(term.id.rawValue)"
                )
            }
        }
    }

    /// An empty query returns everything rather than nothing.
    func testEmptySearchReturnsEveryTerm() {
        XCTAssertEqual(Glossary.search("").count, Glossary.all.count)
        XCTAssertEqual(Glossary.search("   ").count, Glossary.all.count)
    }

    /// Searching the word the code uses finds the term, even though the plain register
    /// avoids it. This is the payoff of indexing the technical register too.
    func testSearchReachesTechnicalVocabulary() {
        for (needle, expected) in [
            ("bm25", GlossaryTermID.hybridSearch),
            ("vdsp", .searchBatch),
            ("minilm", .vector),
            ("tinybert", .reranking),
            ("fts5", .index),
        ] {
            let hits = Glossary.search(needle)
            XCTAssertTrue(
                hits.contains(where: { $0.id == expected }),
                "Searching \"\(needle)\" should reach \(expected.rawValue)"
            )
        }
    }

    // MARK: - Honesty about what the app cannot measure

    /// The TOPS definition must keep saying it is a lookup rather than a measurement.
    ///
    /// `DeviceCapabilityService.npuTops` reads a per-chip table keyed by device identifier,
    /// and several entries are explicitly projections for unreleased silicon. Apple exposes
    /// no live Neural Engine occupancy API. This repository has already withdrawn a `65
    /// tok/s` figure and three invented multipliers that read as measurements, so the
    /// hedge here is load-bearing and a test is cheaper than finding out it was edited out.
    func testTopsDefinitionDoesNotClaimAMeasurement() {
        let technical = GlossaryTermID.tops.definition.technical

        XCTAssertTrue(
            technical.localizedCaseInsensitiveContains("not measured")
                || technical.localizedCaseInsensitiveContains("looked up"),
            "The TOPS definition must state that the figure is a per-chip lookup, not a measurement taken on this device."
        )
    }

    /// The Neural Engine definition must keep Core ML's scheduling hedge.
    ///
    /// The app expresses a preference through `preferredComputeUnits`; Core ML decides. The
    /// same hedge is carried in `HowItWorksView` for the same reason, and dropping it here
    /// would make the glossary the more confident of the two.
    func testNeuralEngineDefinitionKeepsTheSchedulingHedge() {
        let technical = GlossaryTermID.neuralEngine.definition.technical

        XCTAssertTrue(
            technical.localizedCaseInsensitiveContains("preference")
                || technical.localizedCaseInsensitiveContains("not a guarantee"),
            "The Neural Engine definition must say that Core ML makes the final scheduling decision."
        )
    }
}
