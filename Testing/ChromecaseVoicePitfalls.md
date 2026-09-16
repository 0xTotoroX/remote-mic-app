# Chromecase 语音链路踩坑清单（2026-09-15 验收日）

按踩到的时间序记录，供后续回顾与避免。根因详情见
`Testing/ChromecaseHardwareInterface.md` 的「根因 #1~#5」小节。

## 协议与固件

- **HTT 流进行中补发 `MIC_OPEN` 会被样机拆流**：本型号协商 `interaction=0x03`（HTT），
  远端按下即自行推流。规范 4.7.5 要求远端对打断只回 `MIC_OPEN_ERROR`，本机样机不遵守——
  直接拆流且此后零音频。HTT/PTT 下一律不补发 `MIC_OPEN`。
- **手势时长不是意图信号**：同一操作者「按一次」的自然时长在 1.1~5.8 秒间跳动
  （20 次采样），任何阈值（0.55s / 2.0s）都误伤且误伤方式是「立刻结束收音」。
  模式语义应由显式开关决定；连按防抖（latch 后 0.6s 内的再按不作为「关闭」）安全得多。
- **固件固定窗口是软件不可修的硬边界**：物理按下 → 固件上报按键（Δ，日志不可测）→
  再 ~330ms 才送首个音频帧（前两帧还是静音填充）。窗口内说的话遥控器根本没发，
  表现为「按下即说丢 1~3 字」。排查丢字先用「按住 2 秒沉默后再说话」的对照实验
  分离固件窗口与宿主问题。
- **轻点（<1s）固件完全不上报事件**：所有上报手势 ≥1.1s（vRemoter 真机日志同样），
  「轻点没反应」不是宿主 bug。
- 松键后 30~60ms 有一条幽灵 `opcode=0x04`（reason 非 0x03），Arbiter 静默忽略，无害。

## 音频链路

- **音频出口引擎会启动失败且无自愈**：AVAudioEngine 偶尔 startup 时没起来（`engine_running=false`），
  之后每次 REBIND 都无法恢复，`enqueue_failures` 恒等于 `audio_batches`（100% 丢弃）。
  对策：链路就绪即预热（`reason=chromecase_link_ready`），别等首次按键。
- **BlackHole 型环回设备没有回放缓冲**：写入端（宿主写虚拟设备输出端）比读取端（输入法
  打开输入流）先启动，读端开流之前写入的数据直接消失。对策：音频预卷缓冲——会话开头
  0.5s 先攒在宿主内存，到期一次性排入 AVAudioPlayerNode（按实时消费排队 buffer，
  不会倾倒覆盖 ring），读端开读时从人声开头读到。代价是识别出字整体晚 0.5s。
  已验证：豆包转写与宿主录音完全一致。
- **远端 HTT 流按人声门控（VAD）**：按下即开麦，但检测到人声才推帧（首帧距按下
  230~330ms）。按下期间没人声就是 0 帧，不是缺陷；「按住能用、按一次不能用」的观感
  差异来自说话时机，与按键时长无关。

## 工程与验证方法

- **`strings` 验证二进制对 Swift 短字面量完全失效**：≤15 字节的字符串字面量被
  small-string 优化编码成指令立即数（`debounced`、`hold_release` 均搜不到），险些误判
  「改动没编进包」。验证编入用 `nm` 查 mangled 符号，或搜 >15 字节的日志/中文长字面量；
  资源文案要搜 `.lproj` 资源文件而不是主二进制。
- **构建源必须核验包含目标提交**：`git merge-base --is-ancestor <commit> HEAD`；
  同一包/仓被并行会话编辑时用 `git worktree add --detach` 出已提交副本隔离构建，
  提交时只 add 自己的文件。
- **宿主自己的诊断目录不能用来断言第三方应用**：`Transcripts/` 为 0 条 ≠ 豆包没出字
  （那只是文本快照抓取）。第三方行为的证据以用户观察 + 录音资产等直接产物为准，
  用户的实测观察优先于间接证据。
- **按键页档案选择**：设备档案注册后必须 `selectRemoteProfile`（与小米链路的
  `activateRemoteProfile` 对齐），否则按键页停留在上一次选中的遥控器画布。
- **用户换音频设备环境会引入新变量**：戴着蓝牙耳机（默认输入+输出）测试时，语音输入
  激活可能把耳机切到免提（HFP）模式，输出变呲呲白噪声——与软件改动无关。
  排查「新出现的声音/现象」先问「这次和上次的设备环境有什么不同」。

## 硬件真伪

