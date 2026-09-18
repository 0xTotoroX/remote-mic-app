import Foundation

// 遥控器 × Mac 端输入工具的能力矩阵（单一事实源）。
//
// 权威文档：公开仓 `remote/遥控器与输入工具能力矩阵.md`。**改这里必须同步改那份文档**，
// 反之亦然：界面该显示什么、语音键该怎么驱动，都只能从这份矩阵推导，不允许在页面里各写一套判断。
//
// 矩阵（2026-09-19 由用户提供并确认；未测试项按原文标注）：
//
//   遥控器            长按收音  按一次收音  触摸面
//   小米 RC001/RC003    ✅        ❌        ❌
//   Chromecase          ✅        ✅        ❌
//   Apple Siri Remote   ✅      未测试      ✅
//
//   输入工具          长按收音  按一次收音
//   Typeless            ❌        ✅
//   豆包输入法           ✅        ✅（长按模式 / 免按模式）
//   微信输入法           ✅        ✅
//   Vokie               ✅        ✅
//   腾讯 ChatterFly      ✅        ✅
//
// 由此得到的搭配规则：
// 1. 「语音键模拟 Fn 点按」只在**不会按一次收音**的遥控器上才有意义（它把「按住」模拟成「点按」，
//    用来驱动只认点按的工具）。Chromecase 自己能按一次收音，页面不得出现该开关。
// 2. 触摸面类设置（滑动/光标）只有具备触摸面的遥控器才显示。
// 3. Chromecase 的语音键驱动方式由它自己的语音模式决定，不读上面的开关。

extension XiaomiRemoteModel {
    /// 是否支持「按一次收音」（按一下开始、再按一下结束）。
    /// 只有 Chromecase 支持：它的语音模式可选 toggle；小米 RC001/RC003 只能按住收音。
    ///
    /// 该判断与私有包型号自报的能力位一一对应（`ChromecaseCapabilityFlags.toggleVoiceGesture`），
    /// 由 `ChromecaseCapabilityContractTests` 跨仓锁定。将来若出现能力不同的新型号，
    /// 这里要改成读取链路自报的能力，而不是继续按型号硬编码。
    var supportsToggleVoiceRecording: Bool {
        isChromecaseRemote
    }

    /// 是否有触摸面（滑动 / 光标）。只有 Apple Siri Remote 具备。
    var supportsTouchSurface: Bool {
        isAppleSiriRemote
    }
}

extension OnboardingVoiceTool {
    /// 是否支持「长按收音」（按住说话、松手结束）。
    /// 已知工具里只有 Typeless 不支持；豆包、微信输入法、Vokie、腾讯 ChatterFly 均支持。
    var supportsHoldVoiceRecording: Bool {
        switch self {
        case .typeless: return false
        case .doubao, .weixin, .unselected, .other: return true
        }
    }
}

/// 「语音键模拟 Fn 点按」的适用性：界面据此决定是否展示该开关。
///
/// 该开关存在的唯一理由是把遥控器的「按住」模拟成「点按」，去驱动只认点按的输入工具。
/// 因此只有在**不支持按一次收音**的遥控器档案页面上才适用；型号未知时保守保留入口。
enum VoiceFunctionKeyTapApplicability {
    static func isApplicable(model: XiaomiRemoteModel?) -> Bool {
        guard let model else { return true }
        return !model.supportsToggleVoiceRecording
    }
}

/// 触摸面类设置（滑动箭头、光标反馈）的适用性。
enum TouchSurfaceControlApplicability {
    /// 页面请求了触摸类控件、且该型号确实有触摸面时才显示。
    static func isApplicable(model: XiaomiRemoteModel?, pageRequestsControl: Bool) -> Bool {
        guard pageRequestsControl else { return false }
        guard let model else { return false }
        return model.supportsTouchSurface
    }
}
