import CodexBarCore
import Foundation
import SwiftUI

public struct DeepSeekPriceClockPresentation: Equatable, Sendable {
    public struct WindowRow: Equatable, Identifiable, Sendable {
        public let id: String
        public let isPeak: Bool
        public let tagText: String
        public let timeRangeText: String
        public let durationText: String
        public let isCurrent: Bool

        public init(
            id: String,
            isPeak: Bool,
            tagText: String,
            timeRangeText: String,
            durationText: String,
            isCurrent: Bool)
        {
            self.id = id
            self.isPeak = isPeak
            self.tagText = tagText
            self.timeRangeText = timeRangeText
            self.durationText = durationText
            self.isCurrent = isCurrent
        }
    }

    public struct Segment: Equatable, Identifiable, Sendable {
        public let id: Int
        public let startFraction: Double
        public let endFraction: Double
        public let isPeak: Bool

        public init(id: Int, startFraction: Double, endFraction: Double, isPeak: Bool) {
            self.id = id
            self.startFraction = startFraction
            self.endFraction = endFraction
            self.isPeak = isPeak
        }
    }

    public let isPeak: Bool
    public let statusBadgeText: String
    public let countdownDigitsText: String
    public let countdownSuffixText: String
    public let nextTransitionText: String
    public let windowsTitle: String
    public let windows: [WindowRow]
    public let daySegments: [Segment]
    public let currentDayFraction: Double
    public let timeZoneName: String
    public let gmtOffsetDescription: String
    public let isUTC: Bool

    public static func make(
        at now: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent,
        isUTC: Bool = false) -> DeepSeekPriceClockPresentation
    {
        let effectiveTimeZone = isUTC ? (TimeZone(identifier: "UTC") ?? timeZone) : timeZone
        let status = DeepSeekPriceSchedule.status(at: now)

        let isPeak = status.isPeak
        let badgeText = isPeak ? L("PEAK PRICING") : L("OFF-PEAK PRICING (50% OFF)")

        let totalSeconds = max(0, Int(status.timeRemainingInCurrentWindow))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let countdownDigits = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        let countdownSuffix = L("left")

        let nextType = status.nextWindow.tier.isPeak ? L("Peak") : L("Off-peak")
        let timeFormatter = DateFormatter()
        timeFormatter.timeZone = effectiveTimeZone
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        let nextTimeStr = timeFormatter.string(from: status.nextWindow.start)
        let tzAbbr = effectiveTimeZone.abbreviation(for: status.nextWindow.start) ?? ""
        let nextTransition = String(format: L("→ %@ starts %@ %@"), nextType, nextTimeStr, tzAbbr)
            .trimmingCharacters(in: .whitespaces)

        let windowsTitle = isUTC ? L("PRICE WINDOWS · UTC") : L("PRICE WINDOWS · YOUR TIME")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = effectiveTimeZone

        var allWindows = [status.currentWindow]
        allWindows.append(contentsOf: status.upcomingWindows.prefix(3))

        let windowRows = allWindows.enumerated().map { index, window in
            let isCurrent = index == 0
            let isWindowPeak = window.tier.isPeak
            let tag = isWindowPeak ? L("Peak") : L("Off-peak")

            let timeRange: String
            let isSameDay = calendar.isDate(window.start, inSameDayAs: window.end)
            if isSameDay {
                let startStr = timeFormatter.string(from: window.start)
                let endStr = timeFormatter.string(from: window.end)
                timeRange = "\(startStr) — \(endStr)"
            } else {
                let dayFormatter = DateFormatter()
                dayFormatter.timeZone = effectiveTimeZone
                dayFormatter.locale = Locale(identifier: "en_US_POSIX")
                dayFormatter.dateFormat = "E HH:mm"
                let startStr = dayFormatter.string(from: window.start)
                let endStr = dayFormatter.string(from: window.end)
                timeRange = "\(startStr) — \(endStr)"
            }

            let durationStr: String
            if isCurrent {
                let remH = totalSeconds / 3600
                let remM = (totalSeconds % 3600) / 60
                durationStr = String(format: L("now · %dh %02dm left"), remH, remM)
            } else {
                let hoursDuration = max(1, Int(round(window.duration / 3600.0)))
                durationStr = "\(hoursDuration)h"
            }

            return WindowRow(
                id: "\(index)-\(window.start.timeIntervalSince1970)",
                isPeak: isWindowPeak,
                tagText: tag,
                timeRangeText: timeRange,
                durationText: durationStr,
                isCurrent: isCurrent)
        }

        let rawSegments = DeepSeekPriceSchedule.daySegments(for: now, timeZone: effectiveTimeZone)
        let segments = rawSegments.enumerated().map { index, seg in
            Segment(
                id: index,
                startFraction: seg.startFraction,
                endFraction: seg.endFraction,
                isPeak: seg.tier.isPeak)
        }

        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
        let dayDuration = max(1.0, endOfDay.timeIntervalSince(startOfDay))
        let elapsed = now.timeIntervalSince(startOfDay)
        let dayFraction = min(1.0, max(0.0, elapsed / dayDuration))

        let timeZoneName = isUTC ? "UTC" : (effectiveTimeZone.identifier)
        let secondsFromGMT = effectiveTimeZone.secondsFromGMT(for: now)
        let hoursOffset = secondsFromGMT / 3600
        let gmtOffset = hoursOffset == 0 ? "GMT" : String(format: "GMT%+d", hoursOffset)

        return DeepSeekPriceClockPresentation(
            isPeak: isPeak,
            statusBadgeText: badgeText,
            countdownDigitsText: countdownDigits,
            countdownSuffixText: countdownSuffix,
            nextTransitionText: nextTransition,
            windowsTitle: windowsTitle,
            windows: windowRows,
            daySegments: segments,
            currentDayFraction: dayFraction,
            timeZoneName: timeZoneName,
            gmtOffsetDescription: gmtOffset,
            isUTC: isUTC)
    }
}
