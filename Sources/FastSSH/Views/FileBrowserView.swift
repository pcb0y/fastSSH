import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @ObservedObject var session: SSHSession
    @State private var localPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var remotePath: String = "/"
    @State private var localFiles: [FileItem] = []
    @State private var remoteFiles: [FileItem] = []
    @State private var selectedLocalFiles: Set<UUID> = []
    @State private var selectedRemoteFiles: Set<UUID> = []
    @State private var transferStatus: String = ""
    @State private var transferProgress: Double = 0
    @State private var isTransferring = false
    @State private var error: String?
    @State private var isDropTargetLocal = false
    @State private var isDropTargetRemote = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // Local panel
                localPanel
                // Remote panel
                remotePanel
            }

            // Status bar
            statusBar
        }
        .task {
            await loadLocal()
            await loadRemote()
        }
    }

    // MARK: - Local Panel

    private var localPanel: some View {
        VStack(spacing: 0) {
            panelHeader(title: "panel.local".localized, path: localPath, onGoUp: goUpLocal)
            Divider()
            List(localFiles, selection: $selectedLocalFiles) { file in
                fileRow(file: file, isLocal: true)
                    .tag(file.id)
            }
            .listStyle(.plain)
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button("upload.selected".localized) {
                    uploadSelected(ids)
                }
            } primaryAction: { ids in
                // Double-click: navigate into directory
                if let id = ids.first, let file = localFiles.first(where: { $0.id == id }), file.isDirectory {
                    navigateLocal(file)
                }
            }
            // Accept drops from remote (download indicator)
            .overlay(
                isDropTargetLocal ?
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.green, lineWidth: 2)
                    .padding(4) : nil
            )

            // Toolbar
            HStack {
                Button {
                    uploadSelected(selectedLocalFiles)
                } label: {
                    Label("upload".localized, systemImage: "arrow.right")
                }
                .disabled(selectedLocalFiles.isEmpty || isTransferring)
                .help("help.upload".localized)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
        }
        .frame(minWidth: 300)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargetLocal) { providers in
            // Drop from Finder to local - not needed, Finder handles it
            return false
        }
    }

    // MARK: - Remote Panel

    private var remotePanel: some View {
        VStack(spacing: 0) {
            panelHeader(title: "panel.remote".localized, path: remotePath, onGoUp: goUpRemote)
            Divider()
            List(remoteFiles, selection: $selectedRemoteFiles) { file in
                fileRow(file: file, isLocal: false)
                    .tag(file.id)
            }
            .listStyle(.plain)
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button("download.selected".localized) {
                    downloadSelected(ids)
                }
            } primaryAction: { ids in
                if let id = ids.first, let file = remoteFiles.first(where: { $0.id == id }), file.isDirectory {
                    navigateRemote(file)
                }
            }
            .overlay(
                isDropTargetRemote ?
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.blue, lineWidth: 2)
                    .padding(4) : nil
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargetRemote) { providers in
                handleDropToRemote(providers)
                return true
            }

            // Toolbar
            HStack {
                Button {
                    downloadSelected(selectedRemoteFiles)
                } label: {
                    Label("download".localized, systemImage: "arrow.left")
                }
                .disabled(selectedRemoteFiles.isEmpty || isTransferring)
                .help("help.download".localized)

                Spacer()

                Button {
                    createRemoteDir()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("help.new.folder".localized)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
        }
        .frame(minWidth: 300)
    }

    // MARK: - Shared Components

    private func panelHeader(title: String, path: String, onGoUp: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: onGoUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Text(path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private func fileRow(file: FileItem, isLocal: Bool) -> some View {
        HStack {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                .foregroundColor(file.isDirectory ? .blue : .secondary)
                .frame(width: 20)
            Text(file.name)
                .lineLimit(1)
            Spacer()
            Text(Self.dateFormatter.string(from: file.modTime))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .trailing)
            if !file.isDirectory {
                Text(formatSize(file.size))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            } else {
                Text("")
                    .frame(width: 60)
            }
            // Transfer button
            Button {
                if isLocal {
                    transferLocalToRemote(file)
                } else {
                    transferRemoteToLocal(file)
                }
            } label: {
                Image(systemName: isLocal ? "arrow.right.circle" : "arrow.left.circle")
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .help(isLocal ? "upload".localized : "download".localized)
        }
    }

    private var statusBar: some View {
        HStack {
            if isTransferring {
                ProgressView(value: transferProgress)
                    .frame(width: 200)
                Text(transferStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let error = error {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if !transferStatus.isEmpty {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text(transferStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Navigation

    private func navigateLocal(_ file: FileItem) {
        guard file.isDirectory else { return }
        localPath = file.path
        selectedLocalFiles = []
        Task { await loadLocal() }
    }

    private func navigateRemote(_ file: FileItem) {
        guard file.isDirectory else { return }
        remotePath = file.path
        selectedRemoteFiles = []
        Task { await loadRemote() }
    }

    private func goUpLocal() {
        localPath = (localPath as NSString).deletingLastPathComponent
        selectedLocalFiles = []
        Task { await loadLocal() }
    }

    private func goUpRemote() {
        let parts = remotePath.split(separator: "/").dropLast()
        remotePath = "/" + parts.joined(separator: "/")
        selectedRemoteFiles = []
        Task { await loadRemote() }
    }

    // MARK: - Loading

    private func loadLocal() async {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: localPath),
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
            )
            localFiles = contents.compactMap { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
                return FileItem(
                    name: url.lastPathComponent,
                    path: url.path,
                    size: Int64(values?.fileSize ?? 0),
                    isDirectory: values?.isDirectory ?? false,
                    modTime: values?.contentModificationDate ?? Date(),
                    permissions: ""
                )
            }.sorted { ($0.isDirectory ? 0 : 1, $0.name) < ($1.isDirectory ? 0 : 1, $1.name) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadRemote() async {
        do {
            remoteFiles = try await session.listRemoteDirectory(remotePath)
                .sorted { ($0.isDirectory ? 0 : 1, $0.name) < ($1.isDirectory ? 0 : 1, $1.name) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Transfer (single item button)

    private func transferLocalToRemote(_ file: FileItem) {
        Task { await doUpload(files: [file]) }
    }

    private func transferRemoteToLocal(_ file: FileItem) {
        Task { await doDownload(files: [file]) }
    }

    // MARK: - Transfer (multi-select)

    private func uploadSelected(_ ids: Set<UUID>) {
        let files = localFiles.filter { ids.contains($0.id) }
        guard !files.isEmpty else { return }
        Task { await doUpload(files: files) }
    }

    private func downloadSelected(_ ids: Set<UUID>) {
        let files = remoteFiles.filter { ids.contains($0.id) }
        guard !files.isEmpty else { return }
        Task { await doDownload(files: files) }
    }

    // MARK: - Drag and Drop

    private func handleDropToRemote(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let path = url.path
                Task { @MainActor in
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                    let file = FileItem(
                        name: url.lastPathComponent,
                        path: path,
                        size: 0,
                        isDirectory: isDir.boolValue,
                        modTime: Date(),
                        permissions: ""
                    )
                    await doUpload(files: [file])
                }
            }
        }
    }

    // MARK: - Conflict Resolution

    enum ConflictAction {
        case overwrite
        case renameNew
        case backupExisting
        case skip
    }

    /// Show a conflict dialog when a file already exists at the destination.
    /// Returns the chosen action synchronously on the main thread.
    private func showConflictDialog(fileName: String, isUpload: Bool) -> ConflictAction {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "conflict.title".localized
        alert.informativeText = "conflict.message".localized(fileName)

        alert.addButton(withTitle: "overwrite".localized)        // 1st = .alertFirstButtonReturn
        alert.addButton(withTitle: "conflict.rename".localized)  // 2nd
        alert.addButton(withTitle: "conflict.backup".localized)  // 3rd
        alert.addButton(withTitle: "skip".localized)             // 4th

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .overwrite
        case .alertSecondButtonReturn:
            return .renameNew
        case .alertThirdButtonReturn:
            return .backupExisting
        default:
            return .skip
        }
    }

    /// Generate a unique name by appending _1, _2, etc.
    private func generateUniqueName(baseName: String, ext: String, existing: String) -> String {
        let nameWithoutExt = ext.isEmpty ? baseName : String(baseName.dropLast(ext.count + 1))
        let counter = 1
        let newName = ext.isEmpty ? "\(nameWithoutExt)_\(counter)" : "\(nameWithoutExt)_\(counter).\(ext)"
        return newName
    }

    // MARK: - Upload/Download Logic

    private func doUpload(files: [FileItem]) async {
        isTransferring = true
        error = nil
        let total = files.count
        var completed = 0

        for file in files {
            var dest = remotePath + "/" + file.name
            transferStatus = "status.uploading".localized(file.name, completed+1, total)

            // Check for conflict (only for files, not directories)
            if !file.isDirectory {
                let exists = await session.remoteFileExists(dest)
                if exists {
                    let action = showConflictDialog(fileName: file.name, isUpload: true)
                    switch action {
                    case .skip:
                        completed += 1
                        continue
                    case .overwrite:
                        break // proceed as-is
                    case .renameNew:
                        // Rename the uploaded file
                        let ext = (file.name as NSString).pathExtension
                        let nameNoExt = ext.isEmpty ? file.name : String(file.name.dropLast(ext.count + 1))
                        var counter = 1
                        repeat {
                            let newName = ext.isEmpty ? "\(nameNoExt)_\(counter)" : "\(nameNoExt)_\(counter).\(ext)"
                            dest = remotePath + "/" + newName
                            counter += 1
                        } while await session.remoteFileExists(dest)
                    case .backupExisting:
                        // Rename existing remote file to .bak
                        let bakPath = dest + ".bak"
                        try? await session.renameRemote(from: dest, to: bakPath)
                    }
                }
            }

            do {
                if file.isDirectory {
                    try await session.uploadDirectory(localPath: file.path, remotePath: dest) { name in
                        Task { @MainActor in
                            self.transferStatus = "status.uploading.single".localized(name)
                        }
                    }
                } else {
                    try await session.upload(localPath: file.path, remotePath: dest) { pct in
                        Task { @MainActor in
                            self.transferProgress = pct
                        }
                    }
                }
                completed += 1
                transferProgress = Double(completed) / Double(total)
            } catch {
                self.error = "status.upload.failed".localized(file.name, error.localizedDescription)
                break
            }
        }

        isTransferring = false
        if self.error == nil {
            transferStatus = "status.uploaded".localized(completed)
        }
        await loadRemote()
    }

    private func doDownload(files: [FileItem]) async {
        isTransferring = true
        error = nil
        let total = files.count
        var completed = 0

        for file in files {
            var dest = localPath + "/" + file.name
            transferStatus = "status.downloading".localized(file.name, completed+1, total)

            // Check for local conflict
            if !file.isDirectory && FileManager.default.fileExists(atPath: dest) {
                let action = showConflictDialog(fileName: file.name, isUpload: false)
                switch action {
                case .skip:
                    completed += 1
                    continue
                case .overwrite:
                    break
                case .renameNew:
                    let ext = (file.name as NSString).pathExtension
                    let nameNoExt = ext.isEmpty ? file.name : String(file.name.dropLast(ext.count + 1))
                    var counter = 1
                    repeat {
                        let newName = ext.isEmpty ? "\(nameNoExt)_\(counter)" : "\(nameNoExt)_\(counter).\(ext)"
                        dest = localPath + "/" + newName
                        counter += 1
                    } while FileManager.default.fileExists(atPath: dest)
                case .backupExisting:
                    let bakPath = dest + ".bak"
                    try? FileManager.default.moveItem(atPath: dest, toPath: bakPath)
                }
            }

            do {
                if file.isDirectory {
                    try await session.downloadDirectory(remotePath: file.path, localPath: dest) { name in
                        Task { @MainActor in
                            self.transferStatus = "status.downloading.single".localized(name)
                        }
                    }
                } else {
                    try await session.download(remotePath: file.path, localPath: dest) { pct in
                        Task { @MainActor in
                            self.transferProgress = pct
                        }
                    }
                }
                completed += 1
                transferProgress = Double(completed) / Double(total)
            } catch {
                self.error = "status.download.failed".localized(file.name, error.localizedDescription)
                break
            }
        }

        isTransferring = false
        if self.error == nil {
            transferStatus = "status.downloaded".localized(completed)
        }
        await loadLocal()
    }

    // MARK: - Actions

    private func createRemoteDir() {
        let alert = NSAlert()
        alert.messageText = "new.folder.title".localized
        alert.informativeText = "new.folder.message".localized
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        input.stringValue = "new.folder.default".localized
        alert.accessoryView = input
        alert.addButton(withTitle: "create".localized)
        alert.addButton(withTitle: "cancel".localized)

        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            Task {
                do {
                    try await session.mkdirRemote(remotePath + "/" + name)
                    await loadRemote()
                } catch {
                    self.error = "new.folder.failed".localized(error.localizedDescription)
                }
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes == 0 { return "-" }
        let units = ["B", "KB", "MB", "GB"]
        var size = Double(bytes)
        var i = 0
        while size >= 1024 && i < units.count - 1 {
            size /= 1024
            i += 1
        }
        return String(format: i > 0 ? "%.1f %@" : "%.0f %@", size, units[i])
    }
}
