import AppKit
import UsageCore

enum StatusGridImageRenderer {
    static func image(for usages: [ProviderAccountUsage], appearance: NSAppearance?) -> NSImage {
        let width = usages.isEmpty ? emptyWidth : CGFloat(usages.count) * columnWidth
        let size = NSSize(width: width, height: imageHeight)
        let image = NSImage(size: size)

        image.lockFocus()
        if let appearance {
            appearance.performAsCurrentDrawingAppearance {
                draw(usages: usages, in: NSRect(origin: .zero, size: size))
            }
        } else {
            draw(usages: usages, in: NSRect(origin: .zero, size: size))
        }
        image.unlockFocus()
        image.isTemplate = false

        return image
    }

    static func accessibilityLabel(for usages: [ProviderAccountUsage]) -> String {
        guard !usages.isEmpty else {
            return "AI usage loading"
        }

        let now = Date()
        return usages.map { usage in
            "\(usage.compactProviderLabel) \(usage.displayName) resets in \(usage.fiveHourResetCountdownText(now: now)), \(usage.fiveHourDisplayText), \(usage.weeklyDisplayText)"
        }.joined(separator: "; ")
    }

    private static let emptyWidth: CGFloat = 34
    private static let columnWidth: CGFloat = 52
    private static let providerCodeWidth: CGFloat = 23
    private static let valueGap: CGFloat = 4
    private static let valueWidth: CGFloat = 23
    private static let imageHeight: CGFloat = 24

    private static func draw(usages: [ProviderAccountUsage], in bounds: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        if usages.isEmpty {
            drawText("AI ?", in: bounds, color: .labelColor)
            return
        }

        let now = Date()
        for (index, usage) in usages.enumerated() {
            let x = CGFloat(index) * columnWidth
            let columnRect = NSRect(x: x, y: 0, width: columnWidth, height: bounds.height)
            let valueX = x + providerCodeWidth + valueGap

            drawProviderStripe(for: usage, in: columnRect)
            drawText(
                usage.compactProviderCode,
                in: NSRect(x: x, y: 12, width: providerCodeWidth, height: 11),
                color: .labelColor,
                alignment: .right,
                font: .monospacedSystemFont(ofSize: 10.5, weight: .bold)
            )
            drawText(
                usage.fiveHourResetCountdownText(now: now),
                in: NSRect(x: x, y: 1, width: providerCodeWidth, height: 10),
                color: .labelColor,
                alignment: .right,
                font: .monospacedSystemFont(ofSize: 10.5, weight: .bold)
            )
            drawText(
                format(usage.fiveHourRemainingPercent),
                in: NSRect(x: valueX, y: 12, width: valueWidth, height: 11),
                color: valueColor(usage.fiveHourRemainingPercent, for: usage),
                alignment: .left,
                font: .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
            )
            drawText(
                format(usage.weeklyRemainingPercent),
                in: NSRect(x: valueX, y: 1, width: valueWidth, height: 11),
                color: valueColor(usage.weeklyRemainingPercent, for: usage),
                alignment: .left,
                font: .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
            )

            if index < usages.count - 1 {
                drawDivider(atX: x + columnWidth - 0.5, height: bounds.height)
            }
        }
    }

    private static func format(_ percent: Int?) -> String {
        percent.map(String.init) ?? "?"
    }

    private static func valueColor(_ percent: Int?, for usage: ProviderAccountUsage) -> NSColor {
        guard let percent else {
            return usage.errorMessage == nil ? .secondaryLabelColor : .systemOrange
        }
        if percent < 20 {
            return .systemRed
        }
        if percent < 50 {
            return .systemYellow
        }
        return .labelColor
    }

    private static func drawText(_ text: String, in rect: NSRect, color: NSColor) {
        drawText(text, in: rect, color: color, alignment: .center)
    }

    private static func drawText(_ text: String, in rect: NSRect, color: NSColor, alignment: NSTextAlignment) {
        drawText(text, in: rect, color: color, alignment: alignment, font: .monospacedSystemFont(ofSize: 9, weight: .medium))
    }

    private static func drawText(_ text: String, in rect: NSRect, color: NSColor, alignment: NSTextAlignment, font: NSFont) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect, withAttributes: attributes)
    }

    private static func drawProviderStripe(for usage: ProviderAccountUsage, in rect: NSRect) {
        providerColor(for: usage.provider).setFill()
        NSBezierPath(rect: NSRect(x: rect.minX + 5, y: 0, width: rect.width - 10, height: 2)).fill()
    }

    private static func drawDivider(atX x: CGFloat, height: CGFloat) {
        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: x, y: 3))
        path.line(to: NSPoint(x: x, y: height - 3))
        path.stroke()
    }

    private static func providerColor(for provider: UsageProvider) -> NSColor {
        switch provider {
        case .codex:
            return .systemBlue
        case .claude:
            return .systemOrange
        case .claudeRelay:
            return .systemPurple
        }
    }
}
