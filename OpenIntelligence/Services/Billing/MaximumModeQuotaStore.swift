import Foundation

struct MaximumModeQuotaState: Sendable {
    let dayKey: String
    let usedCount: Int
    let dailyLimit: Int

    var remainingUses: Int {
        max(dailyLimit - usedCount, 0)
    }
}

final class MaximumModeQuotaStore {
    private let defaults: UserDefaults
    private var calendar: Calendar

    private enum Keys {
        static let dayKey = "entitlement.maximumMode.dayKey"
        static let usedCount = "entitlement.maximumMode.usedCount"
    }

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func currentState(limit: Int, now: Date = Date()) -> MaximumModeQuotaState {
        let activeDayKey = dayKey(for: now)
        let storedDayKey = defaults.string(forKey: Keys.dayKey)

        if storedDayKey != activeDayKey {
            defaults.set(activeDayKey, forKey: Keys.dayKey)
            defaults.set(0, forKey: Keys.usedCount)
            return MaximumModeQuotaState(dayKey: activeDayKey, usedCount: 0, dailyLimit: limit)
        }

        let storedCount = defaults.integer(forKey: Keys.usedCount)
        return MaximumModeQuotaState(
            dayKey: activeDayKey,
            usedCount: min(max(storedCount, 0), limit),
            dailyLimit: limit
        )
    }

    func consumeIfAllowed(limit: Int, now: Date = Date()) -> MaximumModeExecutionDecision {
        let state = currentState(limit: limit, now: now)
        guard state.remainingUses > 0 else {
            return .blocked(remaining: 0, dailyLimit: limit, resetsAt: nextResetDate(after: now))
        }

        let nextUsedCount = min(state.usedCount + 1, limit)
        defaults.set(state.dayKey, forKey: Keys.dayKey)
        defaults.set(nextUsedCount, forKey: Keys.usedCount)

        return .allowedMetered(remaining: max(limit - nextUsedCount, 0), dailyLimit: limit)
    }

    func nextResetDate(after date: Date = Date()) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
