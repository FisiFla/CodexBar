import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Pins how DeepSeek lands in the shared spend dashboard.
///
/// Two properties need holding at once. Its day keys are vendor days, not the user's: the monthly
/// fallback labels buckets in UTC, so a UTC boundary must map into the containing local day. And its
/// per-model rows are assembled from two separate Platform endpoints (`/by_api_key/amount` and
/// `/by_api_key/cost`), so a retired or lagging model can carry tokens on a day whose cost bucket
/// never arrived — the day is still priced, only its per-model split is unprovable, which previously
/// dropped the provider's whole breakdown.
struct DeepSeekSpendDashboardModelTests {
    @Test
    func `DeepSeek partial per-day model costs keep named rows behind the partial warning`() throws {
        let deepSeek = try Self.group(for: .deepseek)

        // The rows stay visible, but the provider is still reported as partial rather than complete.
        #expect(deepSeek.modelHistoryCompleteness == .incomplete)
        #expect(deepSeek.incompleteModelProviders == [.deepseek])
        #expect(Set(deepSeek.models.map(\.modelName)) == [
            "deepseek-flash",
            "deepseek-v4-pro",
            "deepseek-v4.1-flash-expires-on-0910",
        ])
        // The row whose cost bucket never arrived keeps its tokens and reports no cost, so the list
        // cannot present a partial split as a priced total.
        let unpriced = try #require(deepSeek.models.first { $0.modelName.hasSuffix("expires-on-0910") })
        #expect(unpriced.totalCost == nil)
        #expect(deepSeek.models.filter { $0.modelName != unpriced.modelName }.allSatisfy { $0.totalCost != nil })
    }

    @Test
    func `retention stays scoped to DeepSeek so other vendor-metered sources still fail closed`() throws {
        // Same gap, same provenance, different provider: no allowance, so no rows.
        let other = try Self.group(for: .openrouter)

        #expect(other.modelHistoryCompleteness == .incomplete)
        #expect(other.models.isEmpty)
    }

    @Test
    func `malformed model tokens fail closed even for DeepSeek`() throws {
        // The allowance must not admit rows it cannot type: a negative token count keeps the
        // provider's rows withheld rather than publishing a partial list.
        let group = try Self.group(for: .deepseek, entries: [
            Self.entry(
                day: "2026-07-16",
                totalCost: 4,
                totalTokens: 100,
                breakdowns: [
                    .init(modelName: "deepseek-flash", costUSD: 4, totalTokens: -60),
                ]),
        ])

        #expect(group.models.isEmpty)
    }

    @Test
    func `monthly UTC buckets map into the containing local day`() throws {
        // The monthly fallback labels its buckets with the API calendar (UTC), so "2026-09-01" is
        // local Aug 31 in the west and must not be shown as a local September day.
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-02T00:01:00Z"))
        let august31 = try #require(pacific.date(from: DateComponents(year: 2026, month: 8, day: 31)))
        let snapshot = Self.snapshot(
            dailyDateBasis: .utc,
            historyDays: 2,
            historyLabel: "This month",
            updatedAt: now,
            entries: [
                Self.entry(day: "2026-09-01", totalCost: 1, totalTokens: 10, breakdowns: [
                    .init(modelName: "deepseek-flash", costUSD: 1, totalTokens: 10),
                ]),
                Self.entry(day: "2026-09-02", totalCost: 2, totalTokens: 20, breakdowns: [
                    .init(modelName: "deepseek-flash", costUSD: 2, totalTokens: 20),
                ]),
            ])
        let group = try #require(SpendDashboardModel.build(
            inputs: [.init(provider: .deepseek, displayName: "DeepSeek", snapshot: snapshot)],
            requestedDays: 7,
            now: now,
            calendar: pacific).groups.first)

        #expect(group.dailyPoints.first?.day == august31)
        #expect(group.totalCost == 3)
        #expect(group.totalTokens == 30)
    }

    @Test
    func `preferred local buckets keep the day they name`() throws {
        // The preferred by-key path labels days at the local fixed offset, so the same key resolves to
        // the local day it names instead of being shifted like a UTC-keyed source.
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-02T00:01:00Z"))
        let september1 = try #require(pacific.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let snapshot = Self.snapshot(
            dailyDateBasis: .local,
            historyDays: 2,
            updatedAt: now,
            entries: [
                Self.entry(day: "2026-09-01", totalCost: 1, totalTokens: 10, breakdowns: [
                    .init(modelName: "deepseek-flash", costUSD: 1, totalTokens: 10),
                ]),
            ])
        let group = try #require(SpendDashboardModel.build(
            inputs: [.init(provider: .deepseek, displayName: "DeepSeek", snapshot: snapshot)],
            requestedDays: 7,
            now: now,
            calendar: pacific).groups.first)

        #expect(group.dailyPoints.first?.day == september1)
    }

    // MARK: - Fixtures

    private static func group(
        for provider: UsageProvider,
        entries: [CostUsageDailyReport.Entry] = Self.entries) throws -> SpendDashboardModel.CurrencyGroup
    {
        try #require(SpendDashboardModel.build(
            inputs: [.init(
                provider: provider,
                displayName: provider.rawValue,
                snapshot: self.snapshot(
                    dailyDateBasis: .local,
                    last30DaysTokens: 150,
                    last30DaysCostUSD: 6,
                    updatedAt: self.now,
                    entries: entries))],
            requestedDays: 30,
            now: self.now,
            calendar: self.calendar).groups.first)
    }

    private static func snapshot(
        dailyDateBasis: CostUsageDailyDateBasis,
        historyDays: Int = 30,
        historyLabel: String? = nil,
        last30DaysTokens: Int? = nil,
        last30DaysCostUSD: Double? = nil,
        updatedAt: Date,
        entries: [CostUsageDailyReport.Entry]) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: last30DaysTokens,
            last30DaysCostUSD: last30DaysCostUSD,
            currencyCode: "USD",
            historyDays: historyDays,
            historyLabel: historyLabel,
            costProvenance: .vendorMetered,
            dailyDateBasis: dailyDateBasis,
            daily: entries,
            updatedAt: updatedAt)
    }

    /// Two usage days: one fully priced, one where a retired model's cost bucket never arrived.
    private static let entries = [
        Self.entry(
            day: "2026-07-16",
            totalCost: 4,
            totalTokens: 100,
            breakdowns: [
                .init(modelName: "deepseek-flash", costUSD: 3, totalTokens: 60),
                .init(modelName: "deepseek-v4-pro", costUSD: 1, totalTokens: 40),
            ]),
        Self.entry(
            day: "2026-07-15",
            totalCost: 2,
            totalTokens: 50,
            breakdowns: [
                .init(modelName: "deepseek-flash", costUSD: 2, totalTokens: 30),
                .init(modelName: "deepseek-v4.1-flash-expires-on-0910", costUSD: nil, totalTokens: 20),
            ]),
    ]

    private static func entry(
        day: String,
        totalCost: Double,
        totalTokens: Int,
        breakdowns: [CostUsageDailyReport.ModelBreakdown]) -> CostUsageDailyReport.Entry
    {
        CostUsageDailyReport.Entry(
            date: day,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: totalTokens,
            costUSD: totalCost,
            modelsUsed: nil,
            modelBreakdowns: breakdowns)
    }

    private static let now = Date(timeIntervalSince1970: 1_784_179_200) // 2026-07-16 00:00:00 UTC
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
