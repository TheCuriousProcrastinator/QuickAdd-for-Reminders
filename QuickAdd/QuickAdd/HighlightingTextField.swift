import AppKit
import SwiftUI

struct HighlightingTextField: NSViewRepresentable {
    @Binding var text: String

    let recognizedRanges: [NSRange]
    let focusRequestID: Int
    let caretToEndRequestID: Int
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onMoveSuggestion: (Int) -> Bool
    let onMoveToNotes: () -> Void
    let onRejectRecognition: (NSRange) -> Void
    let onDropURL: (URL, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false

        let textView = RecognitionTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.height]
        textView.minSize = NSSize(
            width: 0,
            height: scrollView.contentSize.height
        )
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.frame = NSRect(
            origin: .zero,
            size: scrollView.contentSize
        )
        textView.font = .systemFont(ofSize: 20, weight: .medium)
        textView.textColor = NSColor(calibratedWhite: 0.90, alpha: 1)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.maximumNumberOfLines = 1
        textView.textContainer?.lineBreakMode = .byClipping
        textView.textContainer?.containerSize = NSSize(
            width: .greatestFiniteMagnitude,
            height: scrollView.contentSize.height
        )
        textView.textContainer?.widthTracksTextView = false
        textView.onRecognizedClick = { range in
            context.coordinator.parent.onRejectRecognition(range)
        }
        textView.onSubmit = {
            context.coordinator.parent.onSubmit()
        }
        textView.onMoveToNotes = {
            context.coordinator.parent.onMoveToNotes()
        }
        textView.onDropURL = { url, suggestedTitle in
            context.coordinator.parent.onDropURL(url, suggestedTitle)
        }
        textView.registerForDraggedTypes([.URL, .string])

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? RecognitionTextView else { return }

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let textLength = (text as NSString).length
            let location = min(selection.location, textLength)
            let length = min(selection.length, textLength - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
        }

        textView.recognizedRanges = recognizedRanges
        context.coordinator.applyHighlight(to: textView)
        context.coordinator.revealSelection(in: textView)

        if context.coordinator.lastCaretToEndRequestID != caretToEndRequestID {
            context.coordinator.lastCaretToEndRequestID = caretToEndRequestID
            DispatchQueue.main.async {
                let end = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                textView.scrollRangeToVisible(textView.selectedRange())
                textView.window?.makeFirstResponder(textView)
            }
        }

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightingTextField
        var lastFocusRequestID = -1
        var lastCaretToEndRequestID = -1

        init(_ parent: HighlightingTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            revealSelection(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            revealSelection(in: textView)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard
                let replacementString,
                let url = webURL(from: replacementString)
            else {
                return true
            }

            DispatchQueue.main.async { [weak self] in
                self?.parent.onDropURL(url, nil)
                textView.window?.makeFirstResponder(textView)
            }
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            case #selector(NSResponder.moveUp(_:)):
                return parent.onMoveSuggestion(-1)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onMoveSuggestion(1)
            default:
                return false
            }
        }

        func applyHighlight(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)

            storage.beginEditing()
            storage.setAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 20, weight: .medium),
                    .foregroundColor: NSColor(calibratedWhite: 0.90, alpha: 1)
                ],
                range: fullRange
            )
            for range in parent.recognizedRanges where NSMaxRange(range) <= storage.length {
                storage.addAttributes(
                    [
                        .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.16),
                        .foregroundColor: NSColor.systemBlue
                    ],
                    range: range
                )
            }
            storage.endEditing()
        }

        func revealSelection(in textView: NSTextView) {
            guard
                let scrollView = textView.enclosingScrollView,
                let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)

            let usedRect = layoutManager.usedRect(
                for: textContainer
            )
            let viewportSize = scrollView.contentSize
            let contentWidth = max(
                viewportSize.width,
                ceil(usedRect.maxX + 2)
            )
            let contentHeight = max(
                viewportSize.height,
                textView.frame.height
            )

            if
                abs(textView.frame.width - contentWidth) > 0.5 ||
                abs(textView.frame.height - contentHeight) > 0.5
            {
                textView.setFrameSize(
                    NSSize(
                        width: contentWidth,
                        height: contentHeight
                    )
                )
            }

            textView.scrollRangeToVisible(
                textView.selectedRange()
            )
        }
    }
}

