import Foundation
import Testing
@testable import CodexBarCore

struct DeepSeekUsageCostIntegrityTests {
    private let fixtureNow = Date(timeIntervalSince1970: 1_779_796_800) // 2026-05-26 12:00:00 UTC
    private let fixtureCalendar: Calendar = {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }()

    @Test
    func `monthly fallback rejects non-finite and negative model cost amounts`() throws {
        let dateString = "2026-05-26"
        let amountJSON = """
        {
          "code": 0,
          "msg": "",
          "data": {
            "biz_code": 0,
            "biz_msg": "",
            "biz_data": {
              "total": [],
              "days": [
                {
                  "date": "\(dateString)",
                  "data": [
                    {
                      "model": "deepseek-chat",
                      "usage": [{"type": "RESPONSE_TOKEN", "amount": "100"}, {"type": "REQUEST", "amount": "1"}]
                    },
                    {
                      "model": "deepseek-reasoner",
                      "usage": [{"type": "RESPONSE_TOKEN", "amount": "100"}, {"type": "REQUEST", "amount": "1"}]
                    }
                  ]
                }
              ]
            }
          }
        }
        """

        let costJSON = """
        {
          "code": 0,
          "msg": "",
          "data": {
            "biz_code": 0,
            "biz_msg": "",
            "biz_data": [
              {
                "currency": "USD",
                "total": [],
                "days": [
                  {
                    "date": "\(dateString)",
                    "data": [
                      {
                        "model": "deepseek-chat",
                        "usage": [{"type": "RESPONSE_TOKEN", "amount": "-1.50"}]
                      },
                      {
                        "model": "deepseek-reasoner",
                        "usage": [{"type": "RESPONSE_TOKEN", "amount": "NaN"}]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """

        let summary = try DeepSeekUsageFetcher._parseUsageSummaryForTesting(
            amountData: Data(amountJSON.utf8),
            costData: Data(costJSON.utf8),
            now: self.fixtureNow,
            calendar: self.fixtureCalendar)

        #expect(summary.daily.count == 1)
        let dayUsage = summary.daily[0]
        let breakdowns = dayUsage.modelBreakdowns ?? []
        #expect(breakdowns.count == 2)

        let chat = breakdowns.first { $0.modelName == "deepseek-chat" }
        #expect(chat?.costUSD == nil)

        let reasoner = breakdowns.first { $0.modelName == "deepseek-reasoner" }
        #expect(reasoner?.costUSD == nil)
        #expect(dayUsage.cost == nil)
        #expect(summary.todayCost == nil)
        #expect(summary.currentMonthCost == nil)
    }

    @Test
    func `monthly fallback invalid model cost invalidates daily aggregate and period spend`() throws {
        let dateString = "2026-05-26"
        let amountJSON = """
        {
          "code": 0,
          "msg": "",
          "data": {
            "biz_code": 0,
            "biz_msg": "",
            "biz_data": {
              "total": [],
              "days": [
                {
                  "date": "\(dateString)",
                  "data": [
                    {
                      "model": "deepseek-chat",
                      "usage": [{"type": "RESPONSE_TOKEN", "amount": "100"}, {"type": "REQUEST", "amount": "1"}]
                    },
                    {
                      "model": "deepseek-reasoner",
                      "usage": [{"type": "RESPONSE_TOKEN", "amount": "100"}, {"type": "REQUEST", "amount": "1"}]
                    }
                  ]
                }
              ]
            }
          }
        }
        """

        let costJSON = """
        {
          "code": 0,
          "msg": "",
          "data": {
            "biz_code": 0,
            "biz_msg": "",
            "biz_data": [
              {
                "currency": "USD",
                "total": [],
                "days": [
                  {
                    "date": "\(dateString)",
                    "data": [
                      {
                        "model": "deepseek-chat",
                        "usage": [{"type": "RESPONSE_TOKEN", "amount": "0.15"}]
                      },
                      {
                        "model": "deepseek-reasoner",
                        "usage": [{"type": "RESPONSE_TOKEN", "amount": "malformed"}]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """

        let summary = try DeepSeekUsageFetcher._parseUsageSummaryForTesting(
            amountData: Data(amountJSON.utf8),
            costData: Data(costJSON.utf8),
            now: self.fixtureNow,
            calendar: self.fixtureCalendar)

        #expect(summary.daily.count == 1)
        let dayUsage = summary.daily[0]
        let breakdowns = dayUsage.modelBreakdowns ?? []
        #expect(breakdowns.count == 2)

        let chat = breakdowns.first { $0.modelName == "deepseek-chat" }
        #expect(chat?.costUSD == 0.15)

        let reasoner = breakdowns.first { $0.modelName == "deepseek-reasoner" }
        #expect(reasoner?.costUSD == nil)

        #expect(dayUsage.cost == nil)
        #expect(summary.todayCost == nil)
        #expect(summary.currentMonthCost == nil)
    }

