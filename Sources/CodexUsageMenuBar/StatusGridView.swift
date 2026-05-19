import AppKit
import UsageCore

final class StatusGridView: NSView {
    var usages: [ProviderAccountUsage] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    var onClick: (() -> Void)?

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(max(usages.count, 1)) * columnWidth, height: 24)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if usages.isEmpty {
            drawText("AI ?", in: bounds, color: .secondaryLabelColor)
            return
        }

        let now = Date()
        for (index, usage) in usages.enumerated() {
            let x = CGFloat(index) * columnWidth
            let columnRect = NSRect(x: x, y: 0, width: columnWidth, height: bounds.height)
            drawProviderStripe(for: usage, in: columnRect)

            let labelRect = NSRect(x: x, y: 2, width: providerCodeWidth, height: 10)
            let resetRect = NSRect(x: x, y: 13, width: providerCodeWidth, height: 10)
            let valueX = x + providerCodeWidth + valueGap
            let topRect = NSRect(x: valueX, y: 2, width: valueWidth, height: 10)
            let bottomRect = NSRect(x: valueX, y: 13, width: valueWidth, height: 10)

            drawText(
                usage.compactProviderCode,
                in: labelRect,
                color: .labelColor,
                alignment: .right,
                font: .monospacedSystemFont(ofSize: 10.5, weight: .bold)
            )
            drawText(
                usage.fiveHourResetCountdownText(now: now),
                in: resetRect,
                color: .secondaryLabelColor,
                alignment: .right,
                font: .monospacedSystemFont(ofSize: 7.5, weight: .medium)
            )
            drawText(
                format(usage.fiveHourRemainingPercent),
                in: topRect,
                color: valueColor(usage.fiveHourRemainingPercent, for: usage),
                alignment: .left,
                font: .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
            )
            drawText(
                format(usage.weeklyRemainingPercent),
                in: bottomRect,
                color: valueColor(usage.weeklyRemainingPercent, for: usage),
                alignment: .left,
                font: .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
            )

            if index < usages.count - 1 {
                drawDivider(atX: x + columnWidth - 0.5)
            }
        }
    }

    private let columnWidth: CGFloat = 52
    private let providerCodeWidth: CGFloat = 23
    private let valueGap: CGFloat = 4
    private let valueWidth: CGFloat = 23

    private var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .paragraphStyle: paragraphStyle(alignment: .center)
        ]
    }

    private func paragraphStyle(alignment: NSTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byClipping
        return style
    }

    private func drawText(_ text: String, in rect: NSRect, color: NSColor) {
        drawText(text, in: rect, color: color, alignment: .center)
    }

    private func drawText(_ text: String, in rect: NSRect, color: NSColor, alignment: NSTextAlignment) {
        drawText(text, in: rect, color: color, alignment: alignment, font: .monospacedSystemFont(ofSize: 9, weight: .medium))
    }

    private func drawText(_ text: String, in rect: NSRect, color: NSColor, alignment: NSTextAlignment, font: NSFont) {
        var attributes = textAttributes
        attributes[.font] = font
        attributes[.foregroundColor] = color
        attributes[.paragraphStyle] = paragraphStyle(alignment: alignment)
        text.draw(in: rect, withAttributes: attributes)
    }

    private func format(_ percent: Int?) -> String {
        percent.map(String.init) ?? "?"
    }

    private func valueColor(_ percent: Int?, for usage: ProviderAccountUsage) -> NSColor {
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

    private func drawProviderStripe(for usage: ProviderAccountUsage, in rect: NSRect) {
        providerColor(for: usage.provider).setFill()
        NSBezierPath(rect: NSRect(x: rect.minX + 5, y: 0, width: rect.width - 10, height: 2)).fill()
    }

    private func drawDivider(atX x: CGFloat) {
        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: x, y: 3))
        path.line(to: NSPoint(x: x, y: bounds.height - 3))
        path.stroke()
    }

    private func providerColor(for provider: UsageProvider) -> NSColor {
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