private final class RecognitionTextView: NSTextView {
    var recognizedRanges: [NSRange] = []
    var onRecognizedClick: ((NSRange) -> Void)?
    var onSubmit: (() -> Void)?
    var onMoveToNotes: (() -> Void)?
    var onDropURL: ((URL, String?) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, !hasMarkedText() {
            onSubmit?()
            return
        }
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) {
                window?.selectPreviousKeyView(self)
            } else {
                onMoveToNotes?()
            }
            return
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let characterIndex = characterIndex(at: event.locationInWindow)
        let clickedRecognizedRange = recognizedRanges.first { range in
            characterIndex.map { NSLocationInRange($0, range) } ?? false
        }

        super.mouseDown(with: event)

        if let clickedRecognizedRange {
            DispatchQueue.main.async { [weak self] in
                self?.onRecognizedClick?(clickedRecognizedRange)
            }
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = droppedWebURL(from: sender.draggingPasteboard) {
            onDropURL?(url, droppedURLTitle(from: sender.draggingPasteboard, url: url))
            window?.makeFirstResponder(self)
            return true
        }

        return super.performDragOperation(sender)
    }

    private func droppedWebURL(from pasteboard: NSPasteboard) -> URL? {
        let value = pasteboard.string(forType: .URL)
            ?? pasteboard.string(forType: .string)
        return value.flatMap(webURL)
    }

    private func droppedURLTitle(from pasteboard: NSPasteboard, url: URL) -> String? {
        let modernTitle = pasteboard.string(
            forType: NSPasteboard.PasteboardType("public.url-name")
        )
        let legacyType = NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType")
        let legacyTitle = (pasteboard.propertyList(forType: legacyType) as? [[String]])?
            .dropFirst()
            .first?
            .first
        let title = (modernTitle ?? legacyTitle)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let title,
            !title.isEmpty,
            title.caseInsensitiveCompare(url.absoluteString) != .orderedSame
        else {
            return nil
        }

        return title
    }

    private func characterIndex(at windowPoint: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let point = convert(windowPoint, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}

private func webURL(from value: String) -> URL? {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        let url = URL(string: trimmedValue),
        let scheme = url.scheme?.lowercased(),
        ["http", "https"].contains(scheme),
        url.host != nil
    else {
        return nil
    }

    return url
}

struct NotesTextEditor: NSViewRepresentable {
    @Binding var text: String

    let focusRequestID: Int
    let isEditable: Bool
    let onMoveForward: () -> Void
    let onMoveBackward: () -> Void
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NavigatingNotesTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor(calibratedWhite: 0.90, alpha: 1)
        textView.textContainerInset = NSSize(width: 5, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.onMoveForward = {
            context.coordinator.parent.onMoveForward()
        }
        textView.onMoveBackward = {
            context.coordinator.parent.onMoveBackward()
        }
        textView.onFocusChange = { isFocused in
            context.coordinator.parent.onFocusChange(isFocused)
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NavigatingNotesTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextEditor
        var lastFocusRequestID: Int

        init(_ parent: NotesTextEditor) {
            self.parent = parent
            lastFocusRequestID = parent.focusRequestID
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private final class NavigatingNotesTextView: NSTextView {
    var onMoveForward: (() -> Void)?
    var onMoveBackward: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            onFocusChange?(true)
        }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        if resignedFirstResponder {
            onFocusChange?(false)
        }
        return resignedFirstResponder
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) {
                onMoveBackward?()
            } else {
                onMoveForward?()
            }
            return
        }

        super.keyDown(with: event)
    }
}
