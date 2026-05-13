import SwiftUI
import AppKit
import EntityModel
import WikiLinks

public struct MarkdownTextView: NSViewRepresentable {
    @Binding public var text: String
    public let resolver: WikiLinkResolver
    public let onOpenLink: (EntityID) -> Void
    public let onSelectionChange: ((NSRange) -> Void)?

    public init(text: Binding<String>,
                resolver: WikiLinkResolver,
                onOpenLink: @escaping (EntityID) -> Void,
                onSelectionChange: ((NSRange) -> Void)? = nil) {
        self._text = text
        self.resolver = resolver
        self.onOpenLink = onOpenLink
        self.onSelectionChange = onSelectionChange
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.allowsUndo = true
        tv.delegate = context.coordinator
        tv.textStorage?.setAttributedString(MarkdownStyler.attributedString(for: text, resolver: resolver))
        context.coordinator.textView = tv
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        tv.addGestureRecognizer(click)
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let selected = tv.selectedRange()
            tv.textStorage?.setAttributedString(MarkdownStyler.attributedString(for: text, resolver: resolver))
            tv.setSelectedRange(NSRange(location: min(selected.location, text.utf16.count), length: 0))
        } else {
            tv.textStorage?.setAttributedString(MarkdownStyler.attributedString(for: text, resolver: resolver))
        }
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MarkdownTextView
        weak var textView: NSTextView?
        init(_ parent: MarkdownTextView) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onSelectionChange?(tv.selectedRange())
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.onSelectionChange?(tv.selectedRange())
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let tv = textView else { return }
            let point = gesture.location(in: tv)
            let charIndex = tv.characterIndexForInsertion(at: point)
            guard charIndex < (tv.textStorage?.length ?? 0) else { return }
            if let raw = tv.textStorage?.attribute(.fantasyWikiLink, at: charIndex, effectiveRange: nil) as? String {
                parent.onOpenLink(EntityID(raw))
            }
        }
    }
}
