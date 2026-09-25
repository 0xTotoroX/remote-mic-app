# 切歌动作错误依赖前台应用

用户确认旧 Command+方向键映射仅在 Apple Music 前台切歌，Codex 前台无效。根因是 KeyboardInjector 的上一首/下一首实际发送普通键盘快捷键。

移植上游 [PR #428](https://github.com/HD838A/remote-mic-app/pull/428) 的相关修复：沿用已有系统媒体事件发送器，上一首为 18，下一首为 17，播放/暂停为 16；保留旧动作 raw value 并更新中英文名称。用户配置调整为音量单击调音量、双击切歌。未引入该 PR 的 Dock 或菜单改动。

自动化及实际验收边界见 [测试手册](../Testing/TypelessVirtualHIDShortcuts.md#系统媒体切歌与音量双击2284-候选)。不保证系统媒体接收者固定为 Apple Music，不能将提交事件等同于成功切歌。
