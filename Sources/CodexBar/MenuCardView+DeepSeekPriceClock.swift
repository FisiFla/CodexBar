import CodexBarCore
import SwiftUI

extension UsageMenuCardView.Model {
    static func deepSeekPriceClock(input: Input) -> DeepSeekPriceClockPresentation? {
        // Provider-specific by design: DeepSeek is the provider offering off-peak / peak scheduled pricing discounts.
        guard input.provider == .deepseek else { return nil }
        guard ProviderDescriptorRegistry.descriptor(for: .deepseek).presentation.menuCard.showsDeepSeekPriceClock else {
            return nil
        }
        guard input.showOptionalCreditsAndExtraUsage else { return nil }
        return DeepSeekPriceClockPresentation.make(at: input.now, timeZone: .autoupdatingCurrent)
    }
}
