import Foundation
import Testing
@testable import CodexBarCore

@Suite
struct DeepSeekCostUsageTests {
    @Test
    func `projects platform usage summary into shared cost usage token snapshot`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let modelBreakdown = CostUsageDailyReport.ModelBreakdown(
            modelName: "deepseek-chat",
            costUSD: 1.50,
            totalTokens: 52000,
            requestCount: 25,
            inputTokens: 10000,
            outputTokens: 2000,
            cacheReadTokens: 40000)

        let dayEntry = DeepSeekDailyUsage(
            date: "2026-09-24",
            totalTokens: 52000,
            cost: 1.50,
            requestCount: 25,
            inputTokens: 10000,
            outputTokens: 2000,
            cacheReadTokens: 40000,
            modelBreakdowns: [modelBreakdown])

        let summary = DeepSeekUsageSummary(
            todayTokens: 52000,
            currentMonthTokens: 762_553_726,
            todayCost: 1.50,
            currentMonthCost: 6.21,
            requestCount: 25,
            currentMonthRequestCount: 4535,
            topModel: "deepseek-chat",
            categoryBreakdown: [],
            daily: [dayEntry],
            currency: "USD",
            modelCosts: [DeepSeekModelCost(model: "deepseek-chat", cost: 6.21)],
            apiKeyCount: 2,
            period: .last30Days,
            updatedAt: now)

        let tokenSnapshot = summary.toCostUsageTokenSnapshot(historyDays: 30)

        #expect(tokenSnapshot.currencyCode == "USD")
        #expect(tokenSnapshot.sessionCostUSD == 1.50)
        #expect(tokenSnapshot.sessionTokens == 52000)
        #expect(tokenSnapshot.sessionRequests == 25)
        #expect(tokenSnapshot.last30DaysCostUSD == 6.21)
        #expect(tokenSnapshot.last30DaysTokens == 762_553_726)
        #expect(tokenSnapshot.last30DaysRequests == 4535)
        #expect(tokenSnapshot.costProvenance == CostProvenance.vendorMetered)
        #expect(tokenSnapshot.historyLabel == nil)
        #expect(tokenSnapshot.historyDays == 30)
        #expect(tokenSnapshot.daily.count == 1)

        let day = tokenSnapshot.daily[0]
        #expect(day.date == "2026-09-24")
        #expect(day.costUSD == 1.50)
        #expect(day.inputTokens == 10000)
        #expect(day.outputTokens == 2000)
        #expect(day.cacheReadTokens == 40000)
        #expect(day.totalTokens == 52000)
        #expect(day.requestCount == 25)
        #expect(day.modelsUsed == ["deepseek-chat"])
        #expect(day.modelBreakdowns?.count == 1)
        #expect(day.modelBreakdowns?.first?.modelName == "deepseek-chat")
        #expect(day.modelBreakdowns?.first?.costUSD == 1.50)
    }

    @Test
    func `preserves currency and fallback topModel when daily models are omitted`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let dayEntry = DeepSeekDailyUsage(
            date: "2026-09-23",
            totalTokens: 100_000,
            cost: 0.85,
            requestCount: 10)

        let summary = DeepSeekUsageSummary(
            todayTokens: 100_000,
            currentMonthTokens: 1_200_000,
            todayCost: 0.85,
            currentMonthCost: 15.40,
            requestCount: 10,
            currentMonthRequestCount: 150,
            topModel: "deepseek-reasoner",
            categoryBreakdown: [],
            daily: [dayEntry],
            currency: "CNY",
            modelCosts: [],
            apiKeyCount: 1,
            period: .currentMonth,
            updatedAt: now)

        let tokenSnapshot = summary.toCostUsageTokenSnapshot()

        #expect(tokenSnapshot.currencyCode == "CNY")
        #expect(tokenSnapshot.historyLabel == "This month")
        #expect(tokenSnapshot.historyDays == 14)
        #expect(tokenSnapshot.daily.first?.modelsUsed == ["deepseek-reasoner"])
        #expect(tokenSnapshot.daily.first?.inputTokens == nil)
        #expect(tokenSnapshot.daily.first?.cacheReadTokens == nil)
    }

    @Test
    func `monthly fallback period sets This month label and covered days`() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 24
        comps.hour = 10
        let date = try #require(cal.date(from: comps))

        let modelBreakdown = CostUsageDailyReport.ModelBreakdown(
            modelName: "deepseek-chat",
            costUSD: 0.75,
            totalTokens: 20000,
            requestCount: 5,
            inputTokens: 5000,
            outputTokens: 1000,
            cacheReadTokens: 14000)

        let day = DeepSeekDailyUsage(
            date: "2026-09-24",
            totalTokens: 20000,
            cost: 0.75,
            requestCount: 5,
            inputTokens: 5000,
            outputTokens: 1000,
            cacheReadTokens: 14000,
            modelBreakdowns: [modelBreakdown])

        let summary = DeepSeekUsageSummary(
            todayTokens: 20000,
            currentMonthTokens: 150_000,
            todayCost: 0.75,
            currentMonthCost: 5.50,
            requestCount: 5,
            currentMonthRequestCount: 40,
            topModel: "deepseek-chat",
            categoryBreakdown: [],
            daily: [day],
            currency: "USD",
            modelCosts: [DeepSeekModelCost(model: "deepseek-chat", cost: 5.50)],
            apiKeyCount: 0,
            period: .currentMonth,
            updatedAt: date)

        let snapshot = summary.toCostUsageTokenSnapshot()

        #expect(snapshot.historyLabel == "This month")
        #expect(snapshot.historyDays == 24)
        #expect(snapshot.daily.first?.costUSD == 0.75)
        #expect(snapshot.daily.first?.modelBreakdowns?.first?.costUSD == 0.75)
        #expect(snapshot.daily.first?.inputTokens == 5000)
        #expect(snapshot.daily.first?.outputTokens == 1000)
        #expect(snapshot.daily.first?.cacheReadTokens == 14000)
    }
}
