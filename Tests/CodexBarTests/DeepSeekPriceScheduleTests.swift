import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct DeepSeekPriceScheduleTests {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func makeDate(
        year: Int = 2026,
        month: Int = 9,
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0) -> Date
    {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Self.utcCalendar.date(from: components)!
    }

    @Test
    func `reproduces screenshot Thursday morning peak window exactly`() {
        // Screenshot was taken on Thursday, Sep 24, 2026 at 08:44:29 CEST (06:44:29 UTC)
        let now = Self.makeDate(day: 24, hour: 6, minute: 44, second: 29)
        let status = DeepSeekPriceSchedule.status(at: now)

        #expect(status.isPeak)
        #expect(status.currentTier == .peak)

        // Peak window: 06:00 to 10:00 UTC (4 hours duration)
        #expect(status.currentWindow.duration == 4 * 3600)
        let expectedRemaining: TimeInterval = (3 * 3600) + (15 * 60) + 31
        #expect(abs(status.timeRemainingInCurrentWindow - expectedRemaining) < 1)

        // Next window is off-peak starting at 10:00 UTC (12:00 CEST)
        #expect(status.nextWindow.tier == .offPeak)
        #expect(status.nextWindow.start == Self.makeDate(day: 24, hour: 10))
        // And runs until Friday 01:00 UTC (15 hours duration)
        #expect(status.nextWindow.end == Self.makeDate(day: 25, hour: 1))
        #expect(status.nextWindow.duration == 15 * 3600)
    }

    @Test
    func `weekday off-peak between peak windows spans two hours`() {
        // Thursday 05:15 UTC is between peak 1 (01:00-04:00) and peak 2 (06:00-10:00)
        let now = Self.makeDate(day: 24, hour: 5, minute: 15)
        let status = DeepSeekPriceSchedule.status(at: now)

        #expect(!status.isPeak)
        #expect(status.currentTier == .offPeak)
        #expect(status.currentWindow.start == Self.makeDate(day: 24, hour: 4))
        #expect(status.currentWindow.end == Self.makeDate(day: 24, hour: 6))
        #expect(status.currentWindow.duration == 2 * 3600)
        #expect(status.timeRemainingInCurrentWindow == 45 * 60)

        // Next window is Peak 2
        #expect(status.nextWindow.tier == .peak)
        #expect(status.nextWindow.start == Self.makeDate(day: 24, hour: 6))
        #expect(status.nextWindow.end == Self.makeDate(day: 24, hour: 10))
    }

    @Test
    func `weekend is off-peak continuously from Friday 10:00 UTC to Monday 01:00 UTC`() {
        // Friday Sep 25, 2026 at 18:00 UTC (after Friday peak hours)
        let fridayNight = Self.makeDate(day: 25, hour: 18)
        let fridayStatus = DeepSeekPriceSchedule.status(at: fridayNight)

        #expect(!fridayStatus.isPeak)
        #expect(fridayStatus.currentTier == .offPeak)
        #expect(fridayStatus.currentWindow.start == Self.makeDate(day: 25, hour: 10))
        #expect(fridayStatus.currentWindow.end == Self.makeDate(day: 28, hour: 1)) // Monday Sep 28, 01:00 UTC
        #expect(fridayStatus.currentWindow.duration == 63 * 3600) // 14h Fri + 24h Sat + 24h Sun + 1h Mon = 63h

        // Saturday Sep 26, 2026 at 14:00 UTC
        let saturdayNoon = Self.makeDate(day: 26, hour: 14)
        let saturdayStatus = DeepSeekPriceSchedule.status(at: saturdayNoon)
        #expect(!saturdayStatus.isPeak)
        #expect(saturdayStatus.currentWindow.end == Self.makeDate(day: 28, hour: 1))

        // Sunday Sep 27, 2026 at 23:30 UTC
        let sundayNight = Self.makeDate(day: 27, hour: 23, minute: 30)
        let sundayStatus = DeepSeekPriceSchedule.status(at: sundayNight)
        #expect(!sundayStatus.isPeak)
        #expect(sundayStatus.timeRemainingInCurrentWindow == 90 * 60)
        #expect(sundayStatus.nextWindow.tier == .peak)
        #expect(sundayStatus.nextWindow.start == Self.makeDate(day: 28, hour: 1))
    }

    @Test
    func `Monday peak window starts at 01:00 UTC`() {
        // Monday Sep 28, 2026 at 02:00 UTC
        let mondayMorning = Self.makeDate(day: 28, hour: 2)
        let status = DeepSeekPriceSchedule.status(at: mondayMorning)

        #expect(status.isPeak)
        #expect(status.currentWindow.start == Self.makeDate(day: 28, hour: 1))
        #expect(status.currentWindow.end == Self.makeDate(day: 28, hour: 4))
        #expect(status.currentWindow.duration == 3 * 3600)
    }

    @Test
    func `peak windows match the published Beijing-time hours`() throws {
        // DeepSeek publishes peak hours as 09:00–12:00 and 14:00–18:00 Beijing time (UTC+8). Asserting
        // against the vendor's own clock is what pins the mirrored constants to the published terms.
        let beijing = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var beijingCalendar = Calendar(identifier: .gregorian)
        beijingCalendar.locale = Locale(identifier: "en_US_POSIX")
        beijingCalendar.timeZone = beijing

        // Thursday Sep 24, 2026 09:00 Beijing == 01:00 UTC: first peak block opens.
        let firstStart = Self.makeDate(day: 24, hour: 1)
        #expect(DeepSeekPriceSchedule.isPeak(at: firstStart))
        #expect(beijingCalendar.component(.hour, from: firstStart) == 9)
        #expect(DeepSeekPriceSchedule.status(at: firstStart).currentWindow.end == Self.makeDate(day: 24, hour: 4))

        // The lunch break between the blocks is off-peak.
        let lunchBreak = Self.makeDate(day: 24, hour: 5)
        #expect(beijingCalendar.component(.hour, from: lunchBreak) == 13)
        #expect(!DeepSeekPriceSchedule.isPeak(at: lunchBreak))

        // 14:00 Beijing == 06:00 UTC: second peak block opens, and closes at 18:00 Beijing == 10:00 UTC.
        let secondStart = Self.makeDate(day: 24, hour: 6)
        #expect(beijingCalendar.component(.hour, from: secondStart) == 14)
        let secondStatus = DeepSeekPriceSchedule.status(at: secondStart)
        #expect(secondStatus.isPeak)
        #expect(secondStatus.currentWindow.end == Self.makeDate(day: 24, hour: 10))
    }

    @Test
    func `schedule records the terms it mirrors`() {
        // The maintenance contract in docs/deepseek.md depends on these staying machine-readable.
        #expect(DeepSeekPriceSchedule.termsSourceURL.hasPrefix("https://"))
        #expect(DeepSeekPriceSchedule.termsLastVerifiedOn.count == 10)
        #expect(
            Self.utcCalendar.date(from: DateComponents(
                year: Int(DeepSeekPriceSchedule.termsLastVerifiedOn.prefix(4)),
                month: Int(DeepSeekPriceSchedule.termsLastVerifiedOn.dropFirst(5).prefix(2)),
                day: Int(DeepSeekPriceSchedule.termsLastVerifiedOn.suffix(2)))) != nil)
    }

    @Test
    func `day segments in local Vienna timezone match expected timeline slices`() throws {
        // Vienna is UTC+2 in September (CEST)
        let viennaTZ = try #require(TimeZone(identifier: "Europe/Vienna"))
        let date = Self.makeDate(day: 24, hour: 12) // Thursday
        let segments = DeepSeekPriceSchedule.daySegments(for: date, timeZone: viennaTZ)

        // In Vienna (UTC+2) on Thursday:
        // 00:00 - 03:00 (Wed 22:00 - Thu 01:00 UTC): off-peak
        // 03:00 - 06:00 (Thu 01:00 - 04:00 UTC): peak
        // 06:00 - 08:00 (Thu 04:00 - 06:00 UTC): off-peak
        // 08:00 - 12:00 (Thu 06:00 - 10:00 UTC): peak
        // 12:00 - 24:00 (Thu 10:00 - 22:00 UTC): off-peak
        #expect(segments.count == 5)
        #expect(segments[0].tier == .offPeak)
        #expect(abs(segments[0].startFraction - 0.0) < 0.001)
        #expect(abs(segments[0].endFraction - (3.0 / 24.0)) < 0.001)

        #expect(segments[1].tier == .peak)
        #expect(abs(segments[1].startFraction - (3.0 / 24.0)) < 0.001)
        #expect(abs(segments[1].endFraction - (6.0 / 24.0)) < 0.001)

        #expect(segments[2].tier == .offPeak)
        #expect(abs(segments[2].startFraction - (6.0 / 24.0)) < 0.001)
        #expect(abs(segments[2].endFraction - (8.0 / 24.0)) < 0.001)

        #expect(segments[3].tier == .peak)
        #expect(abs(segments[3].startFraction - (8.0 / 24.0)) < 0.001)
        #expect(abs(segments[3].endFraction - (12.0 / 24.0)) < 0.001)

        #expect(segments[4].tier == .offPeak)
        #expect(abs(segments[4].startFraction - (12.0 / 24.0)) < 0.001)
        #expect(abs(segments[4].endFraction - 1.0) < 0.001)
    }

    @Test
    func `day segments and needle handle daylight saving transition days`() throws {
        let viennaTZ = try #require(TimeZone(identifier: "Europe/Vienna"))
        var viennaCal = Calendar(identifier: .gregorian)
        viennaCal.timeZone = viennaTZ

        // Spring forward: Sunday, March 29, 2026 (23-hour day in Europe/Vienna)
        var springComps = DateComponents()
        springComps.year = 2026
        springComps.month = 3
        springComps.day = 29
        springComps.hour = 12 // noon
        let springNoon = try #require(viennaCal.date(from: springComps))

        let springSegments = DeepSeekPriceSchedule.daySegments(for: springNoon, timeZone: viennaTZ)
        #expect(!springSegments.isEmpty)
        #expect(abs(springSegments.first?.startFraction ?? 1.0) < 0.001)
        #expect(abs((springSegments.last?.endFraction ?? 0.0) - 1.0) < 0.001)

        let springStartOfDay = viennaCal.startOfDay(for: springNoon)
        let springEndOfDay = try #require(viennaCal.date(byAdding: .day, value: 1, to: springStartOfDay))
        let springDuration = springEndOfDay.timeIntervalSince(springStartOfDay)
        #expect(springDuration == 23 * 3600)

        let springPresentation = DeepSeekPriceClockPresentation.make(
            at: springNoon,
            timeZone: viennaTZ,
            isUTC: false)
        // Spring forward noon: elapsed is 11 hours (02:00-03:00 skipped), actual day duration is 23 hours
        let expectedSpringFraction = 11.0 / 23.0
        #expect(abs(springPresentation.currentDayFraction - expectedSpringFraction) < 0.001)

        // Fall back: Sunday, October 25, 2026 (25-hour day in Europe/Vienna)
        var fallComps = DateComponents()
        fallComps.year = 2026
        fallComps.month = 10
        fallComps.day = 25
        fallComps.hour = 12 // noon
        let fallNoon = try #require(viennaCal.date(from: fallComps))

        let fallSegments = DeepSeekPriceSchedule.daySegments(for: fallNoon, timeZone: viennaTZ)
        #expect(!fallSegments.isEmpty)
        #expect(abs(fallSegments.first?.startFraction ?? 1.0) < 0.001)
        #expect(abs((fallSegments.last?.endFraction ?? 0.0) - 1.0) < 0.001)

        let fallStartOfDay = viennaCal.startOfDay(for: fallNoon)
        let fallEndOfDay = try #require(viennaCal.date(byAdding: .day, value: 1, to: fallStartOfDay))
        let fallDuration = fallEndOfDay.timeIntervalSince(fallStartOfDay)
        #expect(fallDuration == 25 * 3600)

        let fallPresentation = DeepSeekPriceClockPresentation.make(
            at: fallNoon,
            timeZone: viennaTZ,
            isUTC: false)
        // Fall back noon: elapsed is 13 hours (02:00 repeated), actual day duration is 25 hours
        let expectedFallFraction = 13.0 / 25.0
        #expect(abs(fallPresentation.currentDayFraction - expectedFallFraction) < 0.001)
    }
}
