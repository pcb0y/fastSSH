import Foundation
import Shout
import CSSH
import Socket

/// Wrapper to make OpaquePointer sendable for SSH session pointers
struct SendablePointer: @unchecked Sendable {
    let pointer: OpaquePointer
}

@MainActor
class SSHSession: ObservableObject, Identifiable {
    let id = UUID()
    let connection: SSHConnection

    @Published var isConnected = false
    @Published var terminalOutput = ""
    @Published var error: String?

    private var ssh: SSH?
    private var sock: Socket?
    nonisolated(unsafe) private var cSession: OpaquePointer?
    nonisolated(unsafe) private var shellChannel: OpaquePointer?
    private var readTask: Task<Void, Never>?
    /// Lock to serialize all libssh2 access (read loop + SFTP ops)
    private let sessionLock = NSLock()

    init(connection: SSHConnection) {
        self.connection = connection
    }

    func connect() async {
        do {
            // Use Shout for connection and authentication
            let sshObj = try SSH(host: connection.host, port: Int32(connection.port))

            switch connection.authMethod {
            case .password:
                try sshObj.authenticate(username: connection.username, password: connection.password)
            case .key:
                let keyPath = (connection.keyPath as NSString).expandingTildeInPath
                try sshObj.authenticate(username: connection.username, privateKey: keyPath)
            }

            ssh = sshObj

            // Access the underlying libssh2 session through Shout's session
            // We need to open a shell channel with PTY using libssh2 directly
            // Get the cSession from Shout's internals via reflection or re-create
            // Since Shout's Session/Channel are internal, we'll create our own socket+session
            let socket = try Socket.create()
            try socket.connect(to: connection.host, port: Int32(connection.port))
            sock = socket

            guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
                throw SSHSessionError.initFailed
            }
            cSession = session
            libssh2_session_set_blocking(session, 1)

            let hsResult = libssh2_session_handshake(session, socket.socketfd)
            guard hsResult == 0 else {
                throw SSHSessionError.handshakeFailed
            }

            // Authenticate
            let authResult: Int32
            switch connection.authMethod {
            case .password:
                authResult = libssh2_userauth_password_ex(
                    session,
                    connection.username, UInt32(connection.username.count),
                    connection.password, UInt32(connection.password.count),
                    nil
                )
            case .key:
                let keyPath = (connection.keyPath as NSString).expandingTildeInPath
                let pubPath = keyPath + ".pub"
                authResult = libssh2_userauth_publickey_fromfile_ex(
                    session,
                    connection.username, UInt32(connection.username.count),
                    pubPath, keyPath, nil
                )
            }
            guard authResult == 0 else {
                throw SSHSessionError.authFailed
            }

            // Open channel
            let channelType = "session"
            guard let channel = libssh2_channel_open_ex(
                session, channelType, UInt32(channelType.count),
                2 * 1024 * 1024, 32768, nil, 0
            ) else {
                throw SSHSessionError.channelFailed
            }
            shellChannel = channel

            // Request PTY
            let term = "xterm-256color"
            let ptyResult = libssh2_channel_request_pty_ex(
                channel, term, UInt32(term.count),
                nil, 0,
                120, 40, 0, 0
            )
            guard ptyResult == 0 else {
                throw SSHSessionError.ptyFailed
            }

            // Start shell
            let shellType = "shell"
            let shellResult = libssh2_channel_process_startup(
                channel, shellType, UInt32(shellType.count), nil, 0
            )
            guard shellResult == 0 else {
                throw SSHSessionError.shellFailed
            }

            // Switch to non-blocking for reads
            libssh2_session_set_blocking(session, 0)

            isConnected = true

            // Start reading
            readTask = Task.detached { [weak self] in
                await self?.readLoop()
            }
        } catch {
            self.error = error.localizedDescription
            self.ssh = nil
        }
    }

    private func readLoop() async {
        let bufferSize = 4096

        while !Task.isCancelled {
            guard let channel = self.shellChannel else { break }
            let lock = self.sessionLock

            // Perform the read on a background queue to avoid async-context lock restrictions
            let result: (data: Data?, eof: Bool, eagain: Bool, error: Bool) = await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    guard lock.try() else {
                        // SFTP is active, skip this cycle
                        continuation.resume(returning: (nil, false, true, false))
                        return
                    }

                    var buffer = [Int8](repeating: 0, count: bufferSize)
                    let bytesRead = libssh2_channel_read_ex(channel, 0, &buffer, bufferSize)
                    lock.unlock()

                    if bytesRead > 0 {
                        let data = Data(bytes: buffer, count: Int(bytesRead))
                        continuation.resume(returning: (data, false, false, false))
                    } else if bytesRead == Int(LIBSSH2_ERROR_EAGAIN) {
                        continuation.resume(returning: (nil, false, true, false))
                    } else if bytesRead < 0 {
                        continuation.resume(returning: (nil, false, false, true))
                    } else {
                        let eof = libssh2_channel_eof(channel) != 0
                        continuation.resume(returning: (nil, eof, false, false))
                    }
                }
            }

            if let data = result.data {
                if let text = String(data: data, encoding: .utf8) {
                    await MainActor.run {
                        self.terminalOutput += text
                    }
                }
            } else if result.error || result.eof {
                await MainActor.run {
                    self.isConnected = false
                }
                break
            } else {
                // EAGAIN or lock contention — brief sleep
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }

    func send(_ text: String) {
        guard let channel = shellChannel else { return }
        guard let session = cSession else { return }

        sessionLock.lock()
        libssh2_session_set_blocking(session, 1)
        let data = Array(text.utf8).map { Int8(bitPattern: $0) }
        _ = libssh2_channel_write_ex(channel, 0, data, data.count)
        libssh2_session_set_blocking(session, 0)
        sessionLock.unlock()
    }

    func sendBytes(_ bytes: [UInt8]) {
        guard let channel = shellChannel else { return }
        guard let session = cSession else { return }

        sessionLock.lock()
        libssh2_session_set_blocking(session, 1)
        let data = bytes.map { Int8(bitPattern: $0) }
        _ = libssh2_channel_write_ex(channel, 0, data, data.count)
        libssh2_session_set_blocking(session, 0)
        sessionLock.unlock()
    }

    func resize(columns: Int, rows: Int) {
        guard let channel = shellChannel else { return }
        libssh2_channel_request_pty_size_ex(channel, Int32(columns), Int32(rows), 0, 0)
    }

    func disconnect() {
        readTask?.cancel()
        readTask = nil

        if let channel = shellChannel {
            libssh2_channel_close(channel)
            libssh2_channel_free(channel)
            shellChannel = nil
        }
        if let session = cSession {
            libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "Bye", "")
            libssh2_session_free(session)
            cSession = nil
        }
        sock?.close()
        sock = nil
        ssh = nil
        isConnected = false
    }

    // SFTP via Shout's SSH object is not usable since we re-created the session
    // Use cSession directly for SFTP
    nonisolated func listRemoteDirectory(_ path: String) async throws -> [FileItem] {
        guard let rawSession = cSession else { throw SSHSessionError.notConnected }
        let sp = SendablePointer(pointer: rawSession)
        let lock = sessionLock

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                lock.lock()
                let session = sp.pointer
                libssh2_session_set_blocking(session, 1)

                guard let sftp = libssh2_sftp_init(session) else {
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(throwing: SSHSessionError.sftpFailed)
                    return
                }

                guard let handle = libssh2_sftp_open_ex(
                    sftp, path, UInt32(path.count),
                    UInt(LIBSSH2_FXF_READ), 0,
                    LIBSSH2_SFTP_OPENDIR
                ) else {
                    libssh2_sftp_shutdown(sftp)
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(throwing: SSHSessionError.sftpFailed)
                    return
                }

                var items: [FileItem] = []
                var buffer = [Int8](repeating: 0, count: 512)
                var attrs = LIBSSH2_SFTP_ATTRIBUTES()

                while true {
                    let rc = libssh2_sftp_readdir_ex(handle, &buffer, 512, nil, 0, &attrs)
                    if rc <= 0 { break }
                    guard let name = String(bytes: buffer.prefix(Int(rc)).map { UInt8(bitPattern: $0) }, encoding: .utf8) else { continue }
                    if name == "." || name == ".." { continue }

                    let isDir = (attrs.flags & UInt(LIBSSH2_SFTP_ATTR_PERMISSIONS)) != 0 &&
                                (attrs.permissions & UInt(LIBSSH2_SFTP_S_IFDIR)) != 0

                    items.append(FileItem(
                        name: name,
                        path: path == "/" ? "/\(name)" : "\(path)/\(name)",
                        size: Int64(attrs.filesize),
                        isDirectory: isDir,
                        modTime: Date(timeIntervalSince1970: TimeInterval(attrs.mtime)),
                        permissions: String(format: "%o", attrs.permissions & 0o777)
                    ))
                }

                libssh2_sftp_close_handle(handle)
                libssh2_sftp_shutdown(sftp)
                libssh2_session_set_blocking(session, 0)
                lock.unlock()
                continuation.resume(returning: items)
            }
        }
    }

    nonisolated func upload(localPath: String, remotePath: String, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard let rawSession = cSession else { throw SSHSessionError.notConnected }
        let sp = SendablePointer(pointer: rawSession)
        let lock = sessionLock

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                guard let localData = try? Data(contentsOf: URL(fileURLWithPath: localPath)) else {
                    continuation.resume(throwing: SSHSessionError.sftpFailed)
                    return
                }
                let totalSize = localData.count

                lock.lock()
                let session = sp.pointer
                libssh2_session_set_blocking(session, 1)

                guard let sftp = libssh2_sftp_init(session) else {
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(throwing: SSHSessionError.sftpFailed)
                    return
                }

                guard let handle = libssh2_sftp_open_ex(
                    sftp, remotePath, UInt32(remotePath.count),
                    UInt(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC),
                    Int(LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR | LIBSSH2_SFTP_S_IRGRP | LIBSSH2_SFTP_S_IROTH),
                    LIBSSH2_SFTP_OPENFILE
                ) else {
                    libssh2_sftp_shutdown(sftp)
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(throwing: SSHSessionError.sftpFailed)
                    return
                }

                var offset = 0
                let chunkSize = 32768

                while offset < totalSize {
                    let end = min(offset + chunkSize, totalSize)
                    let chunk = localData[offset..<end]
                    let written: Int = chunk.withUnsafeBytes { ptr in
                        guard let base = ptr.bindMemory(to: Int8.self).baseAddress else { return 0 }
                        return libssh2_sftp_write(handle, base, chunk.count)
                    }
                    if written < 0 {
                        libssh2_sftp_close_handle(handle)
                        libssh2_sftp_shutdown(sftp)
                        libssh2_session_set_blocking(session, 0)
                        lock.unlock()
                        continuation.resume(throwing: SSHSessionError.sftpFailed)
                        return
                    }
                    offset += written
                    let pct = Double(offset) / Double(totalSize)
                    DispatchQueue.main.async { progress(pct) }
                }

                libssh2_sftp_close_handle(handle)
                libssh2_sftp_shutdown(sftp)
                libssh2_session_set_blocking(session, 0)
                lock.unlock()
                continuation.resume()
            }
        }
    }

    nonisolated func download(remotePath: String, localPath: String, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard let rawSession = cSession else { throw SSHSessionError.notConnected }
        let sp = SendablePointer(pointer: rawSession)
        let lock = sessionLock

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                lock.lock()
                let session = sp.pointer
                libssh2_session_set_blocking(session, 1)

                guard let sftp = libssh2_sftp_init(session) else {
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(throwing: SSHSessionError.sftpFailed)
                    return
                }

                var attrs = LIBSSH2_SFTP_ATTRIBUTES()
                libssh2_sftp_stat_ex(sftp, remotePath, UInt32(remotePath.count), LIBSSH2_SFTP_STAT, &attrs)
                let totalSize = max(Int64(attrs.filesize), 1)

                guard let handle = libssh2_sftp_open_ex(
                    sftp, remotePath, UInt32(remotePath.count),
                    UInt(LIBSSH2_FXF_READ), 0,
                    LIBSSH2_SFTP_OPENFILE
                ) else {
                    libssh2_sftp_shutdown(sftp)
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(throwing: SSHSessionError.sftpFailed)
                    return
                }

                FileManager.default.createFile(atPath: localPath, contents: nil)
                guard let fileHandle = FileHandle(forWritingAtPath: localPath) else {
                    libssh2_sftp_close_handle(handle)
                    libssh2_sftp_shutdown(sftp)
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(throwing: SSHSessionError.sftpFailed)
                    return
                }

                var downloaded: Int64 = 0
                var buffer = [Int8](repeating: 0, count: 32768)

                while true {
                    let rc = libssh2_sftp_read(handle, &buffer, 32768)
                    if rc <= 0 { break }
                    let data = Data(bytes: buffer, count: Int(rc))
                    fileHandle.write(data)
                    downloaded += Int64(rc)
                    let pct = Double(downloaded) / Double(totalSize)
                    DispatchQueue.main.async { progress(pct) }
                }

                fileHandle.closeFile()
                libssh2_sftp_close_handle(handle)
                libssh2_sftp_shutdown(sftp)
                libssh2_session_set_blocking(session, 0)
                lock.unlock()
                continuation.resume()
            }
        }
    }

    /// Check if a remote file/directory exists
    nonisolated func remoteFileExists(_ path: String) async -> Bool {
        guard let rawSession = cSession else { return false }
        let sp = SendablePointer(pointer: rawSession)
        let lock = sessionLock

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                lock.lock()
                let session = sp.pointer
                libssh2_session_set_blocking(session, 1)

                guard let sftp = libssh2_sftp_init(session) else {
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(returning: false)
                    return
                }

                var attrs = LIBSSH2_SFTP_ATTRIBUTES()
                let rc = libssh2_sftp_stat_ex(sftp, path, UInt32(path.count), LIBSSH2_SFTP_STAT, &attrs)

                libssh2_sftp_shutdown(sftp)
                libssh2_session_set_blocking(session, 0)
                lock.unlock()
                continuation.resume(returning: rc == 0)
            }
        }
    }

    /// Rename a remote file
    nonisolated func renameRemote(from oldPath: String, to newPath: String) async throws {
        guard let rawSession = cSession else { throw SSHSessionError.notConnected }
        let sp = SendablePointer(pointer: rawSession)
        let lock = sessionLock

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                lock.lock()
                let session = sp.pointer
                libssh2_session_set_blocking(session, 1)

                guard let sftp = libssh2_sftp_init(session) else {
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(throwing: SSHSessionError.sftpFailed)
                    return
                }

                oldPath.withCString { srcPtr in
                    newPath.withCString { destPtr in
                        _ = libssh2_sftp_rename_ex(sftp, srcPtr, UInt32(strlen(srcPtr)), destPtr, UInt32(strlen(destPtr)), Int(LIBSSH2_SFTP_RENAME_OVERWRITE))
                    }
                }

                libssh2_sftp_shutdown(sftp)
                libssh2_session_set_blocking(session, 0)
                lock.unlock()
                continuation.resume()
            }
        }
    }

    /// Create a remote directory
    nonisolated func mkdirRemote(_ path: String) async throws {
        guard let rawSession = cSession else { throw SSHSessionError.notConnected }
        let sp = SendablePointer(pointer: rawSession)
        let lock = sessionLock

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                lock.lock()
                let session = sp.pointer
                libssh2_session_set_blocking(session, 1)

                guard let sftp = libssh2_sftp_init(session) else {
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(throwing: SSHSessionError.sftpFailed)
                    return
                }

                let mode = Int(LIBSSH2_SFTP_S_IRWXU | LIBSSH2_SFTP_S_IRGRP | LIBSSH2_SFTP_S_IXGRP | LIBSSH2_SFTP_S_IROTH | LIBSSH2_SFTP_S_IXOTH)
                path.withCString { ptr in
                    _ = libssh2_sftp_mkdir_ex(sftp, ptr, UInt32(strlen(ptr)), mode)
                }

                libssh2_sftp_shutdown(sftp)
                libssh2_session_set_blocking(session, 0)
                lock.unlock()
                continuation.resume()
            }
        }
    }

    /// Recursively upload a local directory
    nonisolated func uploadDirectory(localPath: String, remotePath: String, progress: @Sendable @escaping (String) -> Void) async throws {
        // Create remote dir
        try await mkdirRemote(remotePath)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: localPath) else { return }

        while let relativePath = enumerator.nextObject() as? String {
            let fullLocal = (localPath as NSString).appendingPathComponent(relativePath)
            let fullRemote = remotePath + "/" + relativePath

            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullLocal, isDirectory: &isDir)

            if isDir.boolValue {
                try await mkdirRemote(fullRemote)
            } else {
                progress(relativePath)
                try await upload(localPath: fullLocal, remotePath: fullRemote, progress: { _ in })
            }
        }
    }

    /// Recursively download a remote directory
    nonisolated func downloadDirectory(remotePath: String, localPath: String, progress: @Sendable @escaping (String) -> Void) async throws {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: localPath, withIntermediateDirectories: true)

        let items = try await listRemoteDirectory(remotePath)
        for item in items {
            let localDest = (localPath as NSString).appendingPathComponent(item.name)
            if item.isDirectory {
                progress(item.name + "/")
                try await downloadDirectory(remotePath: item.path, localPath: localDest, progress: progress)
            } else {
                progress(item.name)
                try await download(remotePath: item.path, localPath: localDest, progress: { _ in })
            }
        }
    }

    /// Execute a command on a new channel and return its output
    nonisolated func executeCommand(_ command: String) async -> String {
        guard let rawSession = cSession else { return "" }
        let sp = SendablePointer(pointer: rawSession)
        let lock = sessionLock

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                lock.lock()
                let session = sp.pointer
                libssh2_session_set_blocking(session, 1)

                // Open a new exec channel
                let channelType = "session"
                guard let channel = libssh2_channel_open_ex(
                    session, channelType, UInt32(channelType.count),
                    2 * 1024 * 1024, 32768, nil, 0
                ) else {
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(returning: "")
                    return
                }

                let execType = "exec"
                let rc = libssh2_channel_process_startup(
                    channel, execType, UInt32(execType.count),
                    command, UInt32(command.count)
                )
                guard rc == 0 else {
                    libssh2_channel_close(channel)
                    libssh2_channel_free(channel)
                    libssh2_session_set_blocking(session, 0)
                    lock.unlock()
                    continuation.resume(returning: "")
                    return
                }

                // Read all output
                var output = Data()
                var buffer = [Int8](repeating: 0, count: 8192)
                while true {
                    let bytesRead = libssh2_channel_read_ex(channel, 0, &buffer, 8192)
                    if bytesRead > 0 {
                        output.append(Data(bytes: buffer, count: Int(bytesRead)))
                    } else {
                        break
                    }
                }

                libssh2_channel_close(channel)
                libssh2_channel_free(channel)
                libssh2_session_set_blocking(session, 0)
                lock.unlock()

                let result = String(data: output, encoding: .utf8) ?? ""
                continuation.resume(returning: result)
            }
        }
    }
}

enum SSHSessionError: Error, LocalizedError {
    case notConnected
    case initFailed
    case handshakeFailed
    case authFailed
    case channelFailed
    case ptyFailed
    case shellFailed
    case sftpFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected"
        case .initFailed: return "Failed to initialize SSH session"
        case .handshakeFailed: return "SSH handshake failed"
        case .authFailed: return "Authentication failed"
        case .channelFailed: return "Failed to open channel"
        case .ptyFailed: return "Failed to request PTY"
        case .shellFailed: return "Failed to start shell"
        case .sftpFailed: return "SFTP operation failed"
        }
    }
}
