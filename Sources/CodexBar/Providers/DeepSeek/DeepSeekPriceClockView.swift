import CodexBarCore
import Foundation
import SwiftUI

public struct DeepSeekPriceClockView: View {
    @State private var isUTC: Bool = false
    private let initialPresentation: DeepSeekPriceClockPresentation?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    private static let peakColor = Color(red: 0.91, green: 0.42, blue: 0.36)
    private static let offPeakColor = Color(red: 0.22, green: 0.74, blue: 0.48)

    public init(presentation: DeepSeekPriceClockPresentation? = nil) {
        self.initialPresentation = presentation
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let presentation = DeepSeekPriceClockPresentation.make(
                at: context.date,
                timeZone: .autoupdatingCurrent,
                isUTC: self.isUTC)
            self.content(for: presentation)
        }
    }

    private func content(for presentation: DeepSeekPriceClockPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            self.headerBanner(for: presentation)
            Divider()
            self.priceWindowsSection(for: presentation)
            self.timelineBar(for: presentation)
            self.footerBar(for: presentation)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func headerBanner(for presentation: DeepSeekPriceClockPresentation) -> some View {
        let accentColor = presentation.isPeak ? Self.peakColor : Self.offPeakColor
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 7, height: 7)
                Text(presentation.statusBadgeText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor)
                    .textCase(.uppercase)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.countdownDigitsText)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                Text(presentation.countdownSuffixText)
                    .font(.subheadline)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }

            Text(presentation.nextTransitionText)
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
    }

    private func priceWindowsSection(for presentation: DeepSeekPriceClockPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.windowsTitle)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .textCase(.uppercase)

            ForEach(presentation.windows) { window in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(window.tagText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(window.isPeak ? Self.peakColor : Self.offPeakColor)
                        .frame(width: 54, alignment: .leading)

                    Text(window.timeRangeText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))

                    Spacer(minLength: 4)

                    Text(window.durationText)
                        .font(.system(size: 11))
                        .foregroundStyle(window.isCurrent
                            ? MenuHighlightStyle.primary(self.isHighlighted)
                            : MenuHighlightStyle.secondary(self.isHighlighted))
                }
            }
        }
    }

    private func timelineBar(for presentation: DeepSeekPriceClockPresentation) -> some View {
        VStack(spacing: 3) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 8)

                    ForEach(presentation.daySegments) { segment in
                        let segStart = max(0, min(width, width * segment.startFraction))
                        let segEnd = max(0, min(width, width * segment.endFraction))
                        let segWidth = max(0, segEnd - segStart)
                        Rectangle()
                            .fill(segment.isPeak ? Self.peakColor : Self.offPeakColor)
                            .frame(width: segWidth, height: 8)
                            .offset(x: segStart)
                    }

                    let needleX = max(0, min(width, width * presentation.currentDayFraction))
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 12)
                        .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 0)
                        .offset(x: needleX - 1)
                }
            }
            .frame(height: 12)

            HStack {
                Text("00")
                Spacer()
                Text("06")
                Spacer()
                Text("12")
                Spacer()
                Text("18")
                Spacer()
                Text("24")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
    }

    private func footerBar(for presentation: DeepSeekPriceClockPresentation) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Button(L("Local")) {
                    self.isUTC = false
                }
                .buttonStyle(PriceClockToggleButtonStyle(isSelected: !self.isUTC))

                Button(L("UTC")) {
                    self.isUTC = true
                }
                .buttonStyle(PriceClockToggleButtonStyle(isSelected: self.isUTC))
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08)))

            Spacer()

            Text("\(presentation.timeZoneName) · \(presentation.gmtOffsetDescription)")
                .font(.system(size: 9))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
        }
    }
}

private struct PriceClockToggleButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: self.isSelected ? .semibold : .regular))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(self.isSelected ? Color.accentColor : Color.clear))
            .foregroundStyle(self.isSelected ? Color.white : Color.primary.opacity(0.7))
    }
}
