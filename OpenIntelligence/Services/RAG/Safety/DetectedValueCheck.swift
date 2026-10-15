//
//  DetectedValueCheck.swift
//  OpenIntelligence
//
//  Amounts of money, dates and measurements, read with Apple's data detector, checked against the passages
//  an answer rests on (5.7).
//

import DataDetection
import Foundation

/// Reads the amounts of money, the dates and the measurements in an answer with Apple's data detector, and finds
/// the ones its passages contradict (5.7, catalogue row "Dates, money and measurements detector").
///
/// The number check compares values (`NumericValueExtractor`), so "€1,200" in an answer matched "$1,200" in a
/// passage, and "March 15, 2024" passed against "March 5, 2024" whenever a 15 stood anywhere else in the
/// passages, and "35 kPa" matched "35 psi". The detector reads what the numbers are: an amount with its
/// currency, a day, a value with its unit. Only a
/// contradiction the passages show is reported, because a passage can state a value in a form the detector does
/// not read: on macOS 27 it read no money in "Deposit (USD): 1200" (measured 2026-10-15). So:
/// - an amount counts as contradicted when the passages state it as money only in other currencies;
/// - a measurement counts as contradicted when the passages state its value only with other units. The
///   detector reads psi, kPa, kg, gallons, liters, °F, °C, m and mm, and no unit in "5 mg", "25 Nm", "120 V" or
///   "15 A" (measured on macOS 27 on 2026-10-15); a number it reads no unit for is left to the value check;
/// - a date counts as contradicted when the passages give other days of its month and never this one.
/// A date is read only when it is written with its year, because the detector makes "next Monday" and "the 5th
/// of March" dates relative to today; and it reads "05/03/2024" as May 3, so a date is compared only with the
/// days of its own month. A range or a deadline gives a start day, an end day or both ("from March 5, 2024 to
/// March 10, 2024", "due 15.03.2024"), and each is a day here.
nonisolated enum DetectedValueCheck {
    struct Money: Hashable, Sendable {
        let amount: Decimal
        /// ISO 4217: "USD", "EUR".
        let currency: String
    }

    struct Day: Hashable, Sendable {
        let year: Int
        let month: Int
        let day: Int
    }

    /// A value with the units the detector read for it: "m" can be meters or minutes, so both are kept.
    struct Quantity: Hashable, Sendable {
        let value: Double
        let units: Set<String>
    }

    /// The amounts of money, the days and the measurements the passages state.
    struct Evidence: Sendable {
        var money: Set<Money> = []
        var days: Set<Day> = []
        var quantities: Set<Quantity> = []

        var isEmpty: Bool { money.isEmpty && days.isEmpty && quantities.isEmpty }
    }

    /// A value an answer states that the passages contradict.
    struct Contradiction: Equatable, Sendable {
        /// The value as the answer has it: "€1,200.00", "March 15, 2024".
        let written: String
        /// What the passages state instead: "$1,200.00", "March 5, 2024".
        let stated: String
    }

    /// The most characters read from one answer or one passage.
    static let characterLimit = 20_000

    /// What `passages` state, read once for every sentence checked against them.
    @concurrent
    static func evidence(from passages: [String]) async -> Evidence {
        var evidence = Evidence()
        for passage in passages {
            for value in await values(in: passage) {
                switch value {
                case .money(let money): evidence.money.insert(money)
                case .day(let day): evidence.days.insert(day)
                case .quantity(let quantity): evidence.quantities.insert(quantity)
                }
            }
        }
        return evidence
    }

    /// The values in `text` that `evidence` contradicts, in the order they are written.
    @concurrent
    static func contradictions(in text: String, evidence: Evidence) async -> [Contradiction] {
        guard !evidence.isEmpty else { return [] }
        var found: [Contradiction] = []
        for value in await values(in: text) {
            switch value {
            case .money(let money):
                guard !evidence.money.contains(money),
                    let other = evidence.money
                        .filter({ $0.amount == money.amount })
                        .min(by: { $0.currency < $1.currency })
                else { continue }
                found.append(Contradiction(written: describe(money), stated: describe(other)))
            case .day(let day):
                guard !evidence.days.contains(day),
                    let other = evidence.days
                        .filter({ $0.year == day.year && $0.month == day.month })
                        .min(by: { abs($0.day - day.day) < abs($1.day - day.day) })
                else { continue }
                found.append(Contradiction(written: describe(day), stated: describe(other)))
            case .quantity(let quantity):
                let sameValue = evidence.quantities.filter { $0.value == quantity.value }
                guard !sameValue.contains(where: { !$0.units.isDisjoint(with: quantity.units) }),
                    let other = sameValue.min(by: { describe($0) < describe($1) })
                else { continue }
                found.append(Contradiction(written: describe(quantity), stated: describe(other)))
            }
        }
        return found
    }

    static func describe(_ money: Money) -> String {
        money.amount.formatted(.currency(code: money.currency))
    }

    static func describe(_ day: Day) -> String {
        let components = DateComponents(year: day.year, month: day.month, day: day.day)
        guard let date = Calendar.current.date(from: components) else {
            return "\(day.year)-\(day.month)-\(day.day)"
        }
        return date.formatted(date: .long, time: .omitted)
    }

    static func describe(_ quantity: Quantity) -> String {
        "\(quantity.value.formatted()) \(quantity.units.sorted().joined(separator: " or "))"
    }

    private enum Value {
        case money(Money)
        case day(Day)
        case quantity(Quantity)
    }

    private static func values(in text: String) async -> [Value] {
        let read = text.count > characterLimit ? String(text.prefix(characterLimit)) : text
        guard read.contains(where: \.isNumber) else { return [] }
        var values: [Value] = []
        for await match in read.dataDetectorMatches([.moneyAmount, .calendarEvent, .measurement]) {
            switch match.details {
            case .moneyAmount(let money):
                values.append(.money(Money(amount: money.amount, currency: money.currency.identifier)))
            case .calendarEvent(let event):
                // Only a date written with its year: one without is made relative to today.
                let written = match.range.map { String(read[$0]) } ?? ""
                let years = writtenYears(in: written)
                guard !years.isEmpty else { continue }
                // A start and an end on the same day are one day.
                var days: [Day] = []
                for date in [event.startDate, event.endDate].compactMap({ $0 }) {
                    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
                    guard let year = parts.year, years.contains(year), let month = parts.month, let day = parts.day
                    else { continue }
                    let read = Day(year: year, month: month, day: day)
                    if !days.contains(read) { days.append(read) }
                }
                values.append(contentsOf: days.map(Value.day))
            case .measurement(let measurement):
                // A bare number, with no unit read, is not a measurement here.
                let units = Set(measurement.possibleDimensions.map(\.symbol))
                guard !units.isEmpty else { continue }
                values.append(.quantity(Quantity(value: measurement.value, units: units)))
            default:
                continue
            }
        }
        return values
    }

    /// The years written in `text`: runs of exactly four digits, 1800 to 2199. A run of digits is read
    /// rather than a word, because "15.03.2024" is one word to Unicode's word boundaries.
    static func writtenYears(in text: String) -> Set<Int> {
        Set(
            text.split(whereSeparator: { !$0.isASCII || !$0.isNumber })
                .filter { $0.count == 4 }
                .compactMap { Int($0) }
                .filter { (1800...2199).contains($0) })
    }
}
