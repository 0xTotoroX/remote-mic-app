import Foundation
import Testing
@testable import RemoteMic

@Suite("Chromecase 语音键驱动（长按式 / 点按式）")
struct ChromecaseFunctionKeyDriveTests {
    // MARK: - 事件形状

    @Test func holdDriveSendsPressOnStartAndReleaseOnStop() {
        // 长按式工具（豆包「长按模式」）：按住说话、松开结束。
        #expect(ChromecaseFunctionKeyDrive.hold.startEvents == [.press])
        #expect(ChromecaseFunctionKeyDrive.hold.stopEvents == [.release])
    }

    @Test func tapsDriveSendsPairedTapsOnBothEdges() {
        // 点按式工具（豆包「免按模式」、Typeless）：开始一次点按、结束再一次点按。
        #expect(ChromecaseFunctionKeyDrive.taps.startEvents == [.press, .release])
        #expect(ChromecaseFunctionKeyDrive.taps.stopEvents == [.press, .release])
    }

    @Test func startOfTapsDriveAlwaysReleasesTheKey() {
        // 开始的点按必须自己松开：否则 Fn 修饰位在整个会话期间被按住，
        // 用户此时打字会变成 Fn 组合键。
        #expect(ChromecaseFunctionKeyDrive.taps.startEvents.last == .release)
    }

    @Test func stopOfTapsDriveAlwaysPressesTheKey() {
        // 真机实测（Testing/VoiceKeyFnPanelProbe.swift）：点按式工具对「松开」无反应，
        // 结束必须再给一次「按下」，否则真机表现就是「按一下结束不生效、要再按一下」。
        #expect(ChromecaseFunctionKeyDrive.taps.stopEvents.first == .press)
    }

    // MARK: - 设置解析

    @Test func tapModeResolvesToTapsOnlyInFunctionKeyMode() {
        #expect(
            ChromecaseFunctionKeyDrive.resolve(
                fnTapModeEnabled: true,
                voiceKeyMode: .function
            ) == .taps
        )
        // 开关关闭（含豆包「长按模式」这类按既有建议配置的场景）：保持按住—松开。
        #expect(
            ChromecaseFunctionKeyDrive.resolve(
                fnTapModeEnabled: false,
                voiceKeyMode: .function
            ) == .hold
        )
        // 点按兼容只对 Fn 模式开放（Command 等模式沿用既有长按语义）。
        #expect(
            ChromecaseFunctionKeyDrive.resolve(
                fnTapModeEnabled: true,
                voiceKeyMode: .rightCommand
            ) == .hold
        )
    }
}
