import Foundation

/// Pricing tier for DeepSeek API requests.
///
/// DeepSeek provides a 50% discount during off-peak hours on standard API pricing.
public enum DeepSeekPricingTier: String, Codable, Sendable, Equatable {
    case peak
    case offPeak

    public var isPeak: Bool {
        self == .peak
    }

    public var discountPercent: Int {
        self == .offPeak ? 50 : 0
    }
}

/// A discrete window of time where a specific DeepSeek pricing tier applies.
public struct DeepSeekPriceWindow: Sendable, Equatable {
    public let tier: DeepSeekPricingTier
    public let start: Date
    public let end: Date

    public init(tier: DeepSeekPricingTier, start: Date, end: Date) {
        self.tier = tier
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        self.end.timeIntervalSince(self.start)
    }

    public func timeRemaining(at date: Date) -> TimeInterval {
        max(0, self.end.timeIntervalSince(date))
    }

    public func contains(_ date: Date) -> Bool {
        date >= self.start && date < self.end
    }
}

/// A slice of a 24-hour local day for timeline visualization.
public struct DeepSeekPriceDaySegment: Sendable, Equatable, Identifiable {
    public var id: String {
        "\(self.tier.rawValue)-\(self.startFraction)-\(self.endFraction)"
    }

    public let tier: DeepSeekPricingTier
    public let start: Date
    public let end: Date
    public let startFraction: Double
    public let endFraction: Double

    public init(
        tier: DeepSeekPricingTier,
        start: Date,
        end: Date,
        startFraction: Double,
        endFraction: Double)
    {
        self.tier = tier
        self.start = start
        self.end = end
        self.startFraction = startFraction
        self.endFraction = endFraction
    }
}

/// Comprehensive pricing schedule status at a specific moment in time.
public struct DeepSeekPriceStatus: Sendable, Equatable {
    public let timestamp: Date
    public let currentTier: DeepSeekPricingTier
    public let currentWindow: DeepSeekPriceWindow
    public let nextWindow: DeepSeekPriceWindow
    public let upcomingWindows: [DeepSeekPriceWindow]

    public init(
        timestamp: Date,
        currentTier: DeepSeekPricingTier,
        currentWindow: DeepSeekPriceWindow,
        nextWindow: DeepSeekPriceWindow,
        upcomingWindows: [DeepSeekPriceWindow])
    {
        self.timestamp = timestamp
        self.currentTier = currentTier
        self.currentWindow = currentWindow
        self.nextWindow = nextWindow
        self.upcomingWindows = upcomingWindows
    }

    public var isPeak: Bool {
        self.currentTier == .peak
    }

    public var timeRemainingInCurrentWindow: TimeInterval {
        self.currentWindow.timeRemaining(at: self.timestamp)
    }
}

/// Schedule calculator for DeepSeek peak and off-peak pricing windows.
///
/// Mirrors DeepSeek's published terms at `termsSourceURL` (the "Models & Pricing" page), last
/// checked against them on `termsLastVerifiedOn`. The vendor states its windows in Beijing time,
/// which is the fixed UTC+8 offset quoted below.
///
/// Schedule rules (fixed to UTC / Beijing time):
/// - Peak hours apply Monday through Friday in two daily windows:
///   - 01:00 to 04:00 UTC (3 hours) — 09:00 to 12:00 Beijing time
///   - 06:00 to 10:00 UTC (4 hours) — 14:00 to 18:00 Beijing time
/// - Off-peak applies all other times (off-peak rates are 50% of peak rates):
///   - Weekday intervals: 04:00–06:00 UTC (2h) and 10:00–01:00 UTC next day (15h).
///   - Weekends (Saturday and Sunday): Entire weekend is off-peak (from Friday 10:00 UTC
///     until Monday 01:00 UTC continuously).
///
/// Intentionally not modelled: DeepSeek also bills Chinese public holidays and adjusted make-up
/// workdays at off-peak rates, and it assigns the tier from the moment its server *receives* a
/// request rather than from a clock. Those gaps are surfaced to the user beside the clock, and
/// this schedule is display-only — it never re-prices or rewrites reported spend, so it must not
/// be used to compute a bill.
///
/// Maintenance contract: when DeepSeek changes these terms, update the windows in `transitions`,
/// set `termsLastVerifiedOn` to the date of the check, and refresh the table in `docs/deepseek.md`;
/// that document holds the full procedure. `DeepSeekPriceScheduleTests` fails until the code and
/// the published terms line up again.
public enum DeepSeekPriceSchedule {
    /// Authoritative terms this schedule mirrors. Any window below that this page contradicts is a bug.
    public static let termsSourceURL = "https://api-docs.deepseek.com/quick_start/pricing"

    /// UTC date (`yyyy-MM-dd`) on which the mirrored windows were last checked against
    /// `termsSourceURL`. Shown in the menu so users can judge how stale the schedule is.
    public static let termsLastVerifiedOn = "2026-09-24"

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// Determines if a given instant falls within peak pricing hours.
    public static func isPeak(at date: Date = Date()) -> Bool {
        self.status(at: date).isPeak
    }

    /// Returns the pricing tier at a given instant.
    public static func tier(at date: Date = Date()) -> DeepSeekPricingTier {
        self.status(at: date).currentTier
    }

