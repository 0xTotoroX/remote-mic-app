# 自定义快捷键未向 Typeless 发送修饰键变化事件

## 复现

在 macOS 上，Typeless 2.8.0 的语音输入、翻译和随便问分别录入左 Control + 左 Option + V/T/Q。无线麦 1.9.21（build 174）将实体遥控器确定键、菜单键和 TV 键单击分别映射为相同组合。实体 Mac 键盘按 Control + Option + V 能唤起 Typeless；遥控器触发三个映射均不能。遥控器下键映射的 Command + L 能聚焦 Chrome 地址栏，说明设备和一般按键映射路径可用。

## 日志与根因假设

现场 `~/Library/Logs/RemoteMic/runtime.log` 在 2026-09-24 17:54:06–17:54:07 UTC 记录了 V/T/Q 的 `SHORTCUT ACTION submitted`，键码依次为 9/17/12，`modifier_flags=786432`（Control + Option），但该日志只表示提交，不证明 Typeless 接收。源码 `KeyboardInjector.send` 原先只给主键 `keyDown/keyUp` 加修饰 flags，没有发送修饰键自己的事件。单独修饰键同样以普通 `keyDown/keyUp` 发送。Typeless 捕获界面明确区分 Left Ctrl、Left Option；缺少带左侧键码的修饰键变化事件是当前最强的根因假设，仍须用修复版真机复现验证。

## 候选修复

自定义组合键按 Control、Option、Shift、Command、Fn 顺序发左侧 `flagsChanged` 按下事件，再发主键，随后逆序释放修饰键。单独修饰键也使用 `flagsChanged`，保留原有左右键码。中途创建修饰键事件失败时释放已按下的键并返回失败。专用语音键的 Fn 点按路径保持原样。

## 验证与边界

