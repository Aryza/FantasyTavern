import AppKit

enum PDFExporter {
    enum ExportError: Error {
        case printOperationFailed
    }

    /// Render `content` to a PDF file at `url`. Uses US Letter w/ 0.5" margins.
    static func write(_ content: NSAttributedString, to url: URL) throws {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url as NSURL

        let textWidth  = info.paperSize.width  - info.leftMargin - info.rightMargin
        let textHeight = info.paperSize.height - info.topMargin  - info.bottomMargin

        // Build a tall NSTextView; NSPrintOperation paginates it across pages.
        let frame = NSRect(x: 0, y: 0, width: textWidth, height: textHeight)
        let textView = NSTextView(frame: frame)
        textView.isEditable = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(content)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let used = textView.layoutManager?.usedRect(for: textView.textContainer!).size ?? .zero
        textView.frame = NSRect(x: 0, y: 0, width: textWidth, height: max(textHeight, used.height))

        let op = NSPrintOperation(view: textView, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        if !op.run() {
            throw ExportError.printOperationFailed
        }
    }
}
