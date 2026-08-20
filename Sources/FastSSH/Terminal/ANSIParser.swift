import AppKit

/// Parses ANSI escape sequences and converts them to NSAttributedString
struct ANSIParser {

    // xterm-256color palette (first 16 standard colors)
    static let standardColors: [NSColor] = [
        NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1),       // 0 black
        NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1),       // 1 red
        NSColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1),       // 2 green
        NSColor(red: 0.8, green: 0.8, blue: 0.0, alpha: 1),       // 3 yellow
        NSColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1),       // 4 blue
        NSColor(red: 0.8, green: 0.0, blue: 0.8, alpha: 1),       // 5 magenta
        NSColor(red: 0.0, green: 0.8, blue: 0.8, alpha: 1),       // 6 cyan
        NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1),    // 7 white
        NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),       // 8 bright black
        NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1),       // 9 bright red
        NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1),       // 10 bright green
        NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1),       // 11 bright yellow
        NSColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1),       // 12 bright blue
        NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1),       // 13 bright magenta
        NSColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1),       // 14 bright cyan
        NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),       // 15 bright white
    ]

    static let defaultFG = NSColor(red: 0.804, green: 0.839, blue: 0.957, alpha: 1.0)
    static let defaultBG = NSColor(red: 0.067, green: 0.067, blue: 0.106, alpha: 1.0)
    nonisolated(unsafe) static let defaultFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    nonisolated(unsafe) static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    /// Parse a string containing ANSI escape codes into an attributed string
    static func parse(_ input: String) -> NSAttributedString {
        let result = NSMutableAttributedString()

        var fg: NSColor = defaultFG
        var bg: NSColor = defaultBG
        var bold = false
        var dim = false
        var italic = false
        var underline = false

        var i = input.startIndex
        var textStart = i

        while i < input.endIndex {
            if input[i] == "\u{1b}" {
                // Flush text before escape
                if textStart < i {
                    let text = String(input[textStart..<i])
                    let attrs = makeAttributes(fg: fg, bg: bg, bold: bold, dim: dim, italic: italic, underline: underline)
                    result.append(NSAttributedString(string: text, attributes: attrs))
                }

                // Check for CSI sequence: ESC [
                let next = input.index(after: i)
                if next < input.endIndex && input[next] == "[" {
                    // Parse CSI
                    var j = input.index(after: next)
                    var params = ""
                    while j < input.endIndex {
                        let c = input[j]
                        if c >= "\u{40}" && c <= "\u{7e}" {
                            // Final byte
                            if c == "m" {
                                // SGR - Select Graphic Rendition
                                applySGR(params: params, fg: &fg, bg: &bg, bold: &bold, dim: &dim, italic: &italic, underline: &underline)
                            }
                            // Skip other CSI sequences (cursor movement, etc.)
                            j = input.index(after: j)
                            break
                        } else {
                            params.append(c)
                            j = input.index(after: j)
                        }
                    }
                    i = j
                    textStart = i
                } else if next < input.endIndex && input[next] == "]" {
                    // OSC sequence (e.g., window title) - skip until BEL or ST
                    var j = input.index(after: next)
                    while j < input.endIndex {
                        if input[j] == "\u{07}" { // BEL
                            j = input.index(after: j)
                            break
                        }
                        if input[j] == "\u{1b}" {
                            let nextJ = input.index(after: j)
                            if nextJ < input.endIndex && input[nextJ] == "\\" {
                                j = input.index(after: nextJ)
                                break
                            }
                        }
                        j = input.index(after: j)
                    }
                    i = j
                    textStart = i
                } else {
                    // Unknown escape, skip ESC
                    i = next
                    textStart = i
                }
            } else {
                i = input.index(after: i)
            }
        }

        // Flush remaining text
        if textStart < input.endIndex {
            let text = String(input[textStart...])
            let attrs = makeAttributes(fg: fg, bg: bg, bold: bold, dim: dim, italic: italic, underline: underline)
            result.append(NSAttributedString(string: text, attributes: attrs))
        }

        return result
    }

    private static func applySGR(params: String, fg: inout NSColor, bg: inout NSColor, bold: inout Bool, dim: inout Bool, italic: inout Bool, underline: inout Bool) {
        let codes = params.split(separator: ";").compactMap { Int($0) }

        if codes.isEmpty {
            // ESC[m = reset
            fg = defaultFG
            bg = defaultBG
            bold = false
            dim = false
            italic = false
            underline = false
            return
        }

        var idx = 0
        while idx < codes.count {
            let code = codes[idx]
            switch code {
            case 0:
                fg = defaultFG; bg = defaultBG; bold = false; dim = false; italic = false; underline = false
            case 1:
                bold = true
            case 2:
                dim = true
            case 3:
                italic = true
            case 4:
                underline = true
            case 22:
                bold = false; dim = false
            case 23:
                italic = false
            case 24:
                underline = false
            case 30...37:
                fg = standardColors[code - 30]
            case 38:
                // Extended foreground
                if idx + 1 < codes.count && codes[idx + 1] == 5 && idx + 2 < codes.count {
                    fg = color256(codes[idx + 2])
                    idx += 2
                } else if idx + 1 < codes.count && codes[idx + 1] == 2 && idx + 4 < codes.count {
                    fg = NSColor(red: CGFloat(codes[idx+2])/255, green: CGFloat(codes[idx+3])/255, blue: CGFloat(codes[idx+4])/255, alpha: 1)
                    idx += 4
                }
            case 39:
                fg = defaultFG
            case 40...47:
                bg = standardColors[code - 40]
            case 48:
                // Extended background
                if idx + 1 < codes.count && codes[idx + 1] == 5 && idx + 2 < codes.count {
                    bg = color256(codes[idx + 2])
                    idx += 2
                } else if idx + 1 < codes.count && codes[idx + 1] == 2 && idx + 4 < codes.count {
                    bg = NSColor(red: CGFloat(codes[idx+2])/255, green: CGFloat(codes[idx+3])/255, blue: CGFloat(codes[idx+4])/255, alpha: 1)
                    idx += 4
                }
            case 49:
                bg = defaultBG
            case 90...97:
                fg = standardColors[code - 90 + 8]
            case 100...107:
                bg = standardColors[code - 100 + 8]
            default:
                break
            }
            idx += 1
        }
    }

    /// Convert 256-color index to NSColor
    private static func color256(_ index: Int) -> NSColor {
        if index < 16 {
            return standardColors[index]
        } else if index < 232 {
            // 216 color cube: 6x6x6
            let adjusted = index - 16
            let r = adjusted / 36
            let g = (adjusted % 36) / 6
            let b = adjusted % 6
            return NSColor(
                red: r == 0 ? 0 : CGFloat(r * 40 + 55) / 255.0,
                green: g == 0 ? 0 : CGFloat(g * 40 + 55) / 255.0,
                blue: b == 0 ? 0 : CGFloat(b * 40 + 55) / 255.0,
                alpha: 1
            )
        } else {
            // Grayscale: 24 shades
            let gray = CGFloat((index - 232) * 10 + 8) / 255.0
            return NSColor(red: gray, green: gray, blue: gray, alpha: 1)
        }
    }

    private static func makeAttributes(fg: NSColor, bg: NSColor, bold: Bool, dim: Bool, italic: Bool, underline: Bool) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: dim ? fg.withAlphaComponent(0.6) : fg,
            .font: bold ? boldFont : defaultFont,
        ]
        if bg != defaultBG {
            attrs[.backgroundColor] = bg
        }
        if underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }
}
