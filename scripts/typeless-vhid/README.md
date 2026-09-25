# Typeless 实验桥源码存档

`bridge.cpp` 保存候选构建 228.2 正在使用的本地桥源码；原文件位于临时目录。本目录用于恢复实验环境，不是正式安装器，不会被 App 构建自动编译或启动。

依赖：[pqrs Karabiner-DriverKit-VirtualHIDDevice v8.5.0](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/v8.5.0) 的公开源码（包含 `vendor/vendor/include`）以及同版已启用的官方驱动和 daemon。使用 Xcode C++ 编译器：

```sh
# 在仓库根目录执行；将路径替换为解压后的官方源码目录。
vhid_source=/path/to/Karabiner-DriverKit-VirtualHIDDevice-8.5.0
mkdir -p dist
xcrun clang++ -std=c++23 -O2 -pthread \
  -I "$vhid_source/include" -I "$vhid_source/vendor/vendor/include" \
  scripts/typeless-vhid/bridge.cpp -o dist/sayall-vhid-bridge
```

桥需要管理员权限，与官方 daemon 配合运行。唯一参数为允许连接的非 root 用户 UID；使用 `/var/run/sayall-vhid-bridge.sock`，权限 `0600`，并检查连接方 UID。只接受 `v`、`t`、`q`，发送固定的左 Control + 左 Option + V/T/Q。回执只表示提交虚拟键盘报告，不代表 Typeless 已执行。

这是原样保存的临时样机：缺少正式服务生命周期、客户端读超时和完整异常退出处理，不应作为长期 root 服务发布。恢复时需单独核对官方驱动、daemon、管理员授权及 App 权限；源码备份不能恢复系统授权。

App 侧桥接和原生按键中和仅在 Bundle ID `com.hd838a.RemoteMic.TypelessTest` 启用。正常构建的正式标识不会启用该路径。制作独立测试包时，将 `dist/SayAll.app` 复制为 `dist/SayAllTypelessTest.app`，修改副本标识和显示名称，并重新 ad-hoc 签名；已保存的 228.2 App 包是本次测试的精确二进制，重新构建结果不保证字节相同。

配置与验收边界见 [测试记录](../../Testing/TypelessVirtualHIDShortcuts.md)。完整三模式、文字上屏和稳定性尚未验收；此提交是可恢复的实验检查点，不是发布版本。

## 跟随分支保存设置

[`settings.json`](settings.json) 是测试版通过「设置 → 个性化配置 → 导出配置」生成的当前选中遥控器配置快照，使用 App 原生格式。保存按键映射、自定义快捷键、双击/长按、连续快速按、语音键、增益和通用偏好。设备唯一标识已清空；统计、诊断和系统授权不在此原生导出格式中。此快照不会追踪全部设备档案。

恢复时启动测试版、选中目标遥控器，通过「导入配置」选择 `settings.json`，然后重新选择本机音频设备。导入会替换当前个性化配置，若已有配置需保留，先导出一份。Typeless 的三组快捷键仍需在 Typeless 中配置，macOS 权限仍需独立授权。

后续修改功能或测试配置时，同步执行以下步骤，将配置与对应源码保存在同一分支：

1. 在测试版中选中正在使用的遥控器，通过「导出配置」保存到仓库外的临时 JSON。
2. 在仓库根目录运行 `python3 scripts/typeless-vhid/save-settings.py /path/to/export.json`。脚本清空音频设备标识并稳定排序，便于 Git 比较；新增字段或自定义应用路径需先审查。
3. 检查 `git diff -- scripts/typeless-vhid/settings.json`，确认变化与本次设置一致，再提交并推送到个人 Fork 的实验分支。

当前语音键快照为 Fn/地球键，并关闭「语音键模拟 Fn 点按」，保留此前为微信输入法按住说话做的准备。微信输入法内部的快捷键录入与文字上屏尚待验收；此设置快照不表示对接已经完成。

