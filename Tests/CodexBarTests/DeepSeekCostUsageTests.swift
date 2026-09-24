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
            totalTokens: 52_000,
            requestCount: 25,
            inputTokens: 10_000,
            outputTokens: 2_000,
            cacheReadTokens: 40_000)

        let dayEntry = DeepSeekDailyUsage(
            date: "2026-09-24",
            totalTokens: 52_000,
            cost: 1.50,
            requestCount: 25,
            inputTokens: 10_000,
            outputTokens: 2_000,
            cacheReadTokens: 40_000,
            modelBreakdowns: [modelBreakdown])

        let summary = DeepSeekUsageSummary(
            todayTokens: 52_000,
            currentMonthTokens: 762_553_726,
            todayCost: 1.50,
            currentMonthCost: 6.21,
            requestCount: 25,
            currentMonthRequestCount: 4_535,
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
        #expect(tokenSnapshot.sessionTokens == 52_000)
        #expect(tokenSnapshot.sessionRequests == 25)
        #expect(tokenSnapshot.last30DaysCostUSD == 6.21)
        #expect(tokenSnapshot.last30DaysTokens == 762_553_726)
        #expect(tokenSnapshot.last30DaysRequests == 4_535)
        #expect(tokenSnapshot.costProvenance == CostProvenance.vendorMetered)
        #expect(tokenSnapshot.historyDays == 30)
        #expect(tokenSnapshot.daily.count == 1)

        let day = tokenSnapshot.daily[0]
        #expect(day.date == "2026-09-24")
        #expect(day.costUSD == 1.50)
        #expect(day.inputTokens == 10_000)
        #expect(day.outputTokens == 2_000)
        #expect(day.cacheReadTokens == 40_000)
        #expect(day.totalTokens == 52_000)
        #expect(day.requestCount == 25)
        #expect(day.modelsUsed == ["deepseek-chat"])
        #expect(day.modelBreakdowns?.count == 1)
        #expect(day.modelBreakdowns?.first?.modelName == "deepseek-chat")
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
        #expect(tokenSnapshot.daily.first?.modelsUsed == ["deepseek-reasoner"])
        #expect(tokenSnapshot.daily.first?.inputTokens == nil)
        #expect(tokenSnapshot.daily.first?.cacheReadTokens == nil)
    }
}
