import AppKit
import Darwin

/// Temporary, restricted Typeless test transport. Queue acceptance is not delivery.
final class VirtualHIDShortcutBridge {
    enum SubmissionResult: String {
        case acknowledged, unavailable, writeFailed = "write_failed"
        case readFailed = "read_failed", timedOut = "timed_out", rejected, expired
    }

    static let shared = VirtualHIDShortcutBridge()
    private let queue = DispatchQueue(label: "com.hd838a.RemoteMic.virtual-hid-shortcuts")
    private let lock = NSLock()
    private var nextOperationID: UInt64 = 0
    private let transport: (UInt8) -> SubmissionResult
    private let logger: (String) -> Void
    private let now: () -> TimeInterval

    init(
        transport: @escaping (UInt8) -> SubmissionResult = VirtualHIDShortcutBridge.postCommand,
        logger: @escaping (String) -> Void = { AppLogger.shared.write($0) },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.transport = transport
        self.logger = logger
        self.now = now
    }

    func enqueue(_ command: UInt8, completion: @escaping (SubmissionResult) -> Void = { _ in }) {
        // Serialize insertion as well as execution to preserve caller order.
        lock.lock()
        defer { lock.unlock() }
        nextOperationID += 1
        let operationID = nextOperationID
        let requestedAt = now()
        logger("SHORTCUT BRIDGE operation_id=\(operationID) phase=queued receiver=unknown")
        queue.async { [self] in
            let result: SubmissionResult
            if now() - requestedAt >= 1 {
                result = .expired
            } else {
                logger("SHORTCUT BRIDGE operation_id=\(operationID) phase=sending receiver=unknown")
                result = transport(command)
            }
            let elapsed = Int((now() - requestedAt) * 1_000)
            logger(
                "SHORTCUT BRIDGE operation_id=\(operationID) phase=completed " +
                    "result=\(result.rawValue) elapsed_ms=\(elapsed) receiver=unknown"
            )
            completion(result)
        }
    }

    static let socketPath = "/var/run/sayall-vhid-bridge.sock"
    static var isTestBuild: Bool {
        Bundle.main.bundleIdentifier == "com.hd838a.RemoteMic.TypelessTest"
    }

    static func command(for shortcut: CustomKeyboardShortcut) -> UInt8? {
        guard shortcut.modifierFlags == [.control, .option] else { return nil }
        switch shortcut.keyCode {
        case 9: return 118 // V
        case 17: return 116 // T
        case 12: return 113 // Q
        default: return nil
        }
    }

    /// Returns nil when the shortcut is outside this bridge's restricted protocol.
    static func enqueueIfSupported(_ shortcut: CustomKeyboardShortcut) -> Bool? {
        guard isTestBuild, let command = command(for: shortcut) else { return nil }
        shared.enqueue(command)
        return true
    }

    private static func postCommand(_ value: UInt8) -> SubmissionResult {
        var command = value
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .unavailable }
        defer { Darwin.close(descriptor) }

        var noSignal: Int32 = 1
        _ = withUnsafePointer(to: &noSignal) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            _ = Darwin.setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
            return Darwin.setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }

        let pathBytes = Array(socketPath.utf8CString)
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return .unavailable }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        guard let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) else { return .unavailable }
        pathBytes.withUnsafeBufferPointer { source in
            withUnsafeMutablePointer(to: &address) { destination in
                _ = memcpy(
                    UnsafeMutableRawPointer(destination).advanced(by: pathOffset),
                    source.baseAddress,
                    pathBytes.count
                )
            }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return .unavailable }
        guard Darwin.write(descriptor, &command, 1) == 1 else { return .writeFailed }
        var response: UInt8 = 0
        guard Darwin.read(descriptor, &response, 1) == 1 else {
            return errno == EAGAIN || errno == EWOULDBLOCK ? .timedOut : .readFailed
        }
        return response == 49 ? .acknowledged : .rejected
    }
}