- **当前用于真机实验的 Chromecase 遥控器是假冒品**（2026-09-15 确认）。本文档与手册中
  所有「固件行为」结论（330ms 推流窗口、VAD 门控、<1s 轻点不上报、幽灵 0x04、拆流不回
  `MIC_OPEN_ERROR` 等）均基于该假冒品的实测。**之后需要换真货重新验证**，上述结论在真货上
  可能不成立，验收前先确认手里的遥控器是否为正品。

## HID 按键链路

- **manager 级独占打开会被系统拒绝**：`IOHIDManagerOpen(manager, kIOHIDOptionsTypeSeizeDevice)`
  返回 `kIOReturnNotPrivileged(0xE00002C1)`，桥永远不就绪、按键事件零到达（按键映射完全失效）。
  正确结构（对齐小米链路 `HIDRemoteMonitor`，真机验证过）：manager 用 `None` 打开只做设备发现
  与报告回调，在设备匹配回调里对**每个匹配的 HID collection** 执行
  `IOHIDDeviceOpen(device, seize)`——该遥控器暴露多个 collection，只独占第一个时其余的媒体
  用法仍会被系统消费（确认键会打开「音乐」）。
- **设备级 seize 在这台（假冒）遥控器上同样被拒**（同错误码，而小米链路同调用成功）。
  疑因：本地包反复重签名后输入监控 TCC 绑定失效，或假冒设备接口差异。已实现降级：
  seize 失败 → `IOHIDDeviceOpen(None)` 观察模式打开（`seized=false`），报告仍能驱动按键
  映射，代价是系统同时消费按键。若要恢复独占，先到「系统设置 → 隐私与安全性 → 输入监控」
  重置授权再试；换正品遥控器后重验。
- **最终结论（2026-09-15 19:40）**：观察模式（非独占打开）下 HID 报告回调**一次都不触发**
  （加了逐条日志实测，用户按多个按键 report 行为 0）——macOS 不向非独占客户端发送输入报告；
  而独占（seize）在 manager 级与设备级都被 `NotPrivileged` 拒绝。**同一进程对小米遥控器
  （HIDRemoteMonitor）的 seize 是成功的**，排除进程/TCC 权限问题 → 这台假冒遥控器的蓝牙
  HID 通道不允许 macOS 独占采集，**按键映射在该设备上不可用**，换正品遥控器是唯一解。
  语音链路（ATVV over BLE GATT 通知）不受影响。输入监控里加「无线麦.app」授权也无济于事。

### 正品遥控器实测（2026-09-16，替换假冒品后）

- **正品可被独占采集**：`CHROMECASE HID phase=connected mode=mapped seized=true`，管理级与设备级
  seize 均成功——假冒品做不到（两级都被 `NotPrivileged` 拒绝）。**seize 能力差异是真伪的判据之一**。
- **报告格式**：`reportID=0x01 len=3 head=01 XX 00`（首字节是 reportID，第二字节 usage，
  第三字节 0），与 `ChromecaseHIDUsage` 表完全对得上（0x06=right / 0x08=mute / 0x0a=home /
  0x0e=youtube）。按键映射执行链路 `CHROMECASE ACTION phase=completed result=dispatched` 正常。
- **seize 不足以阻止系统消费按键**：正品在 `seized=true` 下，静音/左右等键仍会触发系统原本行为
  （系统静音、焦点移动）。必须叠加第二道保险——与小米/苹果链路一致，在按键边沿调用
  `hidEventSuppressor.arm(nativeEvents:edge:)` 让 CGEventTap 吞掉随之到达的原生事件。
  **Chromecase 链路此前漏了这一步（HID FILTER 从未启动）**，修复见 build 186。

### 正品按键的原生事件实测表（2026-09-16，`HID FILTER arm/miss/suppressed` 日志为证）

| 按键 | 通用表（小米 RC003） | 正品 Chromecase 实测 | 结果 |
| --- | --- | --- | --- |
| 音量 +/− | `systemKey(0/1)` | `systemKey(0/1)` | 抑制命中（`suppressed`），无系统副作用 |
| **静音** | `systemKey(3)` | **`systemKey(7)`** | 沿用通用表必然 miss → 系统音量 HUD 照常出现 |
| 方向（上/下/左/右） | `keyCode 126/125/123/124` | 系统侧**不产生事件** | tap 零记录，无副作用，无需抑制 |
| 确认（OK） | `keyCode 36` | 系统侧**不产生事件** | 同上 |

- 修复：静音按设备单独映射 `chromecaseNativeEvents(for:)`（build 190）。
- 教训：**通用 `RemoteButton.nativeEvent` 表是小米 RC003 的实测值，换遥控器必须重新实测**；
  诊断「抑制无效」时，命中与未命中都要留日志（`suppressed`/`miss`），只看 miss 会漏掉
  「键码完全对不上」的情况。**注意区分「自定义动作效果」与「系统原本功能」**——本次
  用户报告的「左/右/OK 也执行了原本功能」，实为自定义动作 arrowLeft/returnKey 在特定 App 里的
  效果，系统侧并无事件。