Git 保存的是每次导出、提交并推送的快照，不会自动监视 App 中的每次点击。脚本不会读取其他 App 设置，也不会直接修改运行中的无线麦或自动提交。个人设备信息与完整原始 plist 继续仅在本地备份中保留。

## Global Speed 长按配置

当前快照使用下列长按动作，复用用户在 Chrome Global Speed 页面快捷键中配置的数字小键盘键。此前的 Typeless 和方向键单击动作保留。

| 遥控器长按 | 发送的键 | Global Speed 动作 |
| --- | --- | --- |
| 上键 | Numpad8 | 播放速度增加 0.5 |
| 下键 | Numpad2 | 播放速度减少 0.5 |
| 左键 | Numpad4 | 后退 5 秒 |
| 右键 | Numpad6 | 前进 10 秒 |
| 确定键 | Numpad5 | 设置为 1 倍速 |

数值来源为用户提供的扩展设置截图；没有修改扩展本身。测试包中的 `GlobalSpeedShortcutGuard` 仅对上述五个精确长按绑定限制作用域：前台必须是 Google Chrome，公开辅助功能焦点必须位于网页内容内，且焦点到网页节点之间没有可编辑控件。在其他 App、地址栏、网页输入框或焦点不可确认时跳过，不补发单击。只读取角色和可编辑能力，不读取正文、标题或 URL。规则在触发时检查，正常正式包不启用此个人实验规则；导入 JSON 到正式包不能获得此保护。

此检查不判断网页是否真的有视频，也不读取扩展状态；需要网站允许 Global Speed 页面快捷键。焦点接口不可用时会保守跳过，需要点击网页内容后重试。单击和其他自定义快捷键不受这五项范围限制。

现有手势识别在按住约 550 毫秒后触发一次长按动作；继续按住不会连续调速或跳转，松键后也不补发单击。方向四键没有双击绑定，短按松键时执行原单击，不再等待 300 毫秒的双击窗口。确定键目前双击为 Return，因此单击 Typeless 需要等待约 300 毫秒区分双击。左右键仍因存在长按绑定而不走原生透传，按住左右键用于视频控制，不能同时作为持续移动光标使用。

验证记录：2026-09-25，先前双击方案已获用户“测试成功”的实机反馈；随后按用户要求迁移为长按。新配置的导入、可见五键映射、当前设备档案持久化、原单击及音频设备设置保留均已核对。长按的视频效果和快速单击手感仍待实际使用确认；先前双击成功不能替代这次手势验收。


## Return、退格与模式切换配置

| 遥控器动作 | 配置 |
| --- | --- |
| 确定键单击 | Ctrl+Option+V，Typeless 语音输入 |
| 确定键双击 | Return |
| 返回键单击 | Delete（退格） |
| 主页键单击 | Ctrl+3，按官方默认顺序切至 Codex |
| 主页键双击 | Ctrl+1，按官方默认顺序切至 Chat |

模式快捷键来源：[官方快捷键说明](https://learn.chatgpt.com/docs/reference/commands)，其规则是按界面顺序使用 Control+1/2/3 切换 Chat、Work、Codex。需要目标应用在前台；这不是全局唤起应用的动作。若本机排列或自定义快捷键不同，应核对并调整。主页键与确定键单击均有约 300 毫秒的双击判定等待。配置已通过原生导入并在 UI 核对，用户确认主页键单击切 Codex、双击切 Chat 均正确。

音量＋/－单击分别调高/调低系统音量，双击分别为「上一首（系统媒体）」和「下一首（系统媒体）」。切歌采用上游 [PR #428](https://github.com/HD838A/remote-mic-app/pull/428) 的媒体事件修复思路，使用系统媒体事件 18/17，保留历史动作标识以兼容配置，不再向前台发送 Command+方向键。系统决定当前媒体接收者，不保证固定控制 Apple Music。增加双击后单击需等待约 300 毫秒，按住音量连发停用；实机后台切歌效果待验证。

音量＋长按为系统播放/暂停（再次长按可恢复播放），音量－长按为系统静音切换（再次长按取消静音）。约 550 毫秒触发一次，继续按住不连发，松开不补发单击。
