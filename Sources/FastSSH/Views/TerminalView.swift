import SwiftUI
import AppKit

struct TerminalView: View {
    @ObservedObject var session: SSHSession

    var body: some View {
        TerminalNSView(session: session)
            .background(Color.black)
    }
}

struct TerminalNSView: NSViewRepresentable {
    @ObservedObject var session: SSHSession

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = TerminalTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor(red: 0.067, green: 0.067, blue: 0.106, alpha: 1.0) // #11111b
        textView.textColor = NSColor(red: 0.804, green: 0.839, blue: 0.957, alpha: 1.0) // #cdd6f4
        textView.insertionPointColor = NSColor(red: 0.537, green: 0.706, blue: 0.98, alpha: 1.0)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)

        textView.session = session

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        // Make the text view first responder after a short delay to ensure window is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        guard let storage = textView.textStorage else { return }

        let newOutput = session.terminalOutput
        let lastRendered = context.coordinator.lastRenderedLength

        if newOutput.count > lastRendered {
            context.coordinator.lastRenderedLength = newOutput.count

            // Re-render full output with control char processing + ANSI color parsing
            let processed = TerminalProcessor.process(newOutput)
            let attributed = ANSIParser.parse(processed)

            storage.beginEditing()
            storage.setAttributedString(attributed)
            storage.endEditing()

            textView.scrollToEndOfDocument(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var textView: TerminalTextView?
        var scrollView: NSScrollView?
        var lastRenderedLength = 0
    }
}

class TerminalTextView: NSTextView {
    var session: SSHSession?

    // Autocomplete state
    let completer = CommandCompleter()
    private var inputBuffer = ""
    private var suggestions: [String] = []
    private var selectedSuggestion = 0
    private var popupWindow: NSWindow?
    private var popupTableView: NSTableView?

    override func keyDown(with event: NSEvent) {
        guard let session = session else { return }

        // If popup is showing, handle navigation keys
        if popupWindow?.isVisible == true {
            switch event.keyCode {
            case 125: // Down arrow
                selectedSuggestion = min(selectedSuggestion + 1, suggestions.count - 1)
                popupTableView?.selectRowIndexes(IndexSet(integer: selectedSuggestion), byExtendingSelection: false)
                popupTableView?.scrollRowToVisible(selectedSuggestion)
                return
            case 126: // Up arrow
                selectedSuggestion = max(selectedSuggestion - 1, 0)
                popupTableView?.selectRowIndexes(IndexSet(integer: selectedSuggestion), byExtendingSelection: false)
                popupTableView?.scrollRowToVisible(selectedSuggestion)
                return
            case 36, 48: // Return or Tab — accept suggestion
                acceptSuggestion()
                return
            case 53: // Escape — dismiss
                dismissPopup()
                return
            default:
                break
            }
        }

        // Handle special keys
        if let characters = event.charactersIgnoringModifiers {
            switch event.keyCode {
            case 36: // Return
                // Record command to history before sending
                completer.addToHistory(inputBuffer)
                inputBuffer = ""
                dismissPopup()
                session.send("\r")
                return
            case 51: // Backspace
                if !inputBuffer.isEmpty {
                    inputBuffer.removeLast()
                }
                session.send("\u{7f}")
                updateSuggestions()
                return
            case 53: // Escape
                inputBuffer = ""
                dismissPopup()
                session.send("\u{1b}")
                return
            case 48: // Tab
                session.send("\t")
                return
            case 123: // Left arrow
                session.send("\u{1b}[D")
                dismissPopup()
                return
            case 124: // Right arrow
                session.send("\u{1b}[C")
                dismissPopup()
                return
            case 125: // Down arrow
                session.send("\u{1b}[B")
                return
            case 126: // Up arrow
                session.send("\u{1b}[A")
                return
            default:
                break
            }

            // Handle Ctrl+key combinations
            if event.modifierFlags.contains(.control) {
                if let char = characters.first, char.isLetter {
                    let ctrlChar = Character(UnicodeScalar(char.asciiValue! - 96))
                    session.send(String(ctrlChar))
                    inputBuffer = ""
                    dismissPopup()
                    return
                }
            }

            // Regular character input
            if let chars = event.characters, !chars.isEmpty {
                session.send(chars)
                inputBuffer += chars
                updateSuggestions()
                return
            }
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Intercept paste and typed text
        if let str = string as? String {
            session?.send(str)
            inputBuffer += str
            updateSuggestions()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Allow Cmd+C for copy, Cmd+V for paste
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "c" {
                return super.performKeyEquivalent(with: event)
            }
            if event.charactersIgnoringModifiers == "v" {
                if let content = NSPasteboard.general.string(forType: .string) {
                    session?.send(content)
                    inputBuffer += content
                    updateSuggestions()
                }
                return true
            }
        }
        return false
    }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
        dismissPopup()
    }

    // MARK: - Autocomplete

    private func updateSuggestions() {
        // Only suggest when input looks like a command (no spaces = first word)
        let trimmed = inputBuffer.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains(" "), trimmed.count >= 2 else {
            dismissPopup()
            return
        }

        suggestions = completer.suggest(for: trimmed)
        if suggestions.isEmpty {
            dismissPopup()
            return
        }

        selectedSuggestion = 0
        showPopup()
    }

    private func acceptSuggestion() {
        guard !suggestions.isEmpty, selectedSuggestion < suggestions.count else { return }
        let chosen = suggestions[selectedSuggestion]
        // Send the remaining characters to complete the command
        let remaining = String(chosen.dropFirst(inputBuffer.trimmingCharacters(in: .whitespaces).count))
        session?.send(remaining)
        inputBuffer = chosen
        dismissPopup()
    }

    private func showPopup() {
        guard let window = self.window else { return }

        if popupWindow == nil {
            createPopupWindow()
        }

        guard let popup = popupWindow, let tableView = popupTableView else { return }

        // Position popup near cursor
        let cursorRect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let screenPoint = NSPoint(x: cursorRect.origin.x, y: cursorRect.origin.y - 4)

        let rowHeight: CGFloat = 22
        let popupHeight = min(CGFloat(suggestions.count) * rowHeight + 4, 180)
        let popupWidth: CGFloat = 220

        popup.setFrame(NSRect(x: screenPoint.x, y: screenPoint.y - popupHeight, width: popupWidth, height: popupHeight), display: true)

        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        if !popup.isVisible {
            window.addChildWindow(popup, ordered: .above)
            popup.orderFront(nil)
        }
    }

    private func dismissPopup() {
        suggestions = []
        if let popup = popupWindow, popup.isVisible {
            popup.parent?.removeChildWindow(popup)
            popup.orderOut(nil)
        }
    }

    private func createPopupWindow() {
        let popup = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 150),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        popup.isFloatingPanel = true
        popup.level = .floating
        popup.hasShadow = true
        popup.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 0.95)
        popup.isOpaque = false

        let scrollView = NSScrollView(frame: popup.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.width = 210
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        popup.contentView?.addSubview(scrollView)

        popupWindow = popup
        popupTableView = tableView
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension TerminalTextView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        suggestions.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: suggestions[row])
        cell.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.textColor = NSColor(red: 0.804, green: 0.839, blue: 0.957, alpha: 1.0)
        cell.drawsBackground = false
        cell.isBezeled = false
        cell.isEditable = false

        let container = NSView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cell)
        NSLayoutConstraint.activate([
            cell.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            cell.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if let tableView = notification.object as? NSTableView {
            selectedSuggestion = tableView.selectedRow
        }
    }
}