### 按键「自定义动作 + 系统原本功能同时执行」的根因：Apple 配件协议（AACP，2026-09-16）

症状：正品遥控器上左右键切歌、OK 播放/暂停、静音出音量 HUD，**同时**自定义映射正常执行。
对照实验：**键盘方向键不切歌**（排除「注入方向键在音乐 App 里的效果」这一解释）。

ioreg 取证（VID 0x18D1/PID 0x9450）：

```
"Transport" = "BT-AACP"                  ← Apple 配件协议
"HIDVirtualDevice" = Yes                 ← Apple 给配件暴露的虚拟 HID
"PrimaryUsagePage" = 0xFF0C（Apple 私有）
"InputReportElements" = ReportID 1(24bit，Array) / 4(8bit) / 8(168bit)
"DeviceOpenedByEventSystem" = Yes
```

- 报告是 **Array** 类型（字节=usage 索引）：索引 5/6/7 在系统眼里是 **Menu Up/Down/Left**，
  索引 2 是 **Play/Pause**，8 是 Mute，12/13 是 Volume ±。
- 系统配件服务（AACP）**直接**消费这些 usage → 媒体/导航行为，
  **不经 CGEvent**（cghid 层只读探针实测零记录）、**不是标准 HID 客户端**（`seized=true` 也拦不住）、
  **不读 HID 设备属性**（`hidutil --set HIDDefaultBehavior=0` / AppleVendorSupported 均无效）。
- 我们的读取只是 Apple 为配件暴露的虚拟 HID 旁路——**能读，不能阻止系统那一侧**。

可用/不可用手段一览：

| 手段 | 结果 |
| --- | --- |
| `IOHIDDeviceOpen(seize)`（设备级独占） | ❌ 只挡标准 HID 客户端 |
| CGEventTap 吞事件（session / cghid 两层） | ❌ 事件不经过 CGEvent |
| `hidutil` 改设备属性 | ❌ 行为由 AACP 服务控制 |
| 静音/音量键的抑制 | ✅ 例外：这两个 usage 恰好产生 NX_SYSDEFINED（走 CGEvent） |
| DriverKit 系统扩展（Karabiner 方案） | ⚠️ 理论可行，需安装驱动 + 用户批准，工程量大 |
| 系统蓝牙中移除设备 | ⚠️ 会同时失去虚拟 HID 报告源（按键数据也没了） |

**结论**：这是 macOS 对 Apple 配件协议遥控器的系统级行为，用户态 App 无法拦截。
需要产品决策：接受现状，或投入 DriverKit 扩展方案。

### 补充：参考实现要点与「删除系统配对」实验结论（2026-09-16）

参考文档：私有包 `packages/audio-input-kit/chromecase/Referance/google-tv-remote.md`
（Vokie `google-tv-remote-helper` 的实机记录），可直接采纳的结论：

- **HID 采集不可靠**：该设备的 HID 接口被 macOS HID 事件服务占用，用户态
  `IOHIDDeviceOpen`（含 seize）拿不到输入；文档明确**禁止**再用 IOHID 回调采集其按键。
  按键的权威路径是**蓝牙 GATT 通知**（新款 A0：中间键 `0x0029` 值 `07 00 00 00 00 00 00 00`、
  返回键 `0b 00 …`、语音键 `0x003f` 值 `04 03 02 xx`；旧款 hid_mouse 表不通用）。
- **「轻点无反应」的真因是深度休眠**：遥控器闲置数分钟后短按无任何上报，
  需**长按任意键约 3 秒**唤醒（唤醒期第一个按键被设备自己消耗）。
  另有「已连接但不上报」假死态：取电池 5 秒或系统蓝牙删除重配可恢复。
  → 本文档早前「固件不上报 <1s 按键」的说法应以此更正。
- **语音音频走 GATT（0x003c/0x0054）**：IMA ADPCM 16 kHz / 4 bit / 128 字节帧、无帧头、
  编码器每次语音会话重置（我们的 ATVV 实现与之等价，可作交叉验证）。
- **移除系统配对不可行（2026-09-16 实测）**：本仓库 `ChromecaseAdapter` 早就注释过
  「已被系统持有的遥控器不再广播，`scanForPeripherals` 永远发现不了它」，只能靠
  「系统已连接的设备」取回。删除配对后设备既不广播也不在系统列表 → App 完全够不着，
  **语音链路一并失效**，实测确认。排查此类问题前不要动系统配对；恢复方法是系统蓝牙
  重新配对（同时按住 Home + Back 3~5 秒进配对模式）。
