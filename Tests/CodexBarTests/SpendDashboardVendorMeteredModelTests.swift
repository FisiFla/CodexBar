import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Pins the provider-scoped retention rule that keeps DeepSeek's per-model rows visible in the shared
/// spend dashboard. DeepSeek reads token and cost buckets from two separate Platform endpoints
/// (`/by_api_key/amount` and `/by_api_key/cost`), so a retired or lagging model can carry tokens on a
/// day whose cost bucket never arrived. The day is still priced; only its per-model split is
/// unprovable, which previously dropped the provider's whole breakdown.
struct SpendDashboardVendorMeteredModelTests {
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

    // MARK: - Fixtures

    private static func group(
        for provider: UsageProvider,
        entries: [CostUsageDailyReport.Entry] = Self.entries) throws -> SpendDashboardModel.CurrencyGroup
    {
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 150,
            last30DaysCostUSD: 6,
            currencyCode: "USD",
            historyDays: 30,
            costProvenance: .vendorMetered,
            daily: entries,
            updatedAt: Self.now)
        return try #require(SpendDashboardModel.build(
            inputs: [.init(provider: provider, displayName: provider.rawValue, snapshot: snapshot)],
            requestedDays: 30,
            now: Self.now,
            calendar: Self.calendar).groups.first)
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