    /// Computes the complete pricing status at the given instant.
    public static func status(
        at date: Date = Date(),
        calendar: Calendar? = nil) -> DeepSeekPriceStatus
    {
        let cal = calendar ?? self.utcCalendar
        let transitions = self.transitions(around: date, calendar: cal)

        // Find the active transition: the latest transition <= date
        guard let activeIndex = transitions.lastIndex(where: { $0.date <= date }),
              activeIndex + 1 < transitions.count
        else {
            // Fallback for extreme bounds: safe off-peak window
            let start = cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? date
            let current = DeepSeekPriceWindow(tier: .offPeak, start: start, end: end)
            let next = DeepSeekPriceWindow(tier: .peak, start: end, end: end.addingTimeInterval(3600))
            return DeepSeekPriceStatus(
                timestamp: date,
                currentTier: .offPeak,
                currentWindow: current,
                nextWindow: next,
                upcomingWindows: [next])
        }

        let currentTransition = transitions[activeIndex]
        let nextTransition = transitions[activeIndex + 1]

        let currentWindow = DeepSeekPriceWindow(
            tier: currentTransition.tier,
            start: currentTransition.date,
            end: nextTransition.date)

        let nextEnd = (activeIndex + 2 < transitions.count)
            ? transitions[activeIndex + 2].date
            : nextTransition.date.addingTimeInterval(3600)
        let nextWindow = DeepSeekPriceWindow(
            tier: nextTransition.tier,
            start: nextTransition.date,
            end: nextEnd)

        var upcoming: [DeepSeekPriceWindow] = []
        let maxUpcoming = min(transitions.count - 1, activeIndex + 5)
        if activeIndex + 1 < maxUpcoming {
            for i in (activeIndex + 1)..<maxUpcoming {
                let windowStart = transitions[i].date
                let windowEnd = transitions[i + 1].date
                upcoming.append(DeepSeekPriceWindow(
                    tier: transitions[i].tier,
                    start: windowStart,
                    end: windowEnd))
            }
        }

        return DeepSeekPriceStatus(
            timestamp: date,
            currentTier: currentWindow.tier,
            currentWindow: currentWindow,
            nextWindow: nextWindow,
            upcomingWindows: upcoming)
    }

    /// Computes the day segments for a 24-hour visual progress bar in a given timezone.
    public static func daySegments(
        for date: Date = Date(),
        timeZone: TimeZone = .current) -> [DeepSeekPriceDaySegment]
    {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.locale = Locale(identifier: "en_US_POSIX")
        localCalendar.timeZone = timeZone

        let dayStart = localCalendar.startOfDay(for: date)
        guard let dayEnd = localCalendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        let dayDuration = dayEnd.timeIntervalSince(dayStart)
        guard dayDuration > 0 else { return [] }

        // Fetch transitions covering the local 24-hour range
        let allTransitions = self.transitions(around: date, calendar: self.utcCalendar)

        // Find boundary instants inside [dayStart, dayEnd]
        var cutPoints: [Date] = [dayStart]
        for transition in allTransitions {
            if transition.date > dayStart, transition.date < dayEnd {
                cutPoints.append(transition.date)
            }
        }
        cutPoints.append(dayEnd)
        cutPoints.sort()

        var segments: [DeepSeekPriceDaySegment] = []
        for i in 0..<(cutPoints.count - 1) {
            let start = cutPoints[i]
            let end = cutPoints[i + 1]
            guard end > start else { continue }

            // Sample midpoint to determine tier
            let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            let tier = self.status(at: midpoint, calendar: self.utcCalendar).currentTier

            let startFraction = max(0, min(1, start.timeIntervalSince(dayStart) / dayDuration))
            let endFraction = max(0, min(1, end.timeIntervalSince(dayStart) / dayDuration))

            segments.append(DeepSeekPriceDaySegment(
                tier: tier,
                start: start,
                end: end,
                startFraction: startFraction,
                endFraction: endFraction))
        }

        return segments
    }

    // MARK: - Internal Transition Generation

    private struct Transition: Sendable {
        let date: Date
        let tier: DeepSeekPricingTier
    }

    private static func transitions(around date: Date, calendar: Calendar) -> [Transition] {
        var cal = calendar
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let anchorDay = cal.startOfDay(for: date)
        guard let scanStart = cal.date(byAdding: .day, value: -8, to: anchorDay),
              let scanEnd = cal.date(byAdding: .day, value: 9, to: anchorDay)
        else {
            return []
        }

        var results: [Transition] = []
        var currentDay = scanStart

        while currentDay <= scanEnd {
            let weekday = cal.component(.weekday, from: currentDay)
            // In Gregorian calendar: 1 = Sunday, 2 = Monday, ..., 6 = Friday, 7 = Saturday
            let isWeekday = weekday >= 2 && weekday <= 6

            if isWeekday {
                if let peak1Start = cal.date(bySettingHour: 1, minute: 0, second: 0, of: currentDay),
                   let peak1End = cal.date(bySettingHour: 4, minute: 0, second: 0, of: currentDay),
                   let peak2Start = cal.date(bySettingHour: 6, minute: 0, second: 0, of: currentDay),
                   let peak2End = cal.date(bySettingHour: 10, minute: 0, second: 0, of: currentDay)
                {
                    results.append(Transition(date: peak1Start, tier: .peak))
                    results.append(Transition(date: peak1End, tier: .offPeak))
                    results.append(Transition(date: peak2Start, tier: .peak))
                    results.append(Transition(date: peak2End, tier: .offPeak))
                }
            }

            guard let nextDay = cal.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }

        results.sort { $0.date < $1.date }

        // Deduplicate adjacent transitions with same tier
        var deduplicated: [Transition] = []
        for transition in results {
            if let last = deduplicated.last, last.tier == transition.tier {
                continue
            }
            deduplicated.append(transition)
        }

        return deduplicated
    }
}