    @Test
    func `by-api-key partial invalid bucket for model invalidates daily model cost`() throws {
        let calendar = self.fixtureCalendar
        let today = calendar.startOfDay(for: self.fixtureNow)
        let day = Int((calendar.date(byAdding: .day, value: -1, to: today) ?? today).timeIntervalSince1970)

        let amountJSON = """
        {
          "code": 0,
          "data": {
            "biz_data": {
              "series": [
                {
                  "api_key": "key-1",
                  "model": "deepseek-chat",
                  "buckets": [{"time": \(day), "usage": {"RESPONSE_TOKEN": 100, "REQUEST": 1}}]
                },
                {
                  "api_key": "key-1",
                  "model": "deepseek-coder",
                  "buckets": [{"time": \(day), "usage": {"RESPONSE_TOKEN": 50, "REQUEST": 1}}]
                }
              ]
            }
          }
        }
        """

        let costJSON = """
        {
          "code": 0,
          "data": {
            "biz_data": {
              "data": [{
                "currency": "USD",
                "series": [
                  {
                    "api_key": "key-1",
                    "model": "deepseek-chat",
                    "buckets": [
                      {"time": \(day), "cost": "0.15"},
                      {"time": \(day + 3600), "cost": "invalid"}
                    ]
                  },
                  {
                    "api_key": "key-1",
                    "model": "deepseek-coder",
                    "buckets": [{"time": \(day), "cost": "0.20"}]
                  }
                ]
              }]
            }
          }
        }
        """

        let summary = try DeepSeekUsageCostParser.parseByAPIKey(
            amountData: Data(amountJSON.utf8),
            costData: Data(costJSON.utf8),
            now: self.fixtureNow,
            calendar: calendar,
            rangeStart: calendar.date(byAdding: .day, value: -2, to: today)!,
            rangeEnd: calendar.date(byAdding: .day, value: 1, to: today)!)

        let targetDate = calendar.date(byAdding: .day, value: -1, to: today)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let targetDateString = formatter.string(from: targetDate)

        let dayUsage = summary.daily.first { $0.date == targetDateString }
        #expect(dayUsage != nil)
        let breakdowns = dayUsage?.modelBreakdowns ?? []

        let chat = breakdowns.first { $0.modelName == "deepseek-chat" }
        #expect(chat?.costUSD == nil)

        let coder = breakdowns.first { $0.modelName == "deepseek-coder" }
        #expect(coder?.costUSD == 0.20)
        #expect(dayUsage?.cost == nil)
        #expect(summary.currentMonthCost == nil)
    }

    @Test
    func `by-api-key invalid bucket on one day keeps period spend unknown despite valid days`() throws {
        let calendar = self.fixtureCalendar
        let today = calendar.startOfDay(for: self.fixtureNow)
        let day1 = Int((calendar.date(byAdding: .day, value: -2, to: today) ?? today).timeIntervalSince1970)
        let day2 = Int((calendar.date(byAdding: .day, value: -1, to: today) ?? today).timeIntervalSince1970)

        let amountJSON = """
        {
          "code": 0,
          "data": {
            "biz_data": {
              "series": [
                {
                  "api_key": "key-1",
                  "model": "deepseek-chat",
                  "buckets": [
                    {"time": \(day1), "usage": {"RESPONSE_TOKEN": 100, "REQUEST": 1}},
                    {"time": \(day2), "usage": {"RESPONSE_TOKEN": 100, "REQUEST": 1}}
                  ]
                }
              ]
            }
          }
        }
        """

        let costJSON = """
        {
          "code": 0,
          "data": {
            "biz_data": {
              "data": [{
                "currency": "USD",
                "series": [
                  {
                    "api_key": "key-1",
                    "model": "deepseek-chat",
                    "buckets": [
                      {"time": \(day1), "cost": "0.50"},
                      {"time": \(day2), "cost": "broken"}
                    ]
                  }
                ]
              }]
            }
          }
        }
        """

        let summary = try DeepSeekUsageCostParser.parseByAPIKey(
            amountData: Data(amountJSON.utf8),
            costData: Data(costJSON.utf8),
            now: self.fixtureNow,
            calendar: calendar,
            rangeStart: calendar.date(byAdding: .day, value: -3, to: today)!,
            rangeEnd: calendar.date(byAdding: .day, value: 1, to: today)!)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let targetDate1String = formatter.string(from: calendar.date(byAdding: .day, value: -2, to: today)!)
        let targetDate2String = formatter.string(from: calendar.date(byAdding: .day, value: -1, to: today)!)

        let day1Usage = summary.daily.first { $0.date == targetDate1String }
        let day2Usage = summary.daily.first { $0.date == targetDate2String }

        #expect(day1Usage?.cost == 0.50)
        #expect(day2Usage?.cost == nil)
        #expect(summary.currentMonthCost == nil)
    }
}
