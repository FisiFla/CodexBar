import Foundation

extension DeepSeekUsageSummary {
    /// Projects DeepSeek platform usage into the shared `CostUsageTokenSnapshot` model,
    /// enabling CodexBar's inline usage dashboard, daily breakdown charts, and global spend ledger.
    public func toCostUsageTokenSnapshot(historyDays: Int = 30) -> CostUsageTokenSnapshot {
        let entries = self.daily.map { day in
            CostUsageDailyReport.Entry(
                date: day.date,
                inputTokens: day.inputTokens,
                outputTokens: day.outputTokens,
                cacheReadTokens: day.cacheReadTokens,
                cacheCreationTokens: nil,
                totalTokens: day.totalTokens,
                requestCount: day.requestCount,
                costUSD: day.cost,
                modelsUsed: day.modelsUsed ?? self.topModel.map { [$0] },
                modelBreakdowns: day.modelBreakdowns)
        }

        let isCurrentMonth = self.period == .currentMonth
        let effectiveHistoryDays: Int = {
            if isCurrentMonth {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
                let dayOfMonth = cal.component(.day, from: self.updatedAt)
                return max(1, dayOfMonth)
            }
            return historyDays
        }()

        return CostUsageTokenSnapshot(
            sessionTokens: self.todayTokens,
            sessionCostUSD: self.todayCost,
            sessionRequests: self.requestCount,
            last30DaysTokens: self.currentMonthTokens,
            last30DaysCostUSD: self.currentMonthCost,
            last30DaysRequests: self.currentMonthRequestCount,
            currencyCode: self.currency,
            historyDays: effectiveHistoryDays,
            historyLabel: isCurrentMonth ? "This month" : nil,
            costProvenance: .vendorMetered,
            daily: entries,
            updatedAt: self.updatedAt)
    }
}
