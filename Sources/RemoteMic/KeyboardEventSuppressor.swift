import AppKit
import CoreGraphics
import Foundation

private func keyboardEventSuppressorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let suppressor = Unmanaged<KeyboardEventSuppressor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return suppressor.handle(type: type, event: event)
        ? nil
        : Unmanaged.passUnretained(event)
}

private func keyboardEventSuppressorProbeCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    Unmanaged<KeyboardEventSuppressor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
        .handleProbe(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

final class KeyboardEventSuppressor {
    private static let systemDefinedEventTypeRawValue: UInt32 = 14

    private struct PendingEvent {
        let event: RemoteNativeEvent
        let edge: RemoteEventEdge
        let expiresAt: TimeInterval
    }

    private let lock = NSLock()
    private var pendingEvents: [PendingEvent] = []
    private var heldEventCounts: [RemoteNativeEvent: Int] = [:]
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// 最近 arm 过的事件（带过期时刻），仅用于诊断日志：只有与这些事件相关的
    /// 未命中才值得记录，避免被无关键盘输入淹没。
    private var recentArmed: [(event: RemoteNativeEvent, until: TimeInterval)] = []

    private(set) var isRunning = false

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << Self.systemDefinedEventTypeRawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keyboardEventSuppressorCallback,
            userInfo: context
        ) else {
            return false
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        lock.lock()
        pendingEvents.removeAll()
        heldEventCounts.removeAll()
        lock.unlock()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }

    func arm(button: RemoteButton, edge: RemoteEventEdge) {
        arm(nativeEvents: button.nativeEvents, edge: edge)
    }

    func arm(nativeEvents: Set<RemoteNativeEvent>, edge: RemoteEventEdge) {
        guard !nativeEvents.isEmpty else { return }
        // 诊断：留证「本次预定了什么」，便于与 miss 日志里系统真实事件对照。
        AppLogger.shared.write(
            "HID FILTER arm events=\(nativeEvents.map(Self.logToken).sorted().joined(separator: "+")) "
                + "edge=\(edge == .down ? "down" : "up")"
        )
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        recentArmed.removeAll { $0.until <= now }
        for nativeEvent in nativeEvents {
            recentArmed.append((event: nativeEvent, until: now + 1.0))
        }
        pendingEvents.removeAll { $0.expiresAt <= now }
        for nativeEvent in nativeEvents {
            switch edge {
            case .down:
                heldEventCounts[nativeEvent, default: 0] += 1
                pendingEvents.append(PendingEvent(
                    event: nativeEvent,
                    edge: edge,
                    expiresAt: now + 0.18
                ))
            case .up:
                if let pendingDownIndex = pendingEvents.firstIndex(where: {
                    $0.event == nativeEvent && $0.edge == .down
                }) {
                    pendingEvents.remove(at: pendingDownIndex)
                }
                let remaining = (heldEventCounts[nativeEvent] ?? 0) - 1
                if remaining > 0 {
                    heldEventCounts[nativeEvent] = remaining
                } else {
                    heldEventCounts.removeValue(forKey: nativeEvent)
                }
                pendingEvents.append(PendingEvent(
                    event: nativeEvent,
                    edge: edge,
                    expiresAt: now + 0.18
                ))
            }
        }
        if pendingEvents.count > 32 {
            pendingEvents.removeFirst(pendingEvents.count - 32)
        }
        lock.unlock()
    }

    /// 诊断探针：在 HID 层（`cghidEventTap`，早于 suppressor 所在的 session 层）挂一个
    /// **只读**事件 tap。用于判断「媒体事件是否在更早的层就出现」——若 session 层看不到、
    /// HID 层能看到，说明事件被系统在两层之间消费（例如系统遥控器/媒体服务），
    /// 需要把抑制前移到 HID 层；若两层都看不到，则事件完全不走 CGEvent 路径。
    private var probeTap: CFMachPort?
    private var probeRunLoopSource: CFRunLoopSource?
    private var probeLogCount = 0

    /// 启动 HID 层探针（只观察，不吞事件）。幂等。
    func startHIDLayerProbe() {
        guard probeTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << Self.systemDefinedEventTypeRawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyboardEventSuppressorProbeCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AppLogger.shared.write("HID PROBE result=create_failed")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            AppLogger.shared.write("HID PROBE result=source_failed")
            return
        }
        probeTap = tap
        probeRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        AppLogger.shared.write("HID PROBE result=ready layer=cghid")
    }

    func stopHIDLayerProbe() {
        if let source = probeRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = probeTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        probeRunLoopSource = nil
        probeTap = nil
    }

    /// 探针记录：媒体类事件（systemDefined）与 arm 窗口内的按键事件都要留证。
    fileprivate func handleProbe(type: CGEventType, event: CGEvent) {
        guard let descriptor = descriptor(type: type, event: event) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let armedExactly = recentArmed.contains { $0.event == descriptor.event && $0.until > now }
        let withinArmedWindow = !recentArmed.isEmpty
        lock.unlock()
        let isSystemDefined = type.rawValue == Self.systemDefinedEventTypeRawValue
        guard isSystemDefined || armedExactly || withinArmedWindow else { return }
        probeLogCount += 1
        guard probeLogCount <= 40 || probeLogCount % 50 == 0 else { return }
        AppLogger.shared.write(
            "HID PROBE type=\(type.rawValue) event=\(Self.logToken(descriptor.event)) "
                + "edge=\(descriptor.edge == .down ? "down" : "up") armed=\(armedExactly)"
        )
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == KeyboardInjector.syntheticEventMarker {
            return false
        }
        guard let descriptor = descriptor(type: type, event: event) else { return false }

        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        pendingEvents.removeAll { $0.expiresAt <= now }
        if let matchIndex = pendingEvents.firstIndex(where: {
            $0.event == descriptor.event && $0.edge == descriptor.edge
        }) {
            pendingEvents.remove(at: matchIndex)
            lock.unlock()
            // 诊断：命中并吞掉——与 miss 日志对照即可判定「系统是否产生了该事件」。
            AppLogger.shared.write(
                "HID FILTER suppressed event=\(Self.logToken(descriptor.event)) "
                    + "edge=\(descriptor.edge == .down ? "down" : "up") type=\(type.rawValue)"
            )
            return true
        }
        if descriptor.edge == .down, (heldEventCounts[descriptor.event] ?? 0) > 0 {
            if type == .keyDown,
               event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                heldEventCounts.removeValue(forKey: descriptor.event)
                lock.unlock()
                AppLogger.shared.write(
                    "HID FILTER suppressed event=\(Self.logToken(descriptor.event)) "
                        + "edge=down type=\(type.rawValue) via=held"
                )
                return false
            }
            lock.unlock()
            return true
        }
        let pendingCount = pendingEvents.count
        // 诊断范围（187 的教训：条件太窄会漏掉「系统事件与预定键码不同」的情况）：
        //   1) 与预定键码一致但没被吞（窗口过期）；
        //   2) 任意 systemDefined（媒体/音量类，我们关心的正是这些）；
        //   3) 最近 1 秒内曾 arm 过（覆盖「系统产生的键码与我们预定的不同」）。
        let armedExactly = recentArmed.contains { $0.event == descriptor.event && $0.until > now }
        let isSystemDefined = type.rawValue == Self.systemDefinedEventTypeRawValue
        let withinArmedWindow = !recentArmed.isEmpty
        lock.unlock()
        if armedExactly || isSystemDefined || withinArmedWindow {
            AppLogger.shared.write(
                "HID FILTER miss type=\(type.rawValue) event=\(Self.logToken(descriptor.event)) "
                    + "edge=\(descriptor.edge == .down ? "down" : "up") "
                    + "armed=\(armedExactly) pending=\(pendingCount)"
            )
        }
        return false
    }

    private static func logToken(_ event: RemoteNativeEvent) -> String {
        switch event {
        case .keyboard(let keyCode): return "key\(keyCode)"
        case .systemKey(let type): return "sys\(type)"
        }
    }

    private func descriptor(
        type: CGEventType,
        event: CGEvent
    ) -> (event: RemoteNativeEvent, edge: RemoteEventEdge)? {
        if type.rawValue == Self.systemDefinedEventTypeRawValue {
            guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
            let systemKeyType = Int32((nsEvent.data1 & 0xFFFF_0000) >> 16)
            let keyState = (nsEvent.data1 & 0x0000_FF00) >> 8
            let edge: RemoteEventEdge
            switch keyState {
            case 0xA: edge = .down
            case 0xB: edge = .up
            default: return nil
            }
            return (.systemKey(type: systemKeyType), edge)
        }

        switch type {
        case .keyDown, .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return (.keyboard(keyCode: keyCode), type == .keyDown ? .down : .up)
        default:
            return nil
        }
    }
}
