import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    @ObservedObject var buffer: Buffer
    let fontSize: CGFloat
    let wordWrap: Bool
    let showLineNumbers: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        let bufferChanged = coordinator.buffer !== buffer
        coordinator.buffer = buffer

        if textView.string != buffer.content {
            coordinator.isProgrammaticChange = true
            textView.string = buffer.content
            coordinator.isProgrammaticChange = false
            if bufferChanged {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollToBeginningOfDocument(nil)
            }
        }
        if textView.font?.pointSize != fontSize {
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        if coordinator.wordWrapApplied != wordWrap {
            coordinator.wordWrapApplied = wordWrap
            Self.applyWrapMode(wordWrap, scrollView: scrollView, textView: textView)
        }
        scrollView.rulersVisible = showLineNumbers
        coordinator.ruler?.needsDisplay = true
        if bufferChanged {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        if let pending = AppState.shared.pendingSelection, pending.bufferID == buffer.id,
           NSMaxRange(pending.range) <= (textView.string as NSString).length {
            textView.setSelectedRange(pending.range)
            textView.scrollRangeToVisible(pending.range)
            textView.showFindIndicator(for: pending.range)
            DispatchQueue.main.async {
                AppState.shared.pendingSelection = nil
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    static func applyWrapMode(_ wrap: Bool, scrollView: NSScrollView, textView: NSTextView) {
        let huge = CGFloat.greatestFiniteMagnitude
        if wrap {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: huge)
            textView.textContainer?.widthTracksTextView = true
            textView.frame.size.width = scrollView.contentSize.width
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            textView.maxSize = NSSize(width: huge, height: huge)
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: huge, height: huge)
        }
        textView.needsLayout = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?
        var buffer: Buffer?
        var isProgrammaticChange = false
        var wordWrapApplied: Bool?

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange, let textView, let buffer else { return }
            let text = textView.string
            MainActor.assumeIsolated {
                buffer.suppressChangeNotifications = true
                buffer.content = text
                buffer.suppressChangeNotifications = false
                AppState.shared.bufferEdited(buffer)
            }
            ruler?.needsDisplay = true
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            MainActor.assumeIsolated { buffer?.undoManager }
        }
    }
}

/// Regla lateral con números de línea.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 46
        NotificationCenter.default.addObserver(self, selector: #selector(redraw),
                                               name: NSText.didChangeNotification, object: textView)
        if let contentView = textView.enclosingScrollView?.contentView {
            contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(redraw),
                                                   name: NSView.boundsDidChangeNotification, object: contentView)
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let content = textView.string as NSString
        let visibleRect = textView.visibleRect
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let visibleChars = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: max(9, (textView.font?.pointSize ?? 13) - 2), weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        var lineStart = content.lineRange(for: NSRange(location: visibleChars.location, length: 0)).location

        // Número de línea de la primera línea visible.
        var lineNumber = 1
        if lineStart > 0 {
            content.enumerateSubstrings(in: NSRange(location: 0, length: lineStart),
                                        options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                lineNumber += 1
            }
        }

        let inset = textView.textContainerInset.height
        while lineStart < NSMaxRange(visibleChars) || (lineStart == 0 && content.length == 0) {
            let lineRange = content.length == 0
                ? NSRange(location: 0, length: 0)
                : content.lineRange(for: NSRange(location: lineStart, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = content.length == 0
                ? layoutManager.extraLineFragmentRect
                : layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            let y = lineRect.minY + inset - visibleRect.minY
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: y + 1), withAttributes: attributes)
            if content.length == 0 { break }
            let next = NSMaxRange(lineRange)
            if next <= lineStart { break }
            lineStart = next
            lineNumber += 1
        }

        // Línea extra final si el texto acaba en salto de línea.
        if content.length > 0, lineStart >= content.length,
           let last = content.substring(from: content.length - 1).first, last == "\n" || last == "\r",
           NSMaxRange(visibleChars) >= content.length {
            let lineRect = layoutManager.extraLineFragmentRect
            let y = lineRect.minY + inset - visibleRect.minY
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: y + 1), withAttributes: attributes)
        }
    }
}
