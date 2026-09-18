import Foundation

/// 语音键在目标工具上的一次事件。
enum ChromecaseFunctionKeyEvent: Equatable {
    case press
    case release
}

/// 语音键的两种驱动方式。
///
/// 目标工具分两类，语音键的语义必须跟着分：
/// - `hold`：**长按式**工具（豆包「长按模式」、微信输入法等）——按住说话、松开结束。
/// - `taps`：**点按式**工具（豆包「免按模式」、Typeless 等）——按一次开始，再按一次（或再按任意键）
///   结束；**松开不产生任何作用**。
///
/// `taps` 的依据（2026-09-18 真机实测，`Testing/VoiceKeyFnPanelProbe.swift`）：向豆包注入 Fn 按下 →
/// 语音面板出现；注入 Fn 松开并等待 2.5 秒 → 面板仍在；再注入一次按下 → 面板消失；又按下 → 再次出现。
/// 即豆包「免按模式」只在**按下**时切换状态。若沿用 `hold`（一个会话只发一次按下、松开一次），
/// 豆包的状态每**两个**会话才翻转一次——真机表现就是「按一下结束，电平图不消失；再按一下才结束，
/// 但遥控器灯又亮了（因为那一次已经是下一个会话的开始）」。
struct ChromecaseFunctionKeyDrive: Equatable {
    /// 开始收音时要发出的事件序列。
    let startEvents: [ChromecaseFunctionKeyEvent]
    /// 结束收音时要发出的事件序列。
    let stopEvents: [ChromecaseFunctionKeyEvent]

    /// 按住—松开：开始按下（保持按住），结束松开。
    static let hold = ChromecaseFunctionKeyDrive(
        startEvents: [.press],
        stopEvents: [.release]
    )

    /// 成对点按：开始按下并立即松开（一次点按），结束时再按下并松开（第二次点按）。
    ///
    /// 开始处必须**松开**：否则 Fn 修饰位在整个会话期间一直被按住，用户此时打字会变成 Fn 组合键
    /// （例如 Fn+Delete 是前向删除），而点按式工具根本不需要这个按住状态。
    static let taps = ChromecaseFunctionKeyDrive(
        startEvents: [.press, .release],
        stopEvents: [.press, .release]
    )

    /// 由设置决定驱动方式：仅 Fn/地球键模式支持「语音键模拟 Fn 点按」。
    ///
    /// 注意：这里只看设置本身，不看「Fn 点按硬件映射是否已生效」（启动日志里的
    /// `VOICE FN TAP mode_pending_mapping`）。那条门禁是为**硬件语音键**（RC003 的 F5 类按键）准备的——
    /// 中和未生效时若再发软件 Fn 会出现双份事件。Chromecase 的语音键走 ATVV 语音通道、
    /// 不产生任何 HID Fn（启动日志 `VOICE FN MAPPING matched=0`），因此不受该门禁约束。
    static func resolve(
        fnTapModeEnabled: Bool,
        voiceKeyMode: VoiceKeyMode
    ) -> ChromecaseFunctionKeyDrive {
        fnTapModeEnabled && voiceKeyMode == .function ? .taps : .hold
    }
}
