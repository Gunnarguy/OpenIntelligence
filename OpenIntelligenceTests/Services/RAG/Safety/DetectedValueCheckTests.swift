//
//  DetectedValueCheckTests.swift
//  OpenIntelligenceTests
//
//  Amounts of money, dates and measurements are read with Apple's data detector and checked against the
//  passages (5.7, `DetectedValueCheck`): an amount the passages state only in another currency, a day of a month
//  the passages give other days of, or a value they state only with other units, is a contradiction. The cases
//  are the ones measured on macOS 27 on 2026-10-15. Not covered: an answer on a device.
//

import XCTest

@testable import OpenIntelligence

final class DetectedValueCheckTests: XCTestCase {
    private func contradictions(_ answer: String, against passage: String) async -> [DetectedValueCheck.Contradiction] {
        let evidence = await DetectedValueCheck.evidence(from: [passage])
        return await DetectedValueCheck.contradictions(in: answer, evidence: evidence)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> String {
        DetectedValueCheck.describe(DetectedValueCheck.Day(year: year, month: month, day: day))
    }

    private func money(_ amount: Decimal, _ currency: String) -> String {
        DetectedValueCheck.describe(DetectedValueCheck.Money(amount: amount, currency: currency))
    }

    func testAnAmountInAnotherCurrencyIsContradicted() async {
        let found = await contradictions("The deposit is €1,200.", against: "The deposit is $1,200.")
        XCTAssertEqual(found, [.init(written: money(1200, "EUR"), stated: money(1200, "USD"))])
    }

    func testTheSameAmountWrittenAnotherWayStands() async {
        let found = await contradictions("The deposit is 1,200 dollars.", against: "The deposit is $1,200.")
        XCTAssertEqual(found, [])
    }

    func testAnAmountThePassagesDoNotStateAsMoneyIsLeftToTheNumberCheck() async {
        // The detector reads no money in a table's "(USD): 1200".
        let found = await contradictions("The deposit is €1,200.", against: "Deposit (USD): 1200.")
        XCTAssertEqual(found, [])
    }

    func testAnotherDayOfTheSameMonthIsContradicted() async {
        let found = await contradictions("The lease starts March 15, 2024.", against: "The lease starts March 5, 2024.")
        XCTAssertEqual(found, [.init(written: day(2024, 3, 15), stated: day(2024, 3, 5))])
    }

    func testTheSameDayWrittenAnotherWayStands() async {
        let found = await contradictions("The lease starts on 2024-03-05.", against: "The lease starts March 5, 2024.")
        XCTAssertEqual(found, [])
    }

    func testADayInAMonthThePassagesDoNotGiveIsLeftAlone() async {
        let found = await contradictions("Rent is due April 4, 2024.", against: "The lease starts March 5, 2024.")
        XCTAssertEqual(found, [])
    }

    func testADateWithoutAYearIsNotRead() async {
        // The detector makes these dates relative to today.
        let found = await contradictions("Pay by next Monday or the 5th of March.", against: "The lease starts March 5, 2024.")
        XCTAssertEqual(found, [])
    }

    func testBothEndsOfARangeAreDays() async {
        let found = await contradictions(
            "It ends March 10, 2024.", against: "The lease runs from March 5, 2024 to March 10, 2024.")
        XCTAssertEqual(found, [])
    }

    func testADeadlineWrittenTheEuropeanWayIsRead() async {
        let passage = "Payment of 1.200,50 EUR is due 15.03.2024."
        let right = await contradictions("Pay €1,200.50 by March 15, 2024.", against: passage)
        XCTAssertEqual(right, [])
        let wrong = await contradictions("Pay $1,200.50 by March 16, 2024.", against: passage)
        XCTAssertEqual(
            wrong,
            [
                .init(written: money(Decimal(string: "1200.5")!, "USD"), stated: money(Decimal(string: "1200.5")!, "EUR")),
                .init(written: day(2024, 3, 16), stated: day(2024, 3, 15)),
            ])
    }

    func testAValueWithAnotherUnitIsContradicted() async {
        let passage = "Inflate the front tires to 35 psi and the rear to 32 psi."
        let wrong = await contradictions("Set the front tires to 35 kPa.", against: passage)
        XCTAssertEqual(
            wrong,
            [
                .init(
                    written: DetectedValueCheck.describe(.init(value: 35, units: ["kPa"])),
                    stated: DetectedValueCheck.describe(.init(value: 35, units: ["psi"])))
            ])
        let right = await contradictions("Set the front tires to 35 psi.", against: passage)
        XCTAssertEqual(right, [])
    }

    func testTheSameValueAndUnitWrittenAnotherWayStands() async {
        let found = await contradictions("It holds about 68 L.", against: "The tank holds 18 gallons, about 68 liters.")
        XCTAssertEqual(found, [])
    }

    func testAValueWhoseUnitIsNotReadIsLeftToTheNumberCheck() async {
        // The detector reads no unit in "5 mg".
        let found = await contradictions("Take 5 kg twice a day.", against: "Take 5 mg twice a day.")
        XCTAssertEqual(found, [])
    }

    func testYearsAreRunsOfFourDigits() {
        XCTAssertEqual(DetectedValueCheck.writtenYears(in: "due 15.03.2024"), [2024])
        XCTAssertEqual(DetectedValueCheck.writtenYears(in: "from December 30, 2024 to January 2, 2025"), [2024, 2025])
        XCTAssertEqual(DetectedValueCheck.writtenYears(in: "the 5th of March, page 12345"), [])
    }
}
