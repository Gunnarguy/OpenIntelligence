//
//  AtlasLabelingTests.swift
//  OpenIntelligenceTests
//
//  Unit tests for AtlasLabeling pure static functions verifying deterministic
//  clustering, unique naming, stop-word / noise rejection, and semantic axis analysis.
//

import NaturalLanguage
import XCTest

@testable import OpenIntelligence

final class AtlasLabelingTests: XCTestCase {

    // MARK: - Terms Extraction

    func testTermsExtractionFiltersTokensWithDigitsAndStopWords() {
        let text =
            "GET /api/v1/invoices from customer sha256_hash e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 and valves"
        let terms = AtlasLabeling.terms(in: text)

        // Lowercased, letters only, 3..24
        XCTAssertTrue(terms.contains("invoices"))
        XCTAssertTrue(terms.contains("customer"))
        XCTAssertTrue(terms.contains("valves"))

        // Stop words dropped
        XCTAssertFalse(terms.contains("and"))
        XCTAssertFalse(terms.contains("from"))

        // Identifiers/encodings dropped (contain digit or > 24 chars)
        XCTAssertFalse(terms.contains("v1"))
        XCTAssertFalse(terms.contains("sha256"))
        XCTAssertFalse(terms.contains("sha256_hash"))
        XCTAssertFalse(terms.contains("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
    }

    // MARK: - Determinism Across Shuffles

    func testDeterminismWithShuffledInput() {
        let group0 = [
            "invoices and billing for client accounts",
            "billing ledger records and accounts",
            "invoices sent for customer billing accounts",
            "customer invoices and billing summary",
            "monthly billing invoices and payments",
        ]
        let group1 = [
            "hydraulic valves and pressure piping",
            "industrial valves and pressure fluid tubes",
            "pressure valves in hydraulic piping systems",
            "regulating valves and pressure tubing",
            "valves controlling hydraulic pressure fluid",
        ]
        let group2 = [
            "authentication tokens and secure credentials",
            "user login authentication and security tokens",
            "security tokens for authentication credentials",
            "login tokens verifying secure authentication",
            "authentication security credentials and tokens",
        ]
        let group3 = [
            "canvas rendering drawing graphics context",
            "graphics drawing canvas rendering shaders",
            "rendering graphics on the display canvas",
            "canvas graphics rendering and drawing textures",
            "drawing graphics pipeline on visual canvas",
        ]
        let group4 = [
            "database queries schema tables indexes",
            "relational database schema indexing queries",
            "database tables queries and index optimization",
            "schema tables in relational database queries",
            "indexing queries across database schema tables",
        ]

        let originalGroups = [group0, group1, group2, group3, group4]
        let baseNames = AtlasLabeling.clusterNames(groups: originalGroups)

        for _ in 0..<20 {
            // Shuffle order of passages within each group
            let shuffledGroups = originalGroups.map { $0.shuffled() }
            let shuffledNames = AtlasLabeling.clusterNames(groups: shuffledGroups)
            XCTAssertEqual(
                shuffledNames, baseNames, "Cluster names must be identical regardless of passage order within groups")
        }
    }

    // MARK: - Distinct Cluster Names

    func testFiveClustersNeverShareName() {
        // Create 5 groups that share similar vocabulary
        let group0 = Array(repeating: "records parent citation entry document", count: 10)
        let group1 = Array(repeating: "records parent node hierarchy tree", count: 10)
        let group2 = Array(repeating: "records parent element schema object", count: 10)
        let group3 = Array(repeating: "blob encoded binary storage payload", count: 10)
        let group4 = Array(repeating: "generic empty data passage content", count: 10)

        let names = AtlasLabeling.clusterNames(groups: [group0, group1, group2, group3, group4])

        XCTAssertEqual(names.count, 5)
        let uniqueNames = Set(names)
        XCTAssertEqual(uniqueNames.count, 5, "No two clusters may share a name even when keywords overlap")
    }

    // MARK: - 40% Common Term Rejection

    func testTermInOverFortyPercentOfPassagesIsNeverUsed() {
        // "commonterm" appears in 30 out of 50 passages (60% > 40%)
        // Group 0 has "commonterm" + "invoices"
        // Group 1 has "commonterm" + "valves"
        // Other groups have "commonterm" + generic words
        let group0 = Array(repeating: "commonterm invoices invoices invoices billing", count: 10)
        let group1 = Array(repeating: "commonterm valves valves valves pressure", count: 10)
        let group2 = Array(repeating: "commonterm generic neutral text", count: 10)
        let group3 = Array(repeating: "unique alpha beta gamma delta", count: 10)
        let group4 = Array(repeating: "specialized epsilon zeta theta kappa", count: 10)

        let names = AtlasLabeling.clusterNames(groups: [group0, group1, group2, group3, group4])

        for name in names {
            XCTAssertFalse(
                name.lowercased().contains("commonterm"),
                "A term found in over 40% of all passages must never be used in a cluster name"
            )
        }
    }

    // MARK: - A Word Common in Its Group Ranks First

    /// On the owner's iPhone (2026-10-15) a three-document library's clusters and axes were all named with two words
    /// starting with "A": every word found in one group alone had the same score however many of its passages
    /// carried it, and ties went alphabetically. "serotonin" is in all 20 passages of the first group (40% of the
    /// library, which the 40% rule still allows) and three "A" words are in three passages each; the ratio scored
    /// all four 2.5 and named the group "Abacus & Acorn".
    func testClusterNameLeadsWithTheWordInMostOfItsPassages() {
        let extras = ["abacus", "acorn", "adage"]
        let group0 = (0..<20).map { i in "serotonin study" + (i < 9 ? " " + extras[i / 3] : "") }
        let group1 =
            Array(repeating: "invoices billing study", count: 15) + Array(repeating: "valves pressure study", count: 15)

        let names = AtlasLabeling.clusterNames(groups: [group0, group1])

        XCTAssertTrue(names[0].hasPrefix("Serotonin"), "got \(names)")
        XCTAssertEqual(names[1], "Billing & Invoices")
    }

    /// The same tie at an axis end: "dopamine" is in all five of the lowest passages, "amber" and "anvil" in three.
    func testAxisEndLeadsWithTheWordInMostOfItsPassages() {
        var texts = (0..<5).map { i in "dopamine" + (i < 3 ? " amber anvil" : "") }
        texts += Array(repeating: "neutral standard general reference", count: 40)
        texts += Array(repeating: "valves hydraulic", count: 5)
        let values = (0..<50).map { Float($0) }

        let ends = AtlasLabeling.axisEnds(values: values, texts: texts)

        XCTAssertEqual(ends?.low.first, "dopamine", "got \(String(describing: ends?.low))")
        XCTAssertEqual(ends?.high, ["hydraulic", "valves"])
    }

    func testContrastRewardsAWordInMorePassages() {
        // Absent from the other set in both cases: more passages scores higher.
        XCTAssertGreaterThan(
            AtlasLabeling.contrast(18, of: 19, against: 0, of: 19),
            AtlasLabeling.contrast(3, of: 19, against: 0, of: 19))
        // In most of a set and one passage of the other, it still beats a word in three passages and none.
        XCTAssertGreaterThan(
            AtlasLabeling.contrast(18, of: 19, against: 1, of: 19),
            AtlasLabeling.contrast(3, of: 19, against: 0, of: 19))
        // No more common in the set than in the other: zero.
        XCTAssertEqual(AtlasLabeling.contrast(5, of: 10, against: 5, of: 10), 0)
        XCTAssertEqual(AtlasLabeling.contrast(1, of: 10, against: 9, of: 10), 0)
    }

    // MARK: - Axis Ends Analysis

    func testAxisEndsWithDistinctThemes() {
        // 50 passages:
        // Lowest 5 passages (values 0.0..0.4) are about invoices
        // Highest 5 passages (values 4.5..4.9) are about valves
        // Middle 40 passages are neutral/generic
        var texts = [String]()
        for _ in 0..<5 {
            texts.append("these passages describe invoices and billing records")
        }
        for _ in 0..<40 {
            texts.append("neutral standard general reference specifications")
        }
        for _ in 0..<5 {
            texts.append("these passages describe valves and hydraulic fluid")
        }

        let values = (0..<50).map { Float($0) * 0.1 }

        let ends = AtlasLabeling.axisEnds(values: values, texts: texts)
        XCTAssertNotNil(ends, "Axis with distinct extremes must produce valid AxisEnds")

        if let ends = ends {
            XCTAssertTrue(
                ends.low.contains("invoices"),
                "Low end must contain distinguishing term 'invoices', got \(ends.low)"
            )
            // Every word of the high passages distinguishes them equally, and ties go in
            // alphabetical order, so which two are shown is not "valves" in particular.
            let highWords: Set<String> = ["describe", "fluid", "hydraulic", "passages", "valves"]
            XCTAssertFalse(ends.high.isEmpty)
            XCTAssertTrue(Set(ends.high).isSubset(of: highWords), "got \(ends.high)")
            XCTAssertEqual(ends.lowLabel, AtlasLabeling.formatTerms(ends.low))
            XCTAssertEqual(ends.highLabel, AtlasLabeling.formatTerms(ends.high))
        }
    }

    // MARK: - Every Axis End Has Words (5.7)

    /// An end whose words are each in two of its passages is named by them, so no end of the map is blank. On the
    /// owner's iPhone one axis had no words at one end (2026-10-16).
    func testAnEndWhoseWordsAreInTwoOfItsPassagesIsNamedByThem() throws {
        var texts = [
            "Inspection checklist for the cabinet.", "Inspection checklist for the harbor.",
            "An orchard lantern hangs here.", "A glacier formed pottery shards.", "The meadow grows tall grass.",
        ]
        texts += Array(repeating: "The general reference section lists the standard parts.", count: 40)
        texts += Array(repeating: "Hydraulic valves hold the pressure in the line.", count: 5)
        let values = (0..<50).map { Float($0) }

        let ends = try XCTUnwrap(AtlasLabeling.axisEnds(values: values, texts: texts))

        XCTAssertEqual(ends.low, ["checklist", "inspection"])
        XCTAssertFalse(ends.high.isEmpty)
    }

    /// An end whose passages share no word more common there than at the other end reads "Component N", never blank,
    /// and a word as common at both ends ("device", "ready", "sits") names neither (a refuting review, 2026-10-16).
    func testAnEndWithNoWordOfItsOwnIsAComponentNotBlank() {
        var texts = Array(repeating: "The device sits ready.", count: 3)
        texts += ["A lantern lights the glacier.", "Pottery fills the meadow."]
        texts += Array(repeating: "The general reference section lists the standard parts.", count: 40)
        texts += Array(repeating: "The device sits ready with hydraulic valves.", count: 3)
        texts += Array(repeating: "Hydraulic valves hold the pressure.", count: 2)
        let coords = (0..<50).map { SIMD3<Float>(Float($0), Float($0), Float($0)) }

        let ends = AtlasLabeling.axisEnds(values: coords.map(\.x), texts: texts)
        let labels = AtlasLabeling.axisLabels(coords: coords, texts: texts)

        XCTAssertEqual(ends?.low, [])
        XCTAssertEqual(ends?.high, ["hydraulic", "valves"])
        XCTAssertEqual(Array(labels.prefix(2)), ["Component 1", "Hydraulic & Valves"])
        XCTAssertFalse(labels.contains(""), "got \(labels)")
    }

    /// An adverb does not name an axis end: on the owner's iPhone one read "Blade & Gently".
    func testAnAdverbDoesNotNameAnAxisEnd() throws {
        var texts = Array(repeating: "Soak the handpiece in the enzymatic detergent.", count: 5)
        texts += Array(repeating: "The general reference section lists the standard parts.", count: 40)
        texts += Array(repeating: "Gently wipe the tray with a soft towel.", count: 5)
        let values = (0..<50).map { Float($0) }

        let ends = try XCTUnwrap(AtlasLabeling.axisEnds(values: values, texts: texts))

        XCTAssertEqual(ends.high, ["soft", "towel"])
    }

    /// The word classes of a library's languages are asked for only where a language can have them, once a launch,
    /// and the wait has an end (5.7). Japanese has none, so it is not asked for. Whether the system loads Spanish here
    /// is printed, not assumed.
    func testLoadingWordClassesAsksOnlyWhereTheyExistAndWaitsAtMostItsTimeout() async {
        let texts = [
            "Gently wipe the tray with a soft towel before you store it.",
            "自然言語処理の研究を進めるための基礎的な技術",
            "Limpie suavemente la bandeja con una toalla limpia y seca antes de guardarla.",
        ]

        let start = ContinuousClock.now
        let available = await AtlasLabeling.loadWordClasses(for: texts, timeout: .seconds(2))
        let elapsed = ContinuousClock.now - start
        print("WORD CLASSES AFTER LOADING: \(available.sorted()) in \(elapsed)")

        XCTAssertTrue(available.contains("en"), "got \(available)")
        XCTAssertFalse(available.contains("ja"))
        XCTAssertLessThan(elapsed, .seconds(3))
        // Asked for once a launch: a second time nothing is asked for, so nothing is waited for.
        let again = ContinuousClock.now
        _ = await AtlasLabeling.loadWordClasses(for: texts, timeout: .seconds(2))
        XCTAssertLessThan(ContinuousClock.now - again, .seconds(1))
    }

    /// A word is tagged where it stands in its passages, each in its own language: "tray" alone came back an adverb
    /// on macOS 27 and in a sentence a noun, and a library of instructions for use is often in several languages. A
    /// language the system has no word classes for keeps its words: in the iOS 27 Simulator (2026-10-16) Spanish and
    /// German had none, and on macOS 27 both did.
    func testNamingTermsDropsWordsTheirPassagesUseAsAdverbs() {
        let passages = [
            "Gently wipe the tray, then rinse the blade carefully.", "Rinse the blade gently under running water.",
            "Limpie suavemente la bandeja con una toalla limpia y seca.",
            "Wischen Sie das Tablett vorsichtig mit einem weichen Tuch ab.",
        ]
        let terms = passages.map { AtlasLabeling.terms(in: $0) }

        func hasWordClasses(_ language: NLLanguage) -> Bool {
            NLTagger.availableTagSchemes(for: .word, language: language).contains(.lexicalClass)
        }
        print("WORD CLASSES: Spanish \(hasWordClasses(.spanish)), German \(hasWordClasses(.german))")
        var expected = ["tray", "bandeja", "blade", "tablett"]
        if !hasWordClasses(.german) { expected.insert("vorsichtig", at: 0) }
        if !hasWordClasses(.spanish) { expected.insert("suavemente", at: 0) }
        XCTAssertEqual(
            AtlasLabeling.namingTerms(
                ["gently", "suavemente", "vorsichtig", "tray", "carefully", "bandeja", "blade", "tablett"],
                passages: passages, terms: terms, limit: 8),
            expected)
        XCTAssertEqual(
            AtlasLabeling.namingTerms(
                ["blade", "rinse", "tray"], passages: passages, terms: terms, limit: 2, excluding: ["blade"]),
            ["rinse", "tray"])
        // No word classes for Japanese: every word is kept.
        let japanese = ["自然言語処理の研究"]
        XCTAssertEqual(
            AtlasLabeling.namingTerms(
                ["自然", "処理"], passages: japanese, terms: japanese.map { AtlasLabeling.terms(in: $0) }, limit: 2),
            ["自然", "処理"])
    }

    /// A map's six labels: every end has words, no word names two ends, and an axis whose ends do not differ reads
    /// "Component N" at both ends.
    func testAMapsAxisLabelsNameEveryEndOnceAndAnUndividedAxisIsAComponent() {
        var texts = Array(repeating: "Invoices list the billing records for each customer account.", count: 5)
        texts += Array(repeating: "The general reference section lists the standard parts.", count: 40)
        texts += Array(repeating: "Hydraulic valves hold the pressure in the line.", count: 5)
        // x and y order the passages the same way; z puts general passages at both of its ends.
        let coords = (0..<50).map { i -> SIMD3<Float> in
            let z: Float = (5..<10).contains(i) ? -10 : (40..<45).contains(i) ? 10 : 0
            return SIMD3(Float(i), Float(i), z)
        }

        let labels = AtlasLabeling.axisLabels(coords: coords, texts: texts)

        XCTAssertEqual(labels.count, 6)
        XCTAssertEqual(Array(labels.suffix(2)), ["Component 3", "Component 3"])
        XCTAssertFalse(labels.prefix(4).contains { $0.isEmpty || $0.hasPrefix("Component") }, "got \(labels)")
        let words = labels.prefix(4).flatMap { $0.components(separatedBy: " & ") }
        XCTAssertEqual(Set(words).count, words.count, "a word names two ends: \(labels)")
    }

    func testAxisEndsWithNoDifferenceReturnsNil() {
        // 50 passages with identical content across all coordinates
        let texts = Array(repeating: "neutral standard general reference specifications", count: 50)
        let values = (0..<50).map { Float($0) * 0.1 }

        let ends = AtlasLabeling.axisEnds(values: values, texts: texts)
        XCTAssertNil(ends, "An axis with no thematic difference between extremes must return nil")
    }

    // MARK: - Multilingual Support

    func testJapaneseAndSpanishProduceNamesFromOwnPassages() {
        // Japanese: NLTokenizer segments without spaces, kanji compounds are caseless and >= 2 chars
        let japanesePassages = [
            "自然言語処理と機械学習の研究開発を進める",
            "深層学習を用いた自然言語処理モデルの構築",
            "日本語テキストに対する自然言語処理技術の応用",
            "自然言語処理アルゴリズムの評価と検証",
        ]
        let jpNames = AtlasLabeling.clusterNames(groups: [japanesePassages])
        XCTAssertEqual(jpNames.count, 1)
        let jpName = jpNames[0]
        XCTAssertFalse(jpName.isEmpty)
        XCTAssertNotEqual(jpName, "Group 1", "Japanese passages should produce meaningful terms, got \(jpName)")
        // Verify every character in the name comes from the Japanese passages
        let allJpText = japanesePassages.joined()
        for char in jpName where !char.isWhitespace && char != "&" {
            XCTAssertTrue(allJpText.contains(char), "Character \(char) in name \(jpName) must be from input passages")
        }

        // Spanish: Cased script with accents, filters 1-2 char words like 'de', 'en', 'y'
        let spanishPassages = [
            "tratamiento de enfermedades infecciosas en hospitales",
            "pacientes con enfermedades infecciosas graves",
            "diagnóstico temprano de enfermedades infecciosas",
            "investigación clínica de enfermedades infecciosas avanzadas",
        ]
        let esNames = AtlasLabeling.clusterNames(groups: [spanishPassages])
        XCTAssertEqual(esNames.count, 1)
        let esName = esNames[0]
        XCTAssertFalse(esName.isEmpty)
        XCTAssertNotEqual(esName, "Group 1", "Spanish passages should produce meaningful terms, got \(esName)")
        let allEsText = spanishPassages.joined().lowercased()
        for word in esName.components(separatedBy: .whitespaces) where word != "&" {
            XCTAssertTrue(
                allEsText.contains(word.lowercased()), "Word \(word) in name \(esName) must be from input passages")
        }
    }

    // MARK: - Non-Text & Degenerate Content

    func testSourceCodeAndNumberTablesDoNotCrash() {
        let codePassages = [
            "func processPayment(amount: Double, currency: String) -> Result<PaymentReceipt, PaymentError> {",
            "    guard amount > 0 else { return .failure(.invalidAmount) }",
            "    let transactionId = UUID().uuidString",
            "    return .success(PaymentReceipt(id: transactionId, amount: amount))",
            "}",
        ]

        let numberTablePassages = [
            "100.0   200.5   300.2   400.1",
            "0.001   0.002   0.003   0.004",
            "12345   67890   54321   98765",
            "99.99   88.88   77.77   66.66",
        ]

        let names = AtlasLabeling.clusterNames(groups: [codePassages, numberTablePassages])
        XCTAssertEqual(names.count, 2)
        // Code should extract valid words or fallback to Group 1
        XCTAssertFalse(names[0].isEmpty)
        // Number tables have only digits and symbols, so all tokens contain digits and are filtered -> Group 2 fallback
        XCTAssertEqual(names[1], "Group 2", "Number tables with no alphabetic words must fall back to Group N")

        // AxisEnds with number tables must not crash
        let values: [Float] = [0.1, 0.2, 0.8, 0.9]
        let ends = AtlasLabeling.axisEnds(values: values, texts: numberTablePassages)
        XCTAssertNil(ends, "Axis without distinctive word contrast must return nil")
    }

    func testSmallLibrariesOfOneAndThreePassages() {
        // 1-passage library
        let singlePassage = ["quantum computing algorithms for optimization"]
        let singleCluster = AtlasLabeling.clusterNames(groups: [singlePassage])
        XCTAssertEqual(singleCluster.count, 1)
        XCTAssertFalse(singleCluster[0].isEmpty)
        let singleAxis = AtlasLabeling.axisEnds(values: [1.0], texts: singlePassage)
        XCTAssertNil(singleAxis, "Fewer than 4 passages must return nil for axis")

        // 3-passage library (< 40 passages threshold applies)
        let threePassages = [
            "quantum computing algorithms for optimization",
            "quantum algorithms and circuits for entanglement",
            "quantum processor optimization and error correction",
        ]
        let threeCluster = AtlasLabeling.clusterNames(groups: [threePassages])
        XCTAssertEqual(threeCluster.count, 1)
        XCTAssertFalse(threeCluster[0].isEmpty)
        XCTAssertTrue(threeCluster[0].lowercased().contains("quantum"))

        let threeAxis = AtlasLabeling.axisEnds(values: [0.0, 0.5, 1.0], texts: threePassages)
        XCTAssertNil(threeAxis, "Fewer than 4 passages must return nil for axis")
    }

    func testAllPassagesIdentical() {
        let identicalPassages = Array(repeating: "artificial intelligence neural networks", count: 25)
        let names = AtlasLabeling.clusterNames(groups: [identicalPassages])
        XCTAssertEqual(names.count, 1)
        XCTAssertFalse(names[0].isEmpty)

        // Axis ends with identical passages must not crash or divide by zero: returns nil
        let values = (0..<25).map { Float($0) }
        let ends = AtlasLabeling.axisEnds(values: values, texts: identicalPassages)
        XCTAssertNil(ends, "Identical passages have no contrast and must return nil")
    }

    // MARK: - Deterministic K-Means

    func testKMeansHelperDeterminismAndSeparation() {
        // Two well-separated 3D blobs (10 points each)
        var blobA: [[Float]] = []
        var blobB: [[Float]] = []

        for i in 0..<10 {
            let offset = Float(i) * 0.05
            blobA.append([10.0 + offset, 10.0 - offset, 10.0 + offset])
            blobB.append([-10.0 + offset, -10.0 - offset, -10.0 + offset])
        }

        let combined = blobA + blobB

        let run1 = AtlasLabeling.kMeans(embeddings: combined, k: 2)
        let run2 = AtlasLabeling.kMeans(embeddings: combined, k: 2)

        // Must be 100% deterministic on repeated runs
        XCTAssertEqual(run1, run2, "kMeans must produce identical cluster assignments across multiple runs")

        // Must place all of blob A in one cluster and all of blob B in the other
        let clusterA = run1[0]
        for i in 0..<10 {
            XCTAssertEqual(run1[i], clusterA, "Point \(i) in Blob A should belong to cluster \(clusterA)")
        }

        let clusterB = run1[10]
        XCTAssertNotEqual(clusterA, clusterB, "Blob A and Blob B must be assigned to different clusters")

        for i in 10..<20 {
            XCTAssertEqual(run1[i], clusterB, "Point \(i) in Blob B should belong to cluster \(clusterB)")
        }

        // Test defaultK logic
        XCTAssertEqual(AtlasLabeling.defaultK(for: 1), 1)
        XCTAssertEqual(AtlasLabeling.defaultK(for: 11), 1)
        XCTAssertEqual(AtlasLabeling.defaultK(for: 12), 2)
        XCTAssertEqual(AtlasLabeling.defaultK(for: 2000), 2)
        XCTAssertEqual(AtlasLabeling.defaultK(for: 3500), 4)
        XCTAssertEqual(AtlasLabeling.defaultK(for: 10000), 6)
    }

    // MARK: - Names from the library's structure (5.7)

    /// A document's file name, shortened for the map: no extension, the part before " - ", no word with a digit in it,
    /// at most 28 characters in whole words.
    func testDocumentNamesAreShortenedForTheMap() {
        XCTAssertEqual(AtlasLabeling.shortDocumentName("Kestrel AF-620 Air Fryer Manual.pdf"), "Kestrel Air Fryer Manual")
        XCTAssertEqual(AtlasLabeling.shortDocumentName("Juniper Flats Lease - Unit 4B.pdf"), "Juniper Flats Lease")
        XCTAssertEqual(AtlasLabeling.shortDocumentName("Home Insurance Declarations 2026.pdf"), "Home Insurance Declarations")
        XCTAssertEqual(AtlasLabeling.shortDocumentName("2027 Benefits at a Glance.docx"), "Benefits at a Glance")
        XCTAssertEqual(AtlasLabeling.shortDocumentName("Grandma's Banana Bread.txt"), "Grandma's Banana Bread")
        XCTAssertEqual(AtlasLabeling.shortDocumentName("Alder Creek Elementary Family Handbook.pdf"), "Alder Creek Elementary")
        XCTAssertEqual(AtlasLabeling.shortDocumentName("2026.pdf"), "2026", "a name of digits only keeps them")
    }

    /// A section heading as a name: no leading number, title case for one set in capitals, and none for a sentence, an
    /// address or a heading too long to be a name.
    func testSectionHeadingsAreCleanedOrLeftOut() {
        XCTAssertEqual(AtlasLabeling.sectionName("5. Late Charges"), "Late Charges")
        XCTAssertEqual(AtlasLabeling.sectionName("A. Dwelling"), "Dwelling")
        XCTAssertEqual(AtlasLabeling.sectionName("TROUBLESHOOTING"), "Troubleshooting")
        XCTAssertEqual(AtlasLabeling.sectionName("HOW TO CANCEL"), "How to Cancel")
        XCTAssertEqual(AtlasLabeling.sectionName("Member signature"), "Member signature")
        XCTAssertNil(AtlasLabeling.sectionName("418 Mercer Plaza, Riverton"))
        XCTAssertNil(AtlasLabeling.sectionName("2. Stir the melted butter into the mashed bananas."))
        XCTAssertNil(AtlasLabeling.sectionName("   "))
    }

    /// An axis that runs from one document to another is named by the two documents; one that runs between two parts
    /// of one document, by their section headings; and one with neither still has a name at each end (the owner,
    /// 2026-10-20: "Air & Fryer" named an axis by two words of one product's name).
    func testAxisEndsAreNamedByTheirDocumentOrSection() {
        var coords: [SIMD3<Float>] = []
        var texts: [String] = []
        var groups: [String?] = []
        var sections: [String?] = []
        for i in 0..<20 {
            // The lease: low on x.
            coords.append(SIMD3(-1 - Float(i) * 0.1, 0, Float(i % 5) * 0.1))
            texts.append("The tenant pays rent each month under the lease and its clauses \(["alpha", "beta"][i % 2])")
            groups.append("Juniper Flats Lease")
            sections.append(i % 2 == 0 ? "5. Late Charges" : "9. Pets")
        }
        for i in 0..<20 {
            // The manual: high on x, and along y its cleaning pages below and its settings pages above.
            let cleaning = i < 10
            coords.append(SIMD3(1 + Float(i) * 0.1, cleaning ? -1 - Float(i) * 0.1 : 1 + Float(i) * 0.1, Float(i % 5) * 0.1))
            texts.append(
                cleaning
                    ? "Wipe the basket and wash the tray with warm water and soap \(["alpha", "beta"][i % 2])"
                    : "Set the temperature and the timer with the dial on the front \(["alpha", "beta"][i % 2])")
            groups.append("Kestrel Air Fryer Manual")
            sections.append(cleaning ? "CLEANING" : "SETTINGS")
        }
        let sources = AtlasLabeling.PassageSources(groups: groups, sections: sections)
        let labels = AtlasLabeling.axisLabels(coords: coords, texts: texts, sources: sources)

        XCTAssertEqual(labels.count, 6)
        XCTAssertEqual(labels[0], "Juniper Flats Lease")
        XCTAssertEqual(labels[1], "Kestrel Air Fryer Manual")
        XCTAssertEqual(labels[2], "Cleaning")
        XCTAssertEqual(labels[3], "Settings")
        XCTAssertFalse(labels.contains(""), "no end is blank: \(labels)")
        XCTAssertEqual(Set(labels).count, labels.count, "no name names two ends: \(labels)")
        // Without the sources the same map is named by its words, as before.
        XCTAssertNotEqual(AtlasLabeling.axisLabels(coords: coords, texts: texts)[0], "Juniper Flats Lease")
    }

    /// A cluster most of whose passages come from one document is named by it, and one with no such document keeps its
    /// words; no two clusters share a name.
    func testClustersAreNamedByTheirDocumentWhereOneStandsOut() {
        let membership = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2]
        let groups: [String?] = [
            "Juniper Flats Lease", "Juniper Flats Lease", "Juniper Flats Lease", "Kestrel Air Fryer Manual",
            "Kestrel Air Fryer Manual", "Kestrel Air Fryer Manual", "Kestrel Air Fryer Manual", "Kestrel Air Fryer Manual",
            "Juniper Flats Lease", "Kestrel Air Fryer Manual", "Home Insurance Declarations", "Lisbon Trip Itinerary",
        ]
        let sources = AtlasLabeling.PassageSources(groups: groups, sections: Array(repeating: nil, count: 12))
        let names = AtlasLabeling.clusterNames(
            distinguishingTerms: [["rent", "tenant"], ["basket", "timer"], ["mixed", "things"]],
            membership: membership, sources: sources)
        XCTAssertEqual(names, ["Juniper Flats Lease", "Kestrel Air Fryer Manual", "Mixed & Things"])
    }

    /// A document that already names one end and stands out at another names the second with the section its passages
    /// there share; in a map of several libraries, an end where no document stands out is named by its library.
    func testASecondEndOfADocumentTakesItsSectionAndAMixedEndItsLibrary() {
        let sources = AtlasLabeling.PassageSources(
            groups: ["Lease", "Lease", "Lease", "Lease", "Notes", "Recipe", "Pantry", "Menu"],
            sections: ["5. Late Charges", "5. Late Charges", "9. Pets", nil, nil, nil, nil, nil],
            libraries: ["Home", "Home", "Home", "Home", "Kitchen", "Kitchen", "Kitchen", "Kitchen"])
        let lease = [0, 1, 2, 3], kitchen = [4, 5, 6, 7]
        XCTAssertEqual(AtlasLabeling.sourceName(indices: lease, otherIndices: kitchen, sources: sources, used: []), "Lease")
        XCTAssertEqual(
            AtlasLabeling.sourceName(indices: lease, otherIndices: kitchen, sources: sources, used: ["Lease"]),
            "Lease: Late Charges")
        XCTAssertEqual(AtlasLabeling.sourceName(indices: kitchen, otherIndices: lease, sources: sources, used: []), "Kitchen")
    }

    /// A cluster is named by a document that is 40% of it with twice the passages of the next, and keeps its words when
    /// two documents are as large as each other.
    func testAClusterTakesADocumentThatLeadsItAtFortyPercent() {
        let membership = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1]
        let groups: [String?] = ["Manual", "Manual", "Lease", "Notes", "Recipe", "Itinerary", "Itinerary", "Policy", "Policy", "Menu"]
        let sources = AtlasLabeling.PassageSources(groups: groups, sections: Array(repeating: nil, count: 10))
        let names = AtlasLabeling.clusterNames(
            distinguishingTerms: [["basket", "timer"], ["travel", "cover"]], membership: membership, sources: sources)
        XCTAssertEqual(names, ["Manual", "Travel & Cover"])
    }
}
