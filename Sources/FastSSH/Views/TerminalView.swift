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

    override func keyDown(with event: NSEvent) {
        guard let session = session else { return }

        // Handle special keys
        if let characters = event.charactersIgnoringModifiers {
            switch event.keyCode {
            case 36: // Return
                session.send("\r")
                return
            case 51: // Backspace
                session.send("\u{7f}")
                return
            case 53: // Escape
                session.send("\u{1b}")
                return
            case 48: // Tab
                session.send("\t")
                return
            case 123: // Left arrow
                session.send("\u{1b}[D")
                return
            case 124: // Right arrow
                session.send("\u{1b}[C")
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
                    return
                }
            }

            // Regular character input
            if let chars = event.characters, !chars.isEmpty {
                session.send(chars)
                return
            }
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Intercept paste and typed text
        if let str = string as? String {
            session?.send(str)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Allow Cmd+C for copy, Cmd+V for paste
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "c" {
                // Copy selection
                return super.performKeyEquivalent(with: event)
            }
            if event.charactersIgnoringModifiers == "v" {
                // Paste from clipboard
                if let content = NSPasteboard.general.string(forType: .string) {
                    session?.send(content)
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
        // Automatically grab focus when added to window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Grab focus on click
        window?.makeFirstResponder(self)
    }
}
