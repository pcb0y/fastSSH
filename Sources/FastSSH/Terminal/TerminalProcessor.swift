import Foundation

/// Processes raw terminal output, handling control characters like backspace and carriage return,
/// while preserving ANSI escape sequences for color parsing.
struct TerminalProcessor {

    /// Process raw terminal output into a string with control chars applied.
    /// Uses a simple screen buffer approach: tracks a cursor within current line.
    static func process(_ input: String) -> String {
        var output: [Character] = []
        var i = input.startIndex

        while i < input.endIndex {
            let c = input[i]

            if c == "\u{1b}" {
                // Escape sequence - pass through entirely
                let seqStart = i
                i = input.index(after: i)
                if i < input.endIndex {
                    if input[i] == "[" {
                        // CSI sequence - read until final byte
                        i = input.index(after: i)
                        while i < input.endIndex {
                            let b = input[i]
                            i = input.index(after: i)
                            if b >= "\u{40}" && b <= "\u{7e}" {
                                break
                            }
                        }
                    } else if input[i] == "]" {
                        // OSC sequence - skip until BEL or ST
                        i = input.index(after: i)
                        while i < input.endIndex {
                            if input[i] == "\u{07}" {
                                i = input.index(after: i)
                                break
                            }
                            if input[i] == "\u{1b}" {
                                let next = input.index(after: i)
                                if next < input.endIndex && input[next] == "\\" {
                                    i = input.index(after: next)
                                    break
                                }
                            }
                            i = input.index(after: i)
                        }
                    } else {
                        i = input.index(after: i)
                    }
                }
                // Append entire escape sequence
                for ch in input[seqStart..<i] {
                    output.append(ch)
                }
            } else if c == "\u{08}" {
                // Backspace: remove last visible char (not newline, not escape seq)
                backspace(&output)
                i = input.index(after: i)
            } else if c == "\r" {
                let next = input.index(after: i)
                if next < input.endIndex && input[next] == "\n" {
                    // \r\n = newline
                    output.append("\n")
                    i = input.index(after: next)
                } else {
                    // Pure \r: erase current line back to last \n
                    eraseCurrentLine(&output)
                    i = input.index(after: i)
                }
            } else if c == "\u{07}" {
                // Bell - skip
                i = input.index(after: i)
            } else {
                output.append(c)
                i = input.index(after: i)
            }
        }

        return String(output)
    }

    /// Remove the last visible character, skipping over any trailing escape sequences.
    /// Never goes past a newline.
    private static func backspace(_ output: inout [Character]) {
        while !output.isEmpty {
            let last = output.last!
            // Don't backspace past newline
            if last == "\n" {
                return
            }
            // Check if we're at the end of an escape sequence
            // Escape sequences end with a byte in 0x40-0x7E range preceded by params and ESC[
            // We need to check if the trailing chars form an escape sequence
            if isEndOfEscapeSequence(output) {
                // Skip the entire escape sequence
                skipEscapeSequenceBackward(&output)
                continue
            }
            // Regular visible character - remove it
            output.removeLast()
            return
        }
    }

    /// Check if the end of output is the tail of a CSI escape sequence
    private static func isEndOfEscapeSequence(_ output: [Character]) -> Bool {
        guard output.count >= 3 else { return false }
        let last = output[output.count - 1]
        // CSI final byte is in range 0x40-0x7E but 'm' is most common
        guard last >= "\u{40}" && last <= "\u{7e}" else { return false }

        // Walk back looking for ESC[
        var j = output.count - 2
        while j >= 0 {
            if output[j] == "\u{1b}" {
                // Check if next is [
                if j + 1 < output.count && output[j + 1] == "[" {
                    return true
                }
                return false
            }
            // Parameters are digits, semicolons, and intermediate bytes (0x20-0x3F)
            let ch = output[j]
            if ch == "[" || (ch >= "\u{20}" && ch <= "\u{3f}") {
                j -= 1
                continue
            }
            return false
        }
        return false
    }

    /// Remove a complete escape sequence from the end of output
    private static func skipEscapeSequenceBackward(_ output: inout [Character]) {
        // Remove from end back to (and including) ESC
        while !output.isEmpty {
            let ch = output.removeLast()
            if ch == "\u{1b}" {
                return
            }
        }
    }

    /// Erase from current position back to the last newline (carriage return behavior)
    private static func eraseCurrentLine(_ output: inout [Character]) {
        while !output.isEmpty && output.last != "\n" {
            output.removeLast()
        }
    }
}
