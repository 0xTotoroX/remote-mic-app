import Foundation
import Testing
@testable import RemoteMic

/// 能力矩阵的回归保护：**这里的断言必须与公开仓 `remote/遥控器与输入工具能力矩阵.md` 一致**。
/// 界面该显示什么、语音键该怎么驱动，都从这份矩阵推导；矩阵变了，这里和文档一起改。
@Suite("能力矩阵：遥控器 × 输入工具")
struct VoiceInputCapabilityMatrixTests {
    // MARK: - 遥控器

    @Test func onlyChromecaseSupportsTapOnceRecording() {
        // 小米 RC001/RC003 只能按住收音；Apple Siri Remote 的「按一次」尚未测试，
        // 因此一律按「不支持」处理，不得对外显示该能力。
        #expect(!XiaomiRemoteModel.rc003.supportsToggleVoiceRecording)
        #expect(!XiaomiRemoteModel.rc001.supportsToggleVoiceRecording)
        #expect(!XiaomiRemoteModel.appleSiriRemoteA2854.supportsToggleVoiceRecording)
        #expect(!XiaomiRemoteModel.appleSiriRemoteA2540.supportsToggleVoiceRecording)
        #expect(XiaomiRemoteModel.chromecaseVoiceRemote.supportsToggleVoiceRecording)
    }

    @Test func onlyAppleSiriRemoteHasATouchSurface() {
        #expect(XiaomiRemoteModel.appleSiriRemoteA2854.supportsTouchSurface)
        #expect(XiaomiRemoteModel.appleSiriRemoteA2540.supportsTouchSurface)
        #expect(!XiaomiRemoteModel.rc001.supportsTouchSurface)
        #expect(!XiaomiRemoteModel.rc003.supportsTouchSurface)
        #expect(!XiaomiRemoteModel.chromecaseVoiceRemote.supportsTouchSurface)
    }

    // MARK: - 输入工具

    @Test func onlyTypelessLacksHoldToTalk() {
        #expect(!OnboardingVoiceTool.typeless.supportsHoldVoiceRecording)
        #expect(OnboardingVoiceTool.doubao.supportsHoldVoiceRecording)
        #expect(OnboardingVoiceTool.weixin.supportsHoldVoiceRecording)
        #expect(OnboardingVoiceTool.other.supportsHoldVoiceRecording)
        #expect(OnboardingVoiceTool.unselected.supportsHoldVoiceRecording)
    }

    // MARK: - 界面门禁

    @Test func fnTapSwitchIsNotOfferedForTapOnceRemotes() {
        // 用户要求：Chromecase 的按键页不得出现「语音键模拟 Fn 点按」——它自己就能按一次收音。
        #expect(!VoiceFunctionKeyTapApplicability.isApplicable(model: .chromecaseVoiceRemote))
    }

    @Test func fnTapSwitchStaysAvailableForHoldOnlyRemotes() {
        // 只能按住收音的遥控器保留入口：它是驱动 Typeless 的唯一办法。
        #expect(VoiceFunctionKeyTapApplicability.isApplicable(model: .rc003))
        #expect(VoiceFunctionKeyTapApplicability.isApplicable(model: .rc001))
        #expect(VoiceFunctionKeyTapApplicability.isApplicable(model: .appleSiriRemoteA2854))
        // 型号未知时保守保留，避免升级后入口突然消失。
        #expect(VoiceFunctionKeyTapApplicability.isApplicable(model: nil))
    }

    @Test func touchControlsNeverAppearWithoutATouchSurface() {
        // 页面即使请求触摸类控件，没有触摸面的型号也不显示。
        #expect(
            TouchSurfaceControlApplicability.isApplicable(
                model: .appleSiriRemoteA2854,
                pageRequestsControl: true
            )
        )
        #expect(
            !TouchSurfaceControlApplicability.isApplicable(
                model: .rc003,
                pageRequestsControl: true
            )
        )
        #expect(
            !TouchSurfaceControlApplicability.isApplicable(
                model: .chromecaseVoiceRemote,
                pageRequestsControl: true
            )
        )
        // 页面没请求就不显示（默认路径）。
        #expect(
            !TouchSurfaceControlApplicability.isApplicable(
                model: .appleSiriRemoteA2854,
                pageRequestsControl: false
            )
        )
        #expect(
            !TouchSurfaceControlApplicability.isApplicable(
                model: nil,
                pageRequestsControl: true
            )
        )
    }
}
