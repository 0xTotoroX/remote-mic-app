import Foundation
import XCTest
@testable import RemoteMic

final class VirtualHIDShortcutBridgeTests: XCTestCase {
    @MainActor
    func testSlowBridgeDoesNotBlockMainRunLoop() async {
        let mainResponsive = expectation(description: "main run loop remains responsive")
        let finished = expectation(description: "bridge acknowledged")
        let release = DispatchSemaphore(value: 0)
        let bridge = VirtualHIDShortcutBridge(transport: { _ in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(release.wait(timeout: .now() + 2), .success)
            return .acknowledged
        }, logger: { _ in })

        bridge.enqueue(118) { result in
            XCTAssertEqual(result, .acknowledged)
            finished.fulfill()
        }
        DispatchQueue.main.async {
            mainResponsive.fulfill()
            release.signal()
        }
        await fulfillment(of: [mainResponsive, finished], timeout: 3)
    }

    func testRequestsStayOrderedAndFailureDoesNotReplayOrBlockRecovery() async {
        let finished = expectation(description: "three requests completed once")
        finished.expectedFulfillmentCount = 3
        finished.assertForOverFulfill = true
        var commands: [UInt8] = []
        var results: [VirtualHIDShortcutBridge.SubmissionResult] = []
        let bridge = VirtualHIDShortcutBridge(transport: { command in
            commands.append(command)
            return command == 118 ? .timedOut : .acknowledged
        }, logger: { _ in })
        for command: UInt8 in [118, 116, 113] {
            bridge.enqueue(command) { result in
                results.append(result)
                finished.fulfill()
            }
        }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(commands, [118, 116, 113])
        XCTAssertEqual(results, [.timedOut, .acknowledged, .acknowledged])
    }

    func testStaleQueuedShortcutIsNotSentAfterSlowRequest() async {
        let finished = expectation(description: "both requests completed")
        finished.expectedFulfillmentCount = 2
        let release = DispatchSemaphore(value: 0)
        let clock = BridgeTestClock()
        var commands: [UInt8] = []
        var results: [VirtualHIDShortcutBridge.SubmissionResult] = []
        let bridge = VirtualHIDShortcutBridge(transport: { command in
            commands.append(command)
            XCTAssertEqual(release.wait(timeout: .now() + 2), .success)
            clock.advance()
            return .timedOut
        }, logger: { _ in }, now: { clock.read() })
        for command: UInt8 in [118, 116] {
            bridge.enqueue(command) { result in
                results.append(result)
                finished.fulfill()
            }
        }
        release.signal()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(commands, [118])
        XCTAssertEqual(results, [.timedOut, .expired])
    }
}

private final class BridgeTestClock {
    private let lock = NSLock()
    private var time: TimeInterval = 0

    func read() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return time
    }

    func advance() {
        lock.lock()
        time += 2
        lock.unlock()
    }
}
