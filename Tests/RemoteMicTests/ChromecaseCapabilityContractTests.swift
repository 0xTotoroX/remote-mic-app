import Foundation
import Testing
@testable import RemoteMic

#if SAYALL_CHROMECASE_ENABLED && canImport(SayAllChromecase)
import SayAllChromecase

/// 跨仓一致性校验：**宿主的能力判断必须与私有包型号自报的能力声明一致**，
/// 且两者都必须与说明文档 `remote/遥控器与输入工具能力矩阵.md` 里写的相符。
///
/// 这样「文档说 Chromecase 支持按一次、不支持触摸面」就不再只是界面里的硬编码：
/// 任何一侧的声明被改动（新增型号、改能力位）都会在这里失败，逼着三处一起改。
@Suite("Chromecase 能力契约（跨仓一致性）")
struct ChromecaseCapabilityContractTests {
    private var declared: ChromecaseCapabilityFlags {
        ChromecaseRemoteModel.chromecastVoiceRemote.capabilities
    }

    @Test func modelDeclaresTheMatrixCapabilities() {
        #expect(declared.contains(.controlEdges))
        #expect(declared.contains(.voiceStream))
        #expect(declared.contains(.toggleVoiceGesture))
        // 文档：Chromecase 无触摸面、不宣告电池。两者都必须保持缺席。
        #expect(!declared.contains(.touchSurface))
        #expect(!declared.contains(.battery))
    }

    @Test func declaredGestureModesCoverHoldAndTapOnce() {
        // 文档：Chromecase 长按收音 ✅、按一次收音 ✅。
        #expect(
            ChromecaseRemoteModel.chromecastVoiceRemote.supportedVoiceGestureModes == [.toggle, .hold]
        )
    }

    @Test func hostCapabilityTableMatchesTheDeclaration() {
        #expect(
            XiaomiRemoteModel.chromecaseVoiceRemote.supportsToggleVoiceRecording
                == declared.contains(.toggleVoiceGesture)
        )
        #expect(
            XiaomiRemoteModel.chromecaseVoiceRemote.supportsTouchSurface
                == declared.contains(.touchSurface)
        )
    }

    @Test func hostBatteryPolicyMatchesTheDeclaration() {
        let model = XiaomiRemoteModel.chromecaseVoiceRemote
        // 型号不宣告电池时，界面不得显示永远是「未知」的电量位。
        #expect(
            RemoteBatteryPresentationPolicy.shouldShowBattery(
                model: model,
                level: 87,
                powerState: .onBattery
            ) == declared.contains(.battery)
        )
    }

    @Test func tapOnceSupportDrivesTheSwitchVisibility() {
        // 不会按一次收音的型号才需要「语音键模拟 Fn 点按」；Chromecase 会，因此不显示。
        #expect(!VoiceFunctionKeyTapApplicability.isApplicable(model: .chromecaseVoiceRemote))
        #expect(
            VoiceFunctionKeyTapApplicability.isApplicable(model: .chromecaseVoiceRemote)
                == !declared.contains(.toggleVoiceGesture)
        )
    }
}
#endif
