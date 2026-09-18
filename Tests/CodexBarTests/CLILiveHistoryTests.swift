import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct CLILiveHistoryTests {
    @Test(arguments: BundledPluginTestSupport.engines, [
        (1.25, 0.0, "$1.25 (reported)"),
        (0.0, 0.75, "$0.75 (estimated)"),
        (1.25, 0.75, "$2.00 (includes estimates)"),
    ])
    func `successful Activity appears once in text and full cards with its cost provenance`(
        engine: ProviderPluginEngineKind,
        scenario: (Double, Double, String)) async throws
    {
        let snapshot = try await OpenRouterReasoningTestSupport.snapshot(engine: engine, activityBody: """
        {"data":[{"date":"2026-08-17","model":"example/token-model","prompt_tokens":10,
          "completion_tokens":5,"reasoning_tokens":2,"requests":1,
          "usage":\(scenario.0),"byok_usage_inference":\(scenario.1)}]}
        """)
        let expected = "Last 30 days (UTC): \(scenario.2) · 15 tokens"
        let (text, card) = Self.render(snapshot)
        #expect(text.components(separatedBy: expected).count == 2)
        #expect(card.extraLines.filter { $0 == expected }.count == 1)
        let renderedCard = CLICardsRenderer.renderCard(card, width: 120, useColor: false).joined(separator: "\n")
        #expect(renderedCard.contains(expected))
        #expect(text.contains("Balance: $60.00"))
        #expect(text.contains("API key used: $5.00"))
        #expect(snapshot.primary?.usedPercent == 25)
        #expect(!text.contains("local logs"))
        #expect(!text.contains("Cursor-metered"))

        let data = try JSONEncoder().encode(snapshot)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["costUsage"] == nil)
        #expect(Set(json.keys) == [
            "primary", "secondary", "tertiary", "details", "updatedAt", "identity", "loginMethod",
        ])
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        #expect(decoded.costUsage == nil)
        #expect(decoded.details == snapshot.details)
        #expect(decoded.identity == snapshot.identity)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `empty successful Activity renders known zero while failed Activity retains its diagnostic`(
        engine: ProviderPluginEngineKind) async throws
    {
        let empty = try await OpenRouterReasoningTestSupport.snapshot(engine: engine, activityBody: #"{"data":[]}"#)
        #expect(empty.costUsage?.daily.isEmpty == true)
        let (emptyText, emptyCard) = Self.render(empty)
        let zero = "Last 30 days (UTC): $0.00 (reported) · 0 tokens"
        #expect(emptyText.contains(zero))
        #expect(emptyCard.extraLines.contains(zero))

        let failed = try await OpenRouterReasoningTestSupport.snapshot(engine: engine, activityBody: "not-json")
        #expect(failed.costUsage == nil)
        let (failedText, failedCard) = Self.render(failed)
        let unavailable = "Last 30 days: Unavailable right now · Response was invalid"
        #expect(failedText.components(separatedBy: unavailable).count == 2)
        #expect(failedCard.extraLines.filter { $0 == unavailable }.count == 1)
        #expect(!failedText.contains("$0.00"))
        #expect(!failedText.contains("0 tokens"))
    }

    @Test(arguments: [
        HistoryCase(provider: .grok, tokens: 42, expected: "Last 30 days: 42 tokens"),
        HistoryCase(
            amount: 2.5, currency: "EUR", label: "Billing period", expected: "Billing period: €2.50"),
        HistoryCase(tokens: 15, days: 7, expected: "Last 7 days: 15 tokens"),
        HistoryCase(tokens: 1, days: 1, expected: "Last 1 day: 1 token"),
        HistoryCase(tokens: 0, amount: 0, expected: "Last 30 days: $0.00 · 0 tokens"),
        HistoryCase(expected: nil),
    ])
    func `live history preserves the supplied period currency and optional totals`(scenario: HistoryCase) {
        let history = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: scenario.tokens,
            last30DaysCostUSD: scenario.amount,
            currencyCode: scenario.currency,
            historyDays: scenario.days,
            historyLabel: scenario.label,
            daily: [],
            updatedAt: OpenRouterReasoningTestSupport.now)
        let snapshot = UsageSnapshot(primary: nil, secondary: nil, costUsage: history, updatedAt: history.updatedAt)
        let (text, card) = Self.render(snapshot, provider: scenario.provider)
        if let expected = scenario.expected {
            #expect(text.contains(expected))
            #expect(card.extraLines.contains(expected))
        } else {
            #expect(!text.contains("Last 30 days"))
            #expect(card.extraLines.isEmpty)
        }
        if scenario.amount == nil { #expect(!text.contains("$0.00")) }
        if scenario.tokens == nil { #expect(!text.contains("0 tokens")) }
    }

    struct HistoryCase: Sendable {
        var provider: UsageProvider = .openrouter
        var tokens: Int?
        var amount: Double?
        var currency = "USD"
        var days = 30
        var label: String?
        var expected: String?
    }

    private static func render(
        _ snapshot: UsageSnapshot,
        provider: UsageProvider = .openrouter) -> (String, CLICardModel)
    {
        // Rendering later must not silently re-bucket the provider's completed reporting window.
        let now = OpenRouterReasoningTestSupport.now.addingTimeInterval(90 * 24 * 60 * 60)
        return (
            CLIRenderer.renderText(
                provider: provider,
                snapshot: snapshot,
                credits: nil,
                context: RenderContext(header: "Synthetic usage", status: nil, useColor: false, resetStyle: .countdown),
                now: now),
            CLICardsRenderer.makeCard(CLICardBuildInput(
                provider: provider,
                snapshot: snapshot,
                credits: nil,
                source: "fixture",
                status: nil,
                notes: [],
                useColor: false,
                resetStyle: .countdown,
                weeklyWorkDays: nil,
                now: now)))
    }
}
