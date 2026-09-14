import Foundation
import Testing
@testable import RemoteMic

@Suite("Chromecase integration")
struct ChromecaseIntegrationTests {
    // MARK: - 语音键隔离

    @Test func voiceKeyLatchKeepsHardwareOwnersIndependent() {
        var latch = VoiceFunctionKeyLatch()

        // Siri Remote 先按住。
        #expect(latch.transition(streaming: true, owner: .appleRemote) == .press)
        // Chromecase 同时按住：不得产生第二次按下，也不得取消 Siri。
        #expect(latch.transition(streaming: true, owner: .chromecase) == nil)
        #expect(latch.isHeld)
        // Siri 松手：Chromecase 仍按住，语音键不得抬起。
        #expect(latch.transition(streaming: false, owner: .appleRemote) == nil)
        #expect(latch.isHeld)
        // Chromecase 松手：此时才真正抬起。
        #expect(latch.transition(streaming: false, owner: .chromecase) == .release)
        #expect(!latch.isHeld)
    }

    @Test func chromecasePressesAndReleasesVoiceKeyOnItsOwn() {
        var latch = VoiceFunctionKeyLatch()

        #expect(latch.transition(streaming: true, owner: .chromecase) == .press)
        #expect(latch.isHeld)
        #expect(latch.transition(streaming: false, owner: .chromecase) == .release)
        #expect(!latch.isHeld)
    }

    @Test func chromecaseOwnerIsDistinctFromEveryOtherHardware() {
        let owners: Set<VoiceFunctionKeyLatch.Owner> = [
            .bluetooth,
            .appleRemote,
            .chromecase,
            .mobile,
        ]
        #expect(owners.count == 4)
    }

    // MARK: - 产品默认值

    @Test func productDefaultVoiceModeIsToggle() {
        // 需求：toggle 为默认语音模式，hold 保留给用户可选切换。
        #expect(ChromecaseVoiceMode.productDefault == .toggle)
        #expect(ChromecaseVoiceMode.allCases == [.toggle, .hold])
    }

    @Test func everyLinkStatusHasALocalizationKey() {
        let statuses: [ChromecaseLinkStatus] = [
            .unavailable,
            .disabled,
            .searching,
            .connecting,
            .unauthorized,
            .unsupported(reason: "8 kHz"),
            .connected(displayName: "remote"),
            .disconnected,
        ]
        for status in statuses {
            #expect(status.localizationKey.hasPrefix("chromecase."))
        }
        #expect(ChromecaseLinkStatus.connected(displayName: "x").isConnected)
        #expect(ChromecaseLinkStatus.connected(displayName: "x").isActive)
        #expect(!ChromecaseLinkStatus.disabled.isActive)
    }

    @Test func voiceEndReasonsDistinguishNormalFromForced() {
        #expect(ChromecaseVoiceEndReason.holdRelease.isNormal)
        #expect(ChromecaseVoiceEndReason.toggleSecondTap.isNormal)
        #expect(!ChromecaseVoiceEndReason.hostStop.isNormal)
        #expect(!ChromecaseVoiceEndReason.cancelled("link_unavailable").isNormal)
    }

    // MARK: - 缺包时的退化行为

    @Test func integrationIsInertWhenPrivatePackageIsAbsent() {
        // 未编入私有包时，接入层必须完全惰性：不崩、不产生任何回调。
        guard !ChromecaseFeatureIntegration.isPackageIncluded else { return }
        let integration = ChromecaseFeatureIntegration()
        var eventCount = 0
        integration.onVoiceStart = { eventCount += 1 }
        integration.onVoiceSustain = { eventCount += 1 }
        integration.onVoiceStop = { _ in eventCount += 1 }
        integration.onSamples = { _, _ in eventCount += 1 }
        integration.onStatusChange = { _ in eventCount += 1 }

        integration.start()
        integration.setVoiceMode(.hold)
        integration.reconnect()
        integration.notifyHostVoiceSessionEnded()
        integration.stop()

        #expect(eventCount == 0)
    }

    // MARK: - 打包与接线契约

    @Test func chromecasePackageStaysOptionalForHostBuilds() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageSource = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let buildSource = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOf: root.appendingPathComponent("Sources/RemoteMic/BridgeAppModel.swift"),
            encoding: .utf8
        )

        #expect(packageSource.contains("SAYALL_CHROMECASE_PACKAGE_PATH"))
        #expect(packageSource.contains("SAYALL_CHROMECASE_ENABLED"))
        #expect(packageSource.contains("SayAllChromecase"))
        #expect(buildSource.contains("SAYALL_CHROMECASE_INCLUDED=false"))
        #expect(buildSource.contains("SayAllChromecaseIncluded"))
        #expect(modelSource.contains("#if SAYALL_CHROMECASE_ENABLED"))
        #expect(modelSource.contains("owner: .chromecase"))
        #expect(modelSource.contains("receiveChromecaseAudio"))
        // 缺失私有包必须是普通的代码路径，不能是构建期 fatalError。
        #expect(!packageSource.contains("fatalError(\"SAYALL_CHROMECASE"))
    }

    @Test func chromecasePanelChangesReachTheRuntimeWithoutRestart() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsView = try String(
            contentsOf: root.appendingPathComponent("Sources/RemoteMic/SettingsView.swift"),
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOf: root.appendingPathComponent("Sources/RemoteMic/BridgeAppModel.swift"),
            encoding: .utf8
        )

        // 面板里开关与模式选择必须走同一条「立即作用于运行时」的入口。
        #expect(settingsView.contains("model.applyChromecaseSettings()"))
        // 模式推送必须真的发生在运行入口里，而不是只写偏好。
        #expect(modelSource.contains("chromecaseFeature.setVoiceMode(settings.chromecaseVoiceMode)"))
        #expect(modelSource.contains("func applyChromecaseSettings()"))
    }

    @Test func chromecaseNeverCapturesFromTheComputerMicrophone() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelSource = try String(
            contentsOf: root.appendingPathComponent("Sources/RemoteMic/BridgeAppModel.swift"),
            encoding: .utf8
        )
        // 第一版只走遥控器麦克风到 MiRemoteV 2ch，不做混音、不回退电脑麦克风。
        #expect(modelSource.contains("route=MiRemoteV_2ch"))
        #expect(!modelSource.contains("chromecaseAudioMixer"))
    }
}
