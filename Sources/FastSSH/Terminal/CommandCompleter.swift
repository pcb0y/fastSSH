import Foundation

/// Manages command suggestions based on input prefix
class CommandCompleter {
    /// Common Linux/macOS commands
    private static let builtinCommands: [String] = [
        "apt", "apt-get", "awk",
        "cat", "cd", "chmod", "chown", "cp", "curl", "cut",
        "df", "diff", "dig", "docker", "docker-compose", "du",
        "echo", "env", "exit", "export",
        "find", "free",
        "git", "grep", "gzip",
        "head", "history", "htop",
        "ifconfig", "ip", "iptables",
        "journalctl",
        "kill", "kubectl",
        "less", "ln", "ls", "lsof",
        "make", "man", "mkdir", "mount", "mv",
        "nano", "netstat", "nginx", "nmap", "node", "npm", "nslookup",
        "passwd", "ping", "pip", "pm2", "ps", "pwd", "python", "python3",
        "reboot", "rm", "rmdir", "rsync",
        "scp", "sed", "service", "sh", "shutdown", "sort", "ssh", "sudo", "systemctl",
        "tail", "tar", "tee", "top", "touch", "traceroute",
        "uname", "unzip", "useradd", "usermod",
        "vi", "vim",
        "wc", "wget", "which", "whoami",
        "xargs",
        "yum",
        "zip", "zsh",
    ]

    /// User command history (deduplicated, most recent first)
    private var history: [String] = []
    private let maxHistory = 200

    /// Add a command to history
    func addToHistory(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Remove duplicates
        history.removeAll { $0 == trimmed }
        history.insert(trimmed, at: 0)
        if history.count > maxHistory {
            history.removeLast()
        }
    }

    /// Get suggestions for a given input prefix
    func suggest(for input: String, maxResults: Int = 8) -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var results: [String] = []
        var seen = Set<String>()

        // Search history first (more relevant)
        for cmd in history {
            if cmd.hasPrefix(trimmed) && cmd != trimmed {
                if seen.insert(cmd).inserted {
                    results.append(cmd)
                }
                if results.count >= maxResults { return results }
            }
        }

        // Then search builtin commands
        for cmd in Self.builtinCommands {
            if cmd.hasPrefix(trimmed) && cmd != trimmed {
                if seen.insert(cmd).inserted {
                    results.append(cmd)
                }
                if results.count >= maxResults { return results }
            }
        }

        return results
    }
}
