# Global Speed 长按动作向输入框写入数字

用户在 Codex 中长按确定键，得到数字 5。个人配置将确定长按映射为 Numpad5（Global Speed 恢复 1×），旧 HID 动作分发没有前台或输入焦点限制，故普通键盘注入会写入文本框。

修复仅作用于 TypelessTest 包中的五个精确视频长按映射：通过公开 AX 检查 Chrome 网页非编辑焦点，否则消费动作并跳过发送。单击 Typeless、手势阈值、原始按键中和及虚拟键盘桥不变。未知焦点保守跳过；不读取网页内容或扩展内部数据。

自动化和真实设备验收见 [测试手册](../Testing/TypelessVirtualHIDShortcuts.md#global-speed-长按输入保护2283-历史配置)。用户已反馈 228.3 本轮复测通过；逐项验收范围见测试手册。