- `swiftc -parse` 已通过；独立 CoreGraphics 探针确认构造出的左 Control 事件类型为 `flagsChanged`，键码 59，flags 为 Control。
- 安装并启用 Xcode 27 后，`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-keychain --filter RemoteButtonsTests`：120 个测试通过。其中新增用例覆盖修饰键按下、主键、逆序释放及中途失败清理；首次运行发现失败清理残留 Option flags，修正后重跑通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh` 成功，产出本地 ad-hoc 签名的 `dist/SayAll.app`，`codesign --verify --deep --strict` 通过。此构建不具备已安装正式版的 Developer ID 签名，macOS 将输入监控和辅助功能视为待授权，不能作为正式安装包分发。
- 为避免与已安装正式版共用 Bundle ID 导致 TCC 授权冲突，仅将构建产物重签为独立测试标识 `com.hd838a.RemoteMic.TypelessTest`，不修改源码或正式版。系统设置现将 `SayAllTypelessTest.app` 与正式版分别列出；重启后测试版报告蓝牙、输入监控和辅助功能均已授权，HID 已连接。测试版界面已设置确定键 `⌃⌥V`、菜单键 `⌃⌥T`、TV 键 `⌃⌥Q`，对应双击和长按均未设置。
- 2026-09-25 实体遥控器复验失败：确定键、菜单键和 TV 键均没有唤起 Typeless。测试版日志确认三键分别进入 `customShortcut`，并提交了 V/T/Q 事件；因此 HID 识别和映射路由可用，`CGEvent.post` 返回不代表 Typeless 匹配成功。
- 复查 Xcode SDK `IOKit/hidsystem/IOLLEvent.h`：除通用 Control/Option flags 外，物理左侧修饰键还带 `NX_DEVICELCTLKEYMASK` (`0x01`) 和 `NX_DEVICELALTKEYMASK` (`0x20`)。上一候选版只发左侧键码，flags 没有这些侧别位。第二候选版为组合键及独立修饰键补充对应侧别位；仍需实体遥控器复验。若仍失败，应以 Typeless 捕获结果区分侧别匹配与合成事件识别，不能仅凭日志继续宣称修复。
- 第二候选版实体确定键仍未唤起 Typeless；同一时刻的日志再次确认 `button=ok trigger=singleClick action=customShortcut`，`key_code=9`，提交成功。120 项相关测试通过，但不能覆盖 Typeless 实际接收。`CGEventPost` 本身是主要剩余嫌疑，尚不能排除 Typeless 对事件时序或事件来源的其他要求。
- Typeless 录入框测试未形成有效结论：通过 UI 点击“添加另一个”时，Typeless 把该鼠标点击自动录成 `Left`；已立即删除，核对 `app-settings.json` 恢复为原有 PageDown、LeftCtrl+LeftOption+V/T/Q，没有留下测试快捷键。临时版已退出，`/Applications/SayAll.app` 正式版恢复运行，原用户配置未改。
- 用户已授权安装并测试 pqrs 官方 VirtualHID 驱动。`Karabiner-DriverKit-VirtualHIDDevice-8.5.0.pkg` 从官方 Release 下载，SHA-256 与发布元数据一致，Developer ID Installer 签名和 Apple 公证通过；包收据为 `8.5.0`，内部驱动标识版本仍为 `1.8.0`。当前 `systemextensionsctl list` 显示 `[activated waiting for user]`，系统设置中的驱动程序扩展开关仍为 off，不能把驱动视为可用。官方 daemon 尚未启动，真实虚拟键盘报告与 Typeless 响应尚未测试。临时探针和仅接受 V/T/Q 请求的本地桥接样机已在 `/tmp` 编译，未安装为常驻服务，也未接入正式 App。
- 2026-09-25 后续：用户在系统设置启用扩展，`systemextensionsctl list` 确认为 `[activated enabled]`；用户在终端完成管理员验证，官方 daemon 与仅允许当前用户发送 V/T/Q 的临时 root 桥运行，socket 权限为 `0600`。通过该 socket 发左 Control + 左 Option + V/T/Q，Typeless 可见界面分别进入语音输入、显示“翻译为 英语（美国）”、显示“询问任何问题”，再次发送相同键可结束。由此确认虚拟 HID 路径可触发三种模式，但尚未证明实体遥控器经测试版 App 的整条路径可用。
- 本地测试版加入仅对 Control + Option + V/T/Q 走虚拟 HID 的可选路由；桥不可用时回退现有 CGEvent 路径。`RemoteButtonsTests` 121 项通过，App 构建和独立测试标识重签成功，测试版已启动，输入监控、辅助功能与 HID 连接均正常。等待用户按实体确定键、菜单键、TV 键复验；正式 `/Applications/SayAll.app` 未替换。
- 用户真机反馈三键偶尔触发 Typeless，但“不稳定”。测试版 `pid=34580` 在 2026-09-25 05:19:08–05:20:00 UTC 的日志里，三个按键均至少两次记录 `SHORTCUT ACTION submitted route=virtual_hid`；桥日志也有对应 V/T/Q 报告。因此实体遥控器到虚拟 HID 桥已连通，不能再写作尚未真机复验。Typeless 最终响应只由用户目测确认“有时成功”，暂无逐次对应记录。
- 同一时段出现大量 `HID PRESS rejected ... reason=awaiting_stable_release stable_release_ms=600`。多次 `ok` 的释放后几毫秒又收到按下，符合实体设备按住时连续报键的情形；不能简单打开“允许连续快速按”，否则 Typeless 的开始/结束可能被同一次长按来回切换。需要按一次、间隔至少 2 秒、再按一次的受控真机测试，分辨 600 毫秒防连发规则与 Typeless 对已提交快捷键的偶发漏收。
- 受控测试：用户在 05:25:02 UTC 按确定键，Typeless 启动；相隔 3.3 秒后在 05:25:05 再按，用户主观观察“没结束”。日志两次均有 `HID GESTURE`、`SHORTCUT ACTION submitted route=virtual_hid key_code=9` 和 `HID BUTTON`；桥日志亦各有 V 报告。第二次没有被 600 毫秒规则挡掉。约 05:25:08 可见 Typeless 浮动栏显示 `Thinking`，随后浮动栏消失；这与第二次已停止录音并进入处理阶段相符，但尚不能确定是第二次快捷键导致，亦未确认文字上屏。第二次随后连续报键在 600 毫秒内被正常抑制。
- 查询 Logitech 官方支持文档：其实体 Fn 主要在键盘固件中切换功能层，不会发送与 Apple Fn/Globe 兼容的键码；Karabiner 官方也将非 Apple 键盘 Fn 描述为硬件内部处理。因此不能把用户图中的 Logi Fn 直接视为 Typeless 可录入的 Apple Fn。Typeless 2.8.0 官方帮助将 Mac Fn、Fn+左 Shift、Fn+空格分别列为三种模式的默认快捷键，并说明翻译和随便问通过主快捷键 Fn 结束。虚拟 HID 的 Apple Fn 报告仍可单独测试，不能把这项可能性当作已验证方案。
- 05:35 UTC 后复查 Typeless 可见设置：语音输入的第一快捷键已变成 PageDown，而左 Control + 左 Option + V 仍是第二个；先前截图中的 Fn 已不在列表中。用户实体键盘左 Control + 左 Option + V 仍可唤起 Typeless，说明 Typeless 本身及该组合键的实体键盘监听正常。按用户此前明确要求“不使用 PageUp/PageDown”，通过可见 UI 删除语音输入的 PageDown，当前只剩左 Control + 左 Option + V；后续须重做实体遥控器两次按键与文字上屏验收。


## 非阻塞发送与原始事件配对候选

现场日志中，一次原始确定键按下会进入同步桥调用约 200 ms，而 session event tap 与 HID 都在主线程，原始事件预约只有 180 ms；HID 松开还会删除尚未处理的按下预约。现场出现 Return 按下 `miss`、松开 `suppressed`。这是可独立复现的事件拦截缺陷，其与 Typeless 漏响应的因果关系仍待真机对照。

先增加两个可重复用例：在 session tap 处理前先投递一组或两组 HID 按下/松开。原实现的三个按下断言全部失败。最小修复保留按下预约直至消费或原有期限，未扩大拦截窗口；虚拟 HID 的同步 socket 等待移到串行后台队列，保留请求顺序，并明确区分排队、发送、回执和第三方未知响应。失败后不再静默补发 CGEvent。

自动化验证：`swift test --disable-keychain --filter 'RemoteButtonsTests|VirtualHIDShortcutBridgeTests|AppleSiriRemoteAdapterTests|HardwareSimulationIntegrationTests'` 通过 124 项 Swift Testing 与 3 项 XCTest。后两组硬件测试受编译条件限制未启用，因此不算已验证。新增覆盖慢桥不阻塞主线程、请求顺序、超时后恢复、过期排队丢弃，以及不补发不确定请求。真实三键与文字上屏待验收。

- 非阻塞候选构建 228.1 已启动，输入监控/辅助功能和 HID 连接均正常。直接通过受限桥发送 T/Q，截图分别确认翻译/随便问的录音波形，发送主快捷键 V 后浮动栏退出。AX 树在录音时也包含隐藏的 `Thinking` 文本，因此该词本身不能用于判断已停止。实体确定键的开始、结束、文字输出仍等待用户验收。

- 228.1 真机复验失败：用户反馈确定键完全没有启动 Typeless。对应六次有效操作（06:13 UTC）均记录 bridge acknowledged，确定键原生 Return 的按下/松开均有 suppressed；不能再把主线程阻塞或 session 层 Return 漏出视为全部根因。当前桥源码明确设置 left_control/left_option，但尚未比较系统实际接收的事件及 Typeless 对物理遥控器原生 HID 的响应。普通组合键模型只保存通用修饰标志，缺少用户可配置的左右侧别；这一能力缺口与本次固定左侧桥仍失败须分开处理。候选版仍未通过最终验收。


## 系统事件对照与原生按键干扰实验

2026-09-25 06:32 UTC 的有界 CGHID 只读探针确认：实体键盘和当前虚拟 HID 的 V 主键均收到 flags `0xc0121`，Control/Option 键码分别为 59/58，包含相同左侧标志。当前固定左侧桥的失败不能归因为缺少左右侧别位。遥控器触发时存在另一差异：原始 Return（键码 36）先按下，随后注入 V 的整个组合期间 `CGEventSource.keyState(.hidSystemState, key:36)` 为 true；实体键盘对照期间为 false。session 层吞掉 Return 不会消除更早层级的按下状态。尚未证明 Typeless 正是因该状态拒绝匹配。

临时最小实验通过公开 IOHIDServiceClient UserKeyMapping API，仅对小米 VendorID 0x2717 / ProductID 0x32B8，将原生确定键、菜单键、TV 键的 keyboard usage 0x28/0x65/0x35 映射到 usage 0。保留其他映射并保存被覆盖条目，180 秒后恢复这三个来源的原值。API 返回成功且读回匹配；第一次窗口到期已确认恢复成功。新一轮等待实体确定键操作，尚无可用的中和后事件与 Typeless 验收结果，不将该实验写成修复成功。


- 06:44 UTC 中和实验得到有效真机对照：原始报告仍触发 App，V/T/Q 的系统事件均为左 Control/Option，注入期间 Return 状态全为 false。用户明确确认确定键“能启动，也能结束”。这是原生按键中和后行为改善的证据，支持该路径作为候选修复；尚不能据此宣称三种模式、音频和稳定性全部验收。脚本到期后已恢复原映射。
- 后续候选将中和放入 `RemoteShortcutNativeMapper`，只在独立 Typeless 测试标识中、单台匹配小米设备、自定义按键和两项权限启用时，为当前三键中桥支持的单击组合启用。修改动作、禁用自定义按键和正常退出时恢复所拥有的来源映射，保留其他来源；写入后读回验证，失败尝试回滚并保留恢复信息。虚拟 HID 路由同样限定测试包，正式包不隐式依赖临时 root 桥。

- 构建 228.2：140 项 Swift Testing 加 3 项 XCTest 通过，release 构建与独立测试包签名校验通过。实时验证关闭自定义按键后，仅保留原语音中和；重新开启后三个目标 usage 0 恢复；正常退出后映射为空，与启动前原值相符。重启后设备连接、两项权限和三键中和均恢复。安装位置仍为工作目录的独立测试包，正式 App 未替换。新构建上的三键模式及文字输出仍待用户验收。
