//
//  HeadingClaimTests.swift
//  OpenIntelligenceTests
//
//  An answer's own heading is not a claim for Fact Check (5.7, `VerificationGateService.headingLines`). The model
//  sometimes lists its title among its claims, and "Hotel Address in Lisbon" was scored Partial, so a right answer
//  read "1 of 2 Verified" (demo copy of e9de06d in the Simulator, 2026-10-15).
//

import XCTest

@testable import OpenIntelligence

final class HeadingClaimTests: XCTestCase {
    func testHeadingsAreFoundInEveryForm() {
        let answer = """
            ## Hotel Address in Lisbon
            The hotel is Casa Azulejo, Rua das Flores 41, Chiado [S3].
            **Check-out**
            Getting there:
            Take the metro to Baixa-Chiado.
            """
        let headings = VerificationGateService.headingLines(in: answer)
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Hotel Address in Lisbon")))
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Check-out")))
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Getting there")))
        XCTAssertFalse(
            headings.contains(VerificationGateService.headingKey("The hotel is Casa Azulejo, Rua das Flores 41, Chiado.")))
        XCTAssertFalse(headings.contains(VerificationGateService.headingKey("Take the metro to Baixa-Chiado.")))
    }

    func testAnAnswerWithNoHeadingsHasNone() {
        XCTAssertTrue(VerificationGateService.headingLines(in: "Check-out is at 11:00 a.m. [S2].").isEmpty)
    }

