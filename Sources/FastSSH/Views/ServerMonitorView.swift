import SwiftUI

struct ServerStats {
    var hostname = ""
    var uptime = ""
    var osInfo = ""
    var cpuUsage: Double = 0
    var cpuModel = ""
    var cpuCores = 0
    var loadAverage = ""
    var memTotal: Int64 = 0   // KB
    var memUsed: Int64 = 0    // KB
    var memFree: Int64 = 0    // KB
    var swapTotal: Int64 = 0
    var swapUsed: Int64 = 0
    var disks: [DiskInfo] = []

    struct DiskInfo: Identifiable {
        let id = UUID()
        let filesystem: String
        let size: String
        let used: String
        let available: String
        let usePercent: Int
        let mountPoint: String
    }
}

struct ServerMonitorView: View {
    @ObservedObject var session: SSHSession
    @State private var stats = ServerStats()
    @State private var isLoading = true
    @State private var autoRefresh = true
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stats.hostname)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(stats.osInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(stats.uptime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await fetchStats() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    Toggle("Auto", isOn: $autoRefresh)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal)

                if isLoading && stats.hostname.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // CPU & Memory
                    HStack(spacing: 16) {
                        // CPU
                        statCard {
                            VStack(spacing: 8) {
                                gaugeView(value: stats.cpuUsage, color: cpuColor)
                                Text("CPU")
                                    .font(.headline)
                                Text(stats.cpuModel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Text("\(stats.cpuCores) cores")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Load: \(stats.loadAverage)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Memory
                        statCard {
                            VStack(spacing: 8) {
                                gaugeView(value: memPercent, color: memColor)
                                Text("Memory")
                                    .font(.headline)
                                Text("\(formatKB(stats.memUsed)) / \(formatKB(stats.memTotal))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if stats.swapTotal > 0 {
                                    Text("Swap: \(formatKB(stats.swapUsed)) / \(formatKB(stats.swapTotal))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Disks
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Disk")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(stats.disks) { disk in
                            diskRow(disk)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await fetchStats()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
        .onChange(of: autoRefresh) { _, newValue in
            if newValue {
                startAutoRefresh()
            } else {
                refreshTask?.cancel()
            }
        }
    }

    // MARK: - Subviews

    private func statCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
    }

    private func gaugeView(value: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: value / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(String(format: "%.0f%%", value))
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.medium)
        }
        .frame(width: 80, height: 80)
    }

    private func diskRow(_ disk: ServerStats.DiskInfo) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(disk.mountPoint)
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                Text("\(disk.used) / \(disk.size)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("(\(disk.usePercent)%)")
                    .font(.caption)
                    .foregroundColor(disk.usePercent > 90 ? .red : .secondary)
            }
            ProgressView(value: Double(disk.usePercent), total: 100)
                .tint(disk.usePercent > 90 ? .red : disk.usePercent > 70 ? .orange : .blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - Colors

    private var cpuColor: Color {
        stats.cpuUsage > 80 ? .red : stats.cpuUsage > 50 ? .orange : .green
    }

    private var memPercent: Double {
        guard stats.memTotal > 0 else { return 0 }
        return Double(stats.memUsed) / Double(stats.memTotal) * 100
    }

    private var memColor: Color {
        memPercent > 80 ? .red : memPercent > 50 ? .orange : .blue
    }

    // MARK: - Helpers

    private func formatKB(_ kb: Int64) -> String {
        if kb >= 1048576 {
            return String(format: "%.1f GB", Double(kb) / 1048576.0)
        } else if kb >= 1024 {
            return String(format: "%.0f MB", Double(kb) / 1024.0)
        }
        return "\(kb) KB"
    }

    // MARK: - Data Fetching

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled && autoRefresh {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                if !Task.isCancelled && autoRefresh {
                    await fetchStats()
                }
            }
        }
    }

    private func fetchStats() async {
        isLoading = true
        // Run all stat commands in one shot for efficiency
        let script = """
        echo "===HOSTNAME==="; hostname;
        echo "===UPTIME==="; uptime;
        echo "===OS==="; cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || uname -sr;
        echo "===CPU_MODEL==="; grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 || sysctl -n machdep.cpu.brand_string 2>/dev/null;
        echo "===CPU_CORES==="; nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null;
        echo "===LOAD==="; cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || sysctl -n vm.loadavg 2>/dev/null;
        echo "===CPU_USAGE==="; top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' || echo "0";
        echo "===MEMORY==="; cat /proc/meminfo 2>/dev/null | grep -E "MemTotal|MemAvailable|MemFree|SwapTotal|SwapFree";
        echo "===DISK==="; df -h 2>/dev/null | grep -E "^/";
        echo "===END==="
        """

        let output = await session.executeCommand(script)
        parseStats(output)
        isLoading = false
    }

    private func parseStats(_ output: String) {
        var section = ""
        var memInfo: [String: Int64] = [:]
        var disks: [ServerStats.DiskInfo] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("===") && trimmed.hasSuffix("===") {
                section = trimmed.replacingOccurrences(of: "===", with: "")
                continue
            }
            guard !trimmed.isEmpty else { continue }

            switch section {
            case "HOSTNAME":
                stats.hostname = trimmed
            case "UPTIME":
                stats.uptime = trimmed
            case "OS":
                stats.osInfo = trimmed
            case "CPU_MODEL":
                stats.cpuModel = trimmed.trimmingCharacters(in: .whitespaces)
            case "CPU_CORES":
                stats.cpuCores = Int(trimmed) ?? 0
            case "LOAD":
                stats.loadAverage = trimmed
            case "CPU_USAGE":
                // Parse CPU usage from top output
                let val = trimmed.replacingOccurrences(of: ",", with: ".")
                stats.cpuUsage = Double(val) ?? 0
            case "MEMORY":
                // Parse /proc/meminfo lines
                let parts = trimmed.split(separator: ":")
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let valStr = parts[1].trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: " kB", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let val = Int64(valStr) {
                        memInfo[key] = val
                    }
                }
            case "DISK":
                // Parse df -h output
                let cols = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if cols.count >= 6 {
                    let useStr = String(cols[4]).replacingOccurrences(of: "%", with: "")
                    let disk = ServerStats.DiskInfo(
                        filesystem: String(cols[0]),
                        size: String(cols[1]),
                        used: String(cols[2]),
                        available: String(cols[3]),
                        usePercent: Int(useStr) ?? 0,
                        mountPoint: String(cols[5])
                    )
                    disks.append(disk)
                }
            default:
                break
            }
        }

        // Calculate memory
        stats.memTotal = memInfo["MemTotal"] ?? 0
        let memAvailable = memInfo["MemAvailable"] ?? memInfo["MemFree"] ?? 0
        stats.memUsed = stats.memTotal - memAvailable
        stats.memFree = memAvailable
        stats.swapTotal = memInfo["SwapTotal"] ?? 0
        stats.swapUsed = stats.swapTotal - (memInfo["SwapFree"] ?? 0)
        stats.disks = disks
    }
}