    private func leaseChunk(_ text: String) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0,
            pageNumber: 2,
            sectionTitle: nil,
            keywords: [],
            hasNumericData: false,
            hasListStructure: false,
            wordCount: text.split(separator: " ").count,
            characterCount: text.count
        )
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [0], metadata: metadata),
            similarityScore: 0.9,
            rank: 1,
            sourceDocument: "Juniper Flats Lease - Unit 4B.pdf",
            pageNumber: 2
        )
    }

    /// The heading stays out of the answer's claim list too, so Fact Check neither lists it as "Not checked" nor
    /// counts it: the half `eaccacc` left, seen 2026-10-18 in 2 of 4 takes of one question in the Simulator. And the
    /// space a removed citation leaves before the full stop goes with it.
    func testAHeadingNeverReachesTheClaimListAndNoSpaceIsLeftWhereACitationWas() {
        let lease = "13. Entry by Landlord. Landlord will give at least 24 hours' notice before entering, except in an emergency."
        let generation = StructuredRAGGeneration(
            reasoning: nil,
            answer: "**Notice to Enter**\n- The landlord must give at least 24 hours' notice before entering, except in an emergency [S1].",
            confidence: 90,
            citations: ["S1"],
            matchedTerms: [],
            claims: [
                StructuredRAGClaim(claim: "Notice to Enter", citations: [], isExtracted: false),
                StructuredRAGClaim(
                    claim: "The landlord must give at least 24 hours' notice before entering, except in an emergency [S1].",
                    citations: ["S1"], isExtracted: true),
            ])
        let answer = StructuredAnswer.from(
            response: generation.answer,
            retrievedChunks: [leaseChunk(lease)],
            answerIntent: .lookup,
            verificationResult: nil,
            structuredGeneration: generation)
        XCTAssertEqual(
            answer.claims.map(\.claim),
            ["The landlord must give at least 24 hours' notice before entering, except in an emergency."])
    }

    private func structured(_ answer: String, _ claims: [(String, [String])]) -> StructuredRAGGeneration {
        StructuredRAGGeneration(
            reasoning: nil, answer: answer, confidence: 90, citations: ["S1"], matchedTerms: [],
            claims: claims.map { StructuredRAGClaim(claim: $0.0, citations: $0.1, isExtracted: true) })
    }

    private func claims(of generation: StructuredRAGGeneration, chunk text: String) -> [String] {
        StructuredAnswer.from(
            response: generation.answer, retrievedChunks: [leaseChunk(text)], answerIntent: .lookup,
            verificationResult: nil, structuredGeneration: generation
        ).claims.map(\.claim)
    }

    /// A sentence the answer makes in bold is a claim, not a heading (review, 2026-10-18): treating every bold line as
    /// a heading took "$400 deposit" out of Fact Check and, with the checks on, out of the answer itself.
    func testABoldSentenceIsAClaimNotAHeading() {
        let answer = "**Yes, cats are allowed with a $400 deposit.**\n- The deposit is refundable [S2]."
        XCTAssertTrue(VerificationGateService.headingLines(in: answer).isEmpty)
        XCTAssertTrue(VerificationGateService.isBoldTitle("**Notice to Enter**"))
        XCTAssertFalse(VerificationGateService.isBoldTitle("**Yes, cats are allowed with a $400 deposit.**"))
        let generation = structured(answer, [
            ("Yes, cats are allowed with a $400 deposit.", []), ("The deposit is refundable [S2].", ["S2"]),
        ])
        XCTAssertEqual(
            claims(of: generation, chunk: "Cats are allowed with a $400 deposit. The deposit is refundable."),
            ["Yes, cats are allowed with a $400 deposit.", "The deposit is refundable."])
    }

    /// A bold line that makes a statement is a claim, cited or not, and a bold title with a figure in it is a heading
    /// only when the answer gives the figure again; a number that names a part is not a figure (two reviews,
    /// 2026-10-18).
    func testABoldStatementIsAClaimAndABoldTitlesFiguresMustBeGivenAgain() {
        func headings(_ answer: String) -> Set<String> { VerificationGateService.headingLines(in: answer) }
        XCTAssertTrue(headings("**Subletting is allowed** [S2]\n- With written consent [S2].").isEmpty)
        XCTAssertTrue(headings("**No, pets are not allowed**\n- Section 9 covers pets [S1].").isEmpty)
        XCTAssertTrue(headings("**No pets**\n- Section 9 covers pets [S1].").isEmpty)
        XCTAssertTrue(headings("**24 hours' notice**\n- Except in an emergency [S1].").isEmpty)
        XCTAssertEqual(
            headings("**24 hours' notice**\n- The landlord must give at least 24 hours' notice [S1]."),
            [VerificationGateService.headingKey("24 hours' notice")])
        // A list number and a citation label are not figures the answer gives.
        XCTAssertTrue(headings("**2 pets per unit**\n1. Cats need a $400 deposit [S1].\n2. Dogs are not allowed [S1].").isEmpty)
        // A number that names a part is a label, given again or not.
        XCTAssertEqual(
            headings("**Unit 4B Pet Policy**\n- Two cats are allowed [S2]."), [VerificationGateService.headingKey("Unit 4B Pet Policy")])
        XCTAssertEqual(
            headings("**Step 1: Gather Documents**\n- Bring a photo ID [S1]."),
            [VerificationGateService.headingKey("Step 1: Gather Documents")])
        // A Markdown heading stays a heading whatever its numbers, as in b70eea1.
        XCTAssertEqual(headings("## Step 1\n- Sign the lease [S1]."), [VerificationGateService.headingKey("Step 1")])
        // A number written as a word is not read, so this title is a heading. A known limit of the rule.
        XCTAssertEqual(
            headings("**Two pets per unit**\n- Cats need a deposit [S1]."), [VerificationGateService.headingKey("Two pets per unit")])
    }

    /// A Markdown heading in sentence case that states something is a claim, so neither the check nor the source-only
    /// answer leaves it out; one in Title Case is a title, and a lead-in is a heading whatever it says (three reviews,
    /// 2026-10-18).
    @MainActor
    func testAHeadingInSentenceCaseThatStatesSomethingIsAClaim() {
        func headings(_ answer: String) -> Set<String> { VerificationGateService.headingLines(in: answer) }
        XCTAssertTrue(headings("## Subletting is allowed with written consent\n- Ask the landlord in writing [S1].").isEmpty)
        XCTAssertTrue(headings("## Subletting is allowed [S2]\n- With written consent [S2].").isEmpty)
        XCTAssertEqual(headings("## What Is Included\n- Water and trash [S1]."), [VerificationGateService.headingKey("What Is Included")])
        XCTAssertEqual(headings("## Things to Do Nearby\nThe hotel is near the metro [S3]."), [VerificationGateService.headingKey("Things to Do Nearby")])
        XCTAssertEqual(headings("## Fees You May Owe\n- A $50 fee [S2]."), [VerificationGateService.headingKey("Fees You May Owe")])
        XCTAssertEqual(
            headings("You must bring:\n- A photo ID [S1]."), [VerificationGateService.headingKey("You must bring")])
        XCTAssertEqual(
            headings("Pets are allowed under these conditions:\n- A $400 deposit [S1]."),
            [VerificationGateService.headingKey("Pets are allowed under these conditions")])
        // A statement written in Title Case reads as a title. A known limit of the rule.
        XCTAssertEqual(headings("## Rent Is Due on the 1st\n- Late after the 5th [S1]."), [VerificationGateService.headingKey("Rent Is Due on the 1st")])
        XCTAssertEqual(headings("Here's what the lease says:\n- Rent is due on the 1st [S1]."), [VerificationGateService.headingKey("Here's what the lease says")])
        let draft = "## Subletting is allowed with written consent\n- Ask the landlord in writing [S1].\n- A $50 fee applies [S2]."
        func claim(_ text: String) -> SourceOnlyVerifiedClaim {
            SourceOnlyVerifiedClaim(
                claimId: text, claimText: text, verdict: .supported, evidenceLabels: ["S1"], evidenceIds: [],
                evidenceQuote: "", fidelity: 0.9, notes: nil, isCritical: false)
        }
        let claims = ["Subletting is allowed with written consent.", "Ask the landlord in writing.", "A $50 fee applies."]
        XCTAssertEqual(SourceOnlyAnswerService.claimsToList(claims.map(claim), candidateAnswer: draft).count, 3)
        // In Title Case or as a lead-in the heading reads as a title, and the claim that copies it still states
        // something, so the source-only answer keeps it (fourth review, 2026-10-18).
        let titleCaseDraft = "## Subletting Is Allowed With Written Consent\n- Ask the landlord in writing [S1].\n- A $50 fee applies [S2]."
        XCTAssertEqual(SourceOnlyAnswerService.claimsToList(claims.map(claim), candidateAnswer: titleCaseDraft).count, 3)
        let leadInDraft = "Subletting is allowed with written consent:\n- Ask the landlord in writing [S1].\n- A $50 fee applies [S2]."
        XCTAssertEqual(SourceOnlyAnswerService.claimsToList(claims.map(claim), candidateAnswer: leadInDraft).count, 3)
    }

    /// Which bold lines read as titles (second review, 2026-10-18).
    func testWhichBoldLinesAreTitles() {
        XCTAssertFalse(VerificationGateService.isBoldTitle("**Pets allowed with written consent**"))
        XCTAssertFalse(VerificationGateService.isBoldTitle("**Smoking prohibited indoors**"))
        XCTAssertTrue(VerificationGateService.isBoldTitle("**Required Documents**"))
        XCTAssertTrue(VerificationGateService.isBoldTitle("**What Is Included**"))
        XCTAssertTrue(VerificationGateService.isBoldTitle("**What\u{2019}s Included**"))
        XCTAssertFalse(VerificationGateService.isBoldTitle("**What is included: water and trash**"))
        XCTAssertFalse(VerificationGateService.isBoldTitle("**Utilities paid by the landlord**"))
        XCTAssertFalse(VerificationGateService.isBoldTitle("**Pets welcome**"))
        XCTAssertTrue(VerificationGateService.isBoldTitle("**Welcome Packet**"))
        XCTAssertTrue(VerificationGateService.isBoldTitle("**Things to Do Nearby**"))
        XCTAssertFalse(VerificationGateService.isBoldTitle("**Pet Policy: No Dogs Allowed**"))
        XCTAssertFalse(VerificationGateService.isBoldTitle("**Pets aren\u{2019}t allowed**"))
        XCTAssertFalse(VerificationGateService.isBoldTitle("**\u{30DA}\u{30C3}\u{30C8}\u{306F}\u{7981}\u{6B62}\u{3067}\u{3059}\u{3002}**"))
    }

    /// Gate B checks the sentences it would check anyway even when every one is heading-like, it checks the structured
    /// claims when every one is a heading (what Fact Check lists then), and it checks a bold figure the answer gives
    /// nowhere else (two reviews, 2026-10-18).
    @MainActor
    func testGateBChecksWhatOnlyLooksLikeAHeading() async {
        let gate = VerificationGateService()
        let chunk = leaseChunk("Room types: studio, one-bedroom. Landlord will give at least 24 hours' notice before entering.")
        let onlyATitle = await gate.verify(
            response: "**Room Types**", query: "Which room types are there?", retrievedChunks: [chunk], topScores: [0.9])
        XCTAssertFalse(onlyATitle.claimResults.isEmpty)
        let onlyTitleClaims = await gate.verify(
            response: "**Room Types**", query: "Which room types are there?", retrievedChunks: [chunk], topScores: [0.9],
            structuredClaims: [StructuredRAGClaim(claim: "Room Types", citations: [], isExtracted: false)])
        XCTAssertFalse(onlyTitleClaims.claimResults.isEmpty)
        let figure = await gate.verify(
            response: "**24 hours' notice**\n- Except in an emergency [S1].", query: "How much notice?",
            retrievedChunks: [chunk], topScores: [0.9],
            structuredClaims: [
                StructuredRAGClaim(claim: "24 hours' notice", citations: [], isExtracted: true),
                StructuredRAGClaim(claim: "Except in an emergency [S1].", citations: ["S1"], isExtracted: true),
            ])
        XCTAssertTrue(figure.claimResults.contains { $0.claim.contains("24 hours") }, "\(figure.claimResults.map(\.claim))")
        // When the model lists only its heading, the answer's own sentences are checked, under the rule for them, as in
        // b70eea1; StructuredAnswer lists the same sentences (testATitleOnlyClaimListShowsTheAnswersSentences).
        let titleListed = await gate.verify(
            response: "**Notice to Enter**\n- The landlord must give at least 24 hours' notice [S1].", query: "How much notice?",
            retrievedChunks: [chunk], topScores: [0.9],
            structuredClaims: [StructuredRAGClaim(claim: "Notice to Enter", citations: [], isExtracted: false)])
        XCTAssertFalse(titleListed.claimResults.contains { $0.claim == "Notice to Enter" }, "\(titleListed.claimResults.map(\.claim))")
        XCTAssertTrue(titleListed.claimResults.contains { $0.claim.contains("24 hours' notice") }, "\(titleListed.claimResults.map(\.claim))")
        XCTAssertEqual(titleListed.gateResults.first { $0.gate == .evidenceCoverage }?.passed, true)
        // A question the model listed as a claim is not one.
        let withQuestion = await gate.verify(
            response: "**Notice to Enter**\n- The landlord must give at least 24 hours' notice [S1].", query: "How much notice?",
            retrievedChunks: [chunk], topScores: [0.9],
            structuredClaims: [
                StructuredRAGClaim(claim: "Notice to Enter", citations: [], isExtracted: false),
                StructuredRAGClaim(claim: "What is the notice period?", citations: [], isExtracted: false),
            ])
        XCTAssertFalse(withQuestion.claimResults.contains { $0.claim.hasSuffix("?") }, "\(withQuestion.claimResults.map(\.claim))")
        // Gate B's own sentences are the ones with factual content (a number, a unit, a word such as "type"), so a title
        // with none, alone, still has no claim to check, as in 5.6.
        let bareTitle = await gate.verify(
            response: "**Notice to Enter**", query: "How much notice?", retrievedChunks: [chunk], topScores: [0.9])
        XCTAssertTrue(bareTitle.claimResults.isEmpty)
        let twoSources = await gate.verify(
            response: "Both apply [S1, S2].", query: "Which apply?", retrievedChunks: [chunk], topScores: [0.9],
            structuredClaims: [StructuredRAGClaim(claim: "Both apply [S1, S2].", citations: ["S1", "S2"], isExtracted: true)])
        XCTAssertEqual(twoSources.claimResults.map(\.claim), ["Both apply."])
    }

    /// A heading among an answer's first six sentences doesn't cost one of the six claims (second review, 2026-10-18).
    func testAHeadingDoesNotTakeOneOfTheSixClaims() {
        let sentences = [
            "The studio has one window facing east.", "The one-bedroom has two windows facing south.",
            "The two-bedroom has a balcony facing west.", "Every unit has a gas range and a dishwasher.",
            "Laundry machines are in the basement of each building.", "Parking spaces are assigned by the office.",
        ]
        let answer = StructuredAnswer.from(
            response: "**Room Types**\n" + sentences.joined(separator: " "),
            retrievedChunks: [leaseChunk(sentences.joined(separator: " "))], answerIntent: .lookup,
            verificationResult: nil, structuredGeneration: nil)
        XCTAssertEqual(answer.claims.map(\.claim), sentences)
    }

    /// When the model lists only its heading as a claim, Fact Check lists the answer's own sentences, which are what Gate
    /// B checks then (second review, 2026-10-18).
    func testATitleOnlyClaimListShowsTheAnswersSentences() {
        let generation = structured(
            "**Notice to Enter**\n- The landlord must give at least 24 hours' notice [S1].", [("Notice to Enter", [])])
        let answer = StructuredAnswer.from(
            response: generation.answer, retrievedChunks: [leaseChunk("Landlord will give at least 24 hours' notice before entering.")],
            answerIntent: .lookup, verificationResult: nil, structuredGeneration: generation)
        XCTAssertEqual(answer.claims.map(\.claim), ["The landlord must give at least 24 hours' notice."])
        // The sentence keeps the source it cites, so it is not reported as missing a citation (third review).
        XCTAssertFalse(answer.missing.contains { $0.hasPrefix("Claim missing citation") }, "\(answer.missing)")
    }

    /// The source-only answer is rebuilt from its claims without the headings of the model's draft, which the rebuilt
    /// answer no longer has, unless every claim is one (second review, 2026-10-18).
    @MainActor
    func testTheSourceOnlyAnswerLeavesOutTheDraftsHeadings() {
        func claim(_ text: String) -> SourceOnlyVerifiedClaim {
            SourceOnlyVerifiedClaim(
                claimId: text, claimText: text, verdict: .supported, evidenceLabels: ["S1"], evidenceIds: [],
                evidenceQuote: "", fidelity: 0.9, notes: nil, isCritical: false)
        }
        let draft = "**Notice to Enter**\n- The landlord must give at least 24 hours' notice [S1]."
        let claims = [claim("Notice to Enter"), claim("The landlord must give at least 24 hours' notice.")]
        XCTAssertEqual(
            SourceOnlyAnswerService.claimsToList(claims, candidateAnswer: draft).map(\.claimText),
            ["The landlord must give at least 24 hours' notice."])
        XCTAssertEqual(
            SourceOnlyAnswerService.claimsToList([claim("Notice to Enter")], candidateAnswer: "**Notice to Enter**").map(\.claimText),
            ["Notice to Enter"])
    }

    /// A heading that carries a citation is still a heading, on both sides: Gate B and the claim list match the same
    /// way, so a heading claim with a citation is neither checked nor listed (review, 2026-10-18).
    func testAHeadingWithACitationIsStillAHeading() {
        let answer = "## Notice to Enter [S1]\n- The landlord must give at least 24 hours' notice [S1]."
        let headings = VerificationGateService.headingLines(in: answer)
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Notice to Enter [S1]")))
        XCTAssertEqual(VerificationGateService.headingKey("Notice to Enter [S1]"), VerificationGateService.headingKey("Notice to Enter"))
        let generation = structured(answer, [
            ("Notice to Enter [S1]", ["S1"]), ("The landlord must give at least 24 hours' notice [S1].", ["S1"]),
        ])
        XCTAssertEqual(
            claims(of: generation, chunk: "Landlord will give at least 24 hours' notice before entering."),
            ["The landlord must give at least 24 hours' notice."])
    }

    /// When every claim is a heading, the claims stay: an answer is never left with none, which with the checks on
    /// would turn it into a refusal (review, 2026-10-18).
    func testWhenEveryClaimIsAHeadingTheClaimsStay() {
        let generation = structured("**Notice to Enter**", [("Notice to Enter", [])])
        XCTAssertEqual(claims(of: generation, chunk: "13. Entry by Landlord."), ["Notice to Enter"])
    }

    /// What a removed citation leaves behind is tidied, and nothing else is touched (review, 2026-10-18).
    func testWhatARemovedCitationLeavesBehindIsTidied() {
        let generation = structured("Check-out is at 11:00 a.m. [S2].", [
            ("Check-out is at 11:00 a.m. [S2].", ["S2"]),
            ("Rent is due on the 5th [S1], [S2].", ["S1", "S2"]),
            ("See the lease (section 13 [S1]).", ["S1"]),
            ("It costs $75.50 [S1].", ["S1"]),
            ("Wait for the next step... [S3]", ["S3"]),
        ])
        XCTAssertEqual(
            claims(of: generation, chunk: "Check-out is at 11:00 a.m. Rent is due on the 5th. It costs $75.50."),
            ["Check-out is at 11:00 a.m.", "Rent is due on the 5th.", "See the lease (section 13).", "It costs $75.50.",
             "Wait for the next step..."])
    }

    /// A run of citations goes, and nothing else in the claim is touched: two dots between numbers stay, and a comma
    /// after a citation stays where it was (second review, 2026-10-18).
    func testACitationRunGoesAndNothingElseIsTouched() {
        let generation = structured("Ports 8000..8100 are open [S1].", [
            ("Ports 8000..8100 are open [S1].", ["S1"]),
            ("The fee [S1], and the deposit [S2], are due on the 1st.", ["S1", "S2"]),
            ("Both apply [S1, S2].", ["S1", "S2"]),
            ("The lease ends in May [S1][S2].", ["S1", "S2"]),
            ("The deposit is refundable, [S1].", ["S1"]),
            ("The fee is $50 [S1]\u{2014}the deposit is $400 [S2].", ["S1", "S2"]),
        ])
        XCTAssertEqual(
            claims(of: generation, chunk: "Ports 8000..8100 are open. The fee and the deposit are due on the 1st."),
            ["Ports 8000..8100 are open.", "The fee, and the deposit, are due on the 1st.", "Both apply.",
             "The lease ends in May.", "The deposit is refundable.", "The fee is $50\u{2014}the deposit is $400."])
    }

    /// A bold that ends in an abbreviation keeps one full stop, with a citation after it or without, and a claim cut
    /// out of a bold phrase loses the marker it kept (demo copy of 3a9fcb8 in the iOS 27 Simulator, 2026-10-20): Fact
    /// Check read "Attendance reports must be submitted by 9:00 a.m.." and "The action is to **Unplug.".
    func testABoldAbbreviationKeepsOneFullStopAndACutBoldLosesItsMarker() {
        let generation = structured("Attendance reports must be submitted by **9:00 a.m.** [S9].", [
            ("Attendance reports must be submitted by **9:00 a.m.** [S9].", ["S9"]),
            ("Bring the form by **9:00 a.m.**.", ["S9"]),
            ("The action is to **Unplug.", ["S13"]),
            ("**E1** means **Temperature sensor open circuit** [S13].", ["S13"]),
            ("Reports are due by *9:00 a.m.* [S9].", ["S9"]),
            ("The setting is 2**10 bytes [S2].", ["S2"]),
        ])
        XCTAssertEqual(
            claims(of: generation, chunk: "Reports by 9:00 a.m. E1 Temperature sensor open circuit. Unplug."),
            ["Attendance reports must be submitted by **9:00 a.m.**", "Bring the form by **9:00 a.m.**",
             "The action is to Unplug.", "**E1** means **Temperature sensor open circuit**.",
             "Reports are due by *9:00 a.m.*", "The setting is 2**10 bytes."])
    }

    /// The same answer read sentence by sentence, as one that comes without the model's claim list is: the sentence
    /// cut inside the bold phrase is listed without its marker, and none ends in two full stops.
    func testAPlainAnswerCutInsideABoldPhraseShowsNoMarker() {
        let response = "**E1** means **Temperature sensor open circuit** [S13]. The action is to **Unplug. Contact "
            + "Kestrel support; the unit needs service.** [S13]. Reports are due by **9:00 a.m.** [S9]."
        let claims = StructuredAnswer.from(
            response: response,
            retrievedChunks: [leaseChunk("E1 Temperature sensor open circuit. Unplug. Contact Kestrel support.")],
            answerIntent: .lookup, verificationResult: nil, structuredGeneration: nil
        ).claims.map(\.claim)
        XCTAssertTrue(claims.contains("The action is to Unplug."), "\(claims)")
        XCTAssertTrue(claims.contains("Reports are due by **9:00 a.m.**"), "\(claims)")
        XCTAssertFalse(claims.contains { $0.components(separatedBy: "**").count % 2 == 0 }, "\(claims)")
        XCTAssertFalse(claims.contains { $0.contains("..") }, "\(claims)")
        let whole = "**E1** means **open circuit**"
        XCTAssertEqual(StructuredAnswer.withoutUnpairedBold(whole), whole)
    }

    /// A range of citations goes with the word that led to it (5.7): Fact Check read "...are present in through." for
    /// "...are present in [S1] through [S15]." (demo copy of 3a9fcb8, 2026-10-20).
    func testACitationRangeGoesWithTheWordThatLedToIt() {
        let generation = structured("No details about painting are present in [S1] through [S15].", [
            ("No details about painting are present in [S1] through [S15].", ["S1", "S15"]),
            ("Check-out is by 11:00 a.m. [S1] to [S3].", ["S1", "S3"]),
            ("The fees are listed in [S2]\u{2013}[S4].", ["S2", "S4"]),
            ("Pay the deposit before move-in [S1] through [S3].", ["S1", "S3"]),
            ("Both are listed in [S1, S2] through [S5].", ["S1", "S5"]),
            ("See the fee schedule (in [S2]\u{2013}[S4]).", ["S2", "S4"]),
        ])
        XCTAssertEqual(
            claims(of: generation, chunk: "Check-out is by 11:00 a.m. The fees are listed below."),
            ["No details about painting are present.", "Check-out is by 11:00 a.m.", "The fees are listed.",
             "Pay the deposit before move-in.", "Both are listed.", "See the fee schedule."])
    }

    /// Gate B and Fact Check read a range of citations the same way, so the claim keeps its verdict (review,
    /// 2026-10-20): with the range read on Fact Check's side alone, the claim's key no longer matched Gate B's and the
    /// claim showed "Not checked".
    @MainActor
    func testAClaimWithACitationRangeKeepsItsVerdict() async {
        let claim = "The late fee is $75.00, charged on the 6th, as set out in [S1] through [S2]."
        let chunk = leaseChunk("The late fee is $75.00, charged on the 6th day of the month.")
        let verification = await VerificationGateService().verify(
            response: claim, query: "What is the late fee?", retrievedChunks: [chunk], topScores: [0.9],
            structuredClaims: [StructuredRAGClaim(claim: claim, citations: ["S1", "S2"], isExtracted: true)])
        let answer = StructuredAnswer.from(
            response: claim, retrievedChunks: [chunk], answerIntent: .lookup, verificationResult: verification,
            structuredGeneration: structured(claim, [(claim, ["S1", "S2"])]))
        let checked = answer.claims.first { $0.claim.hasPrefix("The late fee is") }
        XCTAssertEqual(checked?.claim, "The late fee is $75.00, charged on the 6th, as set out.")
        XCTAssertNotNil(checked?.verificationVerdict, "\(verification.claimResults.map(\.claim))")
    }

    /// Information Gaps quotes a long claim up to its last whole word, with an ellipsis (5.7): the cut at 72
    /// characters read "...about painting a bedroo" (demo copy of 3a9fcb8, 2026-10-20).
    func testAGapQuotesALongClaimToItsLastWholeWord() {
        XCTAssertEqual(
            StructuredAnswer.gapQuote("The provided excerpts do not contain information about painting a bedroom."),
            "The provided excerpts do not contain information about painting a\u{2026}")
        XCTAssertEqual(StructuredAnswer.gapQuote("Rent is late."), "Rent is late.")
        let word = String(repeating: "x", count: 69)
        XCTAssertEqual(StructuredAnswer.gapQuote("ab " + word + " tail"), "ab " + word + "\u{2026}")
        // Gate B's own text for a claim it could not support is quoted tidied and without bold (review, 2026-10-20).
        XCTAssertEqual(StructuredAnswer.gapQuote("Reports are due by **9:00 a.m.** [S9]."), "Reports are due by 9:00 a.m.")
        XCTAssertEqual(StructuredAnswer.gapQuote("The action is to **Unplug."), "The action is to Unplug.")
    }

    /// The answer rebuilt from its checked claims keeps an abbreviation's full stop before the citation:
    /// "11:00 a.m. [S1].", not "11:00 a.m [S1]." (review, 2026-10-18).
    func testTheRebuiltAnswerKeepsAnAbbreviationsFullStop() {
        XCTAssertTrue(StructuredAnswer.endsWithAbbreviation("Check-out is at 11:00 a.m."))
        XCTAssertTrue(StructuredAnswer.endsWithAbbreviation("Bring a photo ID, a lease, etc."))
        XCTAssertFalse(StructuredAnswer.endsWithAbbreviation("It costs $75.50."))
        XCTAssertFalse(StructuredAnswer.endsWithAbbreviation("Rent is due on the 5th."))
        let claim = "Check-out is at 11:00 a.m."
        let verification = RAGVerificationResult(
            passed: true,
            gateResults: [.init(gate: .evidenceCoverage, passed: true, confidence: 1, details: "")],
            claimResults: [.init(claim: claim, verdict: .supported, confidence: 0.9, details: "", citations: ["S1"], resolvedEvidenceIds: [])],
            overallConfidence: 0.9, shouldAbstain: false, abstainReason: nil)
        let generation = structured("Check-out is at 11:00 a.m. [S1].", [("Check-out is at 11:00 a.m. [S1].", ["S1"])])
        let answer = StructuredAnswer.from(
            response: generation.answer, retrievedChunks: [leaseChunk("Check-out is at 11:00 a.m. on the last day.")],
            answerIntent: .lookup, verificationResult: verification, structuredGeneration: generation)
        XCTAssertFalse(answer.refuse)
        XCTAssertFalse(answer.answer.contains("a.m ["), answer.answer)
        XCTAssertFalse(answer.answer.contains("a.m.."), answer.answer)
    }

    /// Without structured claims, a bold sentence with a time in it is a claim the checks can support (review,
    /// 2026-10-18): it is not taken for a heading, so the answer is not refused for having no claims.
    func testABoldSentenceInAPlainAnswerIsKept() {
        let verification = RAGVerificationResult(
            passed: true,
            gateResults: [.init(gate: .evidenceCoverage, passed: true, confidence: 1, details: "")],
            claimResults: [.init(claim: "Check-out is at 11:00 a.m.", verdict: .supported, confidence: 0.9, details: "", citations: [], resolvedEvidenceIds: [])],
            overallConfidence: 0.9, shouldAbstain: false, abstainReason: nil)
        let answer = StructuredAnswer.from(
            response: "**Check-out is at 11:00 a.m.**", retrievedChunks: [leaseChunk("Check-out is at 11:00 a.m.")],
            answerIntent: .lookup, verificationResult: verification, structuredGeneration: nil, allowUngroundedFallback: false)
        XCTAssertFalse(answer.refuse)
        XCTAssertEqual(answer.claims.count, 1)
    }

    /// A number that starts with its decimal point keeps the space in front of it.
    func testADecimalAfterASpaceKeepsItsSpace() {
        let generation = StructuredRAGGeneration(
            reasoning: nil,
            answer: "The late fee is .5 percent of the rent [S1].",
            confidence: 90,
            citations: ["S1"],
            matchedTerms: [],
            claims: [StructuredRAGClaim(claim: "The late fee is .5 percent of the rent [S1].", citations: ["S1"], isExtracted: true)])
        let answer = StructuredAnswer.from(
            response: generation.answer,
            retrievedChunks: [leaseChunk("The late fee is .5 percent of the rent.")],
            answerIntent: .lookup,
            verificationResult: nil,
            structuredGeneration: generation)
        XCTAssertEqual(answer.claims.map(\.claim), ["The late fee is .5 percent of the rent."])
    }
}
