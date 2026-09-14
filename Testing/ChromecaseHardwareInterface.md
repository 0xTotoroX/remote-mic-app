# Chromecase 遥控器（ATVV）实机测试手册

## 适用范围

- 日期：2026-09-15。
- 目标硬件：Chromecase 语音遥控器（ATVV over BLE，广播名含 `Chromecast Remote`）。
- 当前状态：宿主接线已完成并通过自动化验证（协议、解码、仲裁、会话策略、语音键隔离）。本手册覆盖的**真机连接、语音链路与安装包验收尚未执行**，未通过前不得声明该硬件正式受支持。
- 第一版范围：**只做语音**。不含普通按键边沿、触摸面、电池状态；这些能力在代码里明确缺席，不得伪造。
- 跨平台基础约束见 [`Testing/HardwareCompatibilityContract.md`](HardwareCompatibilityContract.md)；语音完整性门槛见 [`Testing/HardwareVoiceAudioContract.md`](HardwareVoiceAudioContract.md)。本手册不重新定义通用行为，只增加该硬件的实机步骤。
- **与 Siri Remote 完全隔离**：两者互不 `import`、不共享全局状态、不共用语音键 owner。用户可能只有其中一个、两个都有，或都没有。

## 本地测试包

| 项目 | 值 |
| --- | --- |
| App | `/Users/andy/MySrc/remote-mic-app-chromecase/dist/SayAll.app` |
| 构建时间 | 2026-09-15 01:01（CST） |
| 配置 | Release，Apple Silicon `arm64`，最低 macOS 14.0 |
| 版本 | 1.9.21（174） |
| Bundle ID | `com.hd838a.RemoteMic` |
| 宿主源码基线 | 分支 `codex/chromecase-voice-hardware`（worktree `/Users/andy/MySrc/remote-mic-app-chromecase`，含提交 `3dd3779`、`1ea5061` 与本次自检清单修复；基线 `origin/main` `41073ea`） |
| 私有包基线 | `SayAllChromecase` @ `c3699e8`（`sayall-private-platform/packages/audio-input-kit/chromecase`） |
| 主程序 SHA-256 | `b9f31c0e2f65c708c6b2c0c1bde6e672e0cbbedc48a91afdc9cd27aeb6f2d130` |
| 包体积 | 约 `15 MB` |
| 签名 | Developer ID Application `L3QHLDRPAY`；`codesign --verify --deep --strict` 已通过 |
| Info.plist 标记 | `SayAllChromecaseIncluded=true`，其余可选组件均为 `false` |

> 上一版（SHA-256 `bc0dac56…`，2026-09-15 00:25）缺少「取回系统已连接设备」的发现路径：
> 遥控器一旦在系统蓝牙里配对就连不上，面板永远停在「正在搜索遥控器」。该版已被本版替换，
> 构建脚本已把旧包移入废纸篓。

### 已确认（2026-09-15 01:01，本机真机）

遥控器已配对至系统蓝牙的前提下启动本包，链路自动打通，**不需要先断开系统蓝牙**：

```
FEATURE start model=chromecast-voice-remote
BLE SYSTEM CONNECTED ADOPTED model=chromecast-voice-remote
BLE CONNECTING source=connected_peripheral model=chromecast-voice-remote
BLE CONNECTED model=chromecast-voice-remote
ATVV CAPABILITIES version=0x0100 codec=2 frame=120
ATVV READY version=0x0100 codec=2 frame=120 fallback=false
CHROMECASE CONNECTION state=available
```

这证明：发现路径、BLE 连接、服务发现与 ATVV 能力协商（v1.0 / 16 kHz IMA ADPCM / 120 字节帧）
在真实硬件上全部可用。**它不等于语音链路已验收**——用例 2 起的收音、首字、尾字与异常路径仍待执行。

此包只用于本机候选功能测试，不可作为正式发布包分发。

**它不需要任何 helper、LaunchDaemon、安装器组件或 root 授权**——ATVV 是标准 BLE GATT，标准用户即可。这与 Siri Remote（依赖私有 HCI 与 PacketLogger helper）是本质区别，因此本包用 ad-hoc 或 Developer ID 普通签名即可，不要求特权组件。

### 重新构建

```sh
cd /Users/andy/MySrc/remote-mic-app-chromecase
SAYALL_CHROMECASE_PACKAGE_PATH=/Users/andy/MySrc/sayall-private-platform/packages/audio-input-kit/chromecase \
CODE_SIGN_IDENTITY="Developer ID Application: lei qian (L3QHLDRPAY)" \
  ./scripts/build-app.sh
```

不带 `SAYALL_CHROMECASE_PACKAGE_PATH` 时，构建产物与未接入该硬件前完全一致（`SayAllChromecaseIncluded=false`，界面不显示该面板）。这是必须回归的约束。

## 测试前准备

1. 退出其他无线麦SayAll.app 实例，只保留待测包。
2. 确认已安装 `MiRemoteV 2ch` 音频设备（侧边栏「连接」→「连接与语音」页的「音频输入与兼容」面板应显示已就绪）。本次不安装任何 helper。
3. 在侧边栏「设置」页的「权限与隐私」区授予蓝牙、输入监控和辅助功能权限，然后完全退出并重新打开 App。
4. 打开 `~/Library/Logs/RemoteMic/runtime.log`，保留现有文件，不清空、不覆盖。
   - 建议直接双击 `Testing/启动Chromecase真机测试.command`，它会实时过滤出本手册用到的日志行，并在桌面留一份会话记录。
5. 进入侧边栏**「连接」**（链接图标，页面标题「连接与语音」），在右列第三块找到「Chromecase 遥控器」面板——总开关在**这一页**，不在「设置」页（「设置」页只有权限、通用、诊断与日志）。
6. 确认遥控器可被 App 发现。**这里有两种情况，都必须能连上**：

   | 情况 | 遥控器状态 | App 应走的发现路径 |
   | --- | --- | --- |
   | A | 未与 Mac 建立连接，正在广播 | `BLE SCANNING` → `BLE CONNECTING source=scan` |
   | B | **已在「系统设置 → 蓝牙」里配对/连接**（或已被系统当作 HID 设备占用） | `BLE SYSTEM CONNECTED ADOPTED` → `BLE CONNECTING source=connected_peripheral` |

   情况 B 是被动出现的：BLE 设备一旦与主机建立连接就**停止广播**，只靠扫描的链路会永远停在
   「正在搜索遥控器」。App 必须能取回系统已连接的设备并主动连上它。
7. 状态应从「正在搜索遥控器」变为「已连接」。**没有 `state=available` 就不要往下测。**
8. 若长时间停在「正在搜索遥控器」，先看日志：
   - 完全没有 `BLE DISCOVERED UNMATCHED` 也没有 `BLE SYSTEM CONNECTED ADOPTED`：遥控器既没广播、也没被系统连接，多半是没唤醒或不在配对模式。
   - 有 `BLE DISCOVERED UNMATCHED name=...`：设备在广播但名字对不上，记下该名字（匹配规则冻结自 vRemoter，不得擅自放宽）。

## 隔离组合

| 组合 | 期望行为 |
| --- | --- |
| 只有 Chromecase | 该面板可见可用；Siri Remote 相关界面与代码路径完全不存在（本包 `SayAllSiriRemoteIncluded=false`）。 |
| 两个都有 | 两套链路各自独立工作；同时收音时语音键按引用计数保持按下，互不取消。 |
| 都没有 | `SayAllChromecaseIncluded=false`，该面板不出现，启动、运行、打包与未接入前一致。 |

## 实机测试矩阵

### 用例 1：连接、重连与设备识别

1. 启动 App，等待状态从「正在搜索遥控器」变为「已连接」。
2. 在面板点「重新连接」。
3. 关闭再打开遥控器，观察是否自动恢复。
4. **系统已连接场景**：在「系统设置 → 蓝牙」里把遥控器连上（或先移除再重新配对），回到 App 点「重新连接」。

预期：状态依次经过 `discovering → connecting → available`；重连期间活动收音必须先被结束。日志出现 `CHROMECASE LINK state=` 与 `CHROMECASE CONNECTION state=available`。

第 4 步的发现路径必须是 `connected_peripheral`，不是 `scan`：遥控器被系统连上后**不再广播**，扫描不可能发现它。若这里只有 `BLE SCANNING` 而没有 `BLE SYSTEM CONNECTED ADOPTED`，说明该发现路径失效——这正是本用例要盯的回归点。

失败判定：状态长期停在「正在搜索」；或断连后仍显示已连接；或第 4 步只能靠先断开系统蓝牙才能连上。

### 用例 2：toggle 模式——按一下开始、再按一下结束（默认模式）

确认面板（侧边栏「连接」→「连接与语音」页 →「Chromecase 遥控器」）语音键模式为「点按开关」。

1. 按一下遥控器语音键，说一句话后停顿几秒（**先不要**再按）。
2. 观察录音/识别是否持续进行（这正是与 Siri Remote 的核心差异）。
3. 再按一下语音键。

预期：
- 第 1 次按下即开始收音，且**不结束**；用户可见"正在收音"状态保持。
- 第 2 次按下才结束。
- 日志出现 `CHROMECASE VOICE phase=started` → `CHROMECASE VOICE phase=sustain result=no_visible_change`（可能有多次）→ `CHROMECASE VOICE playback_stop phase=waiting_for_drain` → `CHROMECASE AUDIO playback_stop phase=completed result=drained`。

失败判定：第 1 次点按后立刻结束收音；或持续收音期间输入法识别被反复关闭（说明换流被当成了新的用户动作）。

### 用例 3：hold 模式

把模式切到「按住说话」。切换后**立即生效**，无需重启（面板改动会即时同步到运行时）。

1. 按住语音键说话，中途松开。

预期：按住期间收音，松开即结束；`completion=normal reason=hold_release`。

失败判定：松开后仍在收音；或按住期间没有开始。

### 用例 4：首字完整性（最关键）

在 toggle 模式下，按一下语音键后**立刻**说第一个字（例如「测试」，不要先停顿）。

1. 重复 10 次，每次换一个首字（如「你好」「今天」「帮我」）。
2. 检查识别结果与录音资产的首字是否完整。

预期：10 次首字全部完整。设计上宿主是在包写 `MIC_OPEN` 之前备好音频出口的，因此最早几帧不应丢失。

失败判定：出现首字缺失或吞字。这正是需要重点观察的换流缺口风险；历史上该协议的实现在此处出现过偶发失败。

### 用例 5：尾字完整性（正常停止不 flush）

1. 按住语音键（hold 模式）说一句结尾有力的短句，例如「今天天气很好」，说完立刻松开。
2. 检查最后两个字是否完整。

预期：尾字完整。正常结束路径只做自然排空（`maximumDelay: nil`），不得 flush。

失败判定：末字被截断；或日志出现 `AUDIO PLAYBACK interrupted`。

### 用例 6：断连、蓝牙关闭与系统休眠

分别在**收音进行中**的三种情况下操作：

1. 关掉遥控器电源。
2. 在系统里关闭蓝牙。
3. 让 Mac 进入休眠并唤醒。

预期：三种情况都必须立即结束收音并释放语音键，日志为 `completion=forced`；**不得**自动改用电脑内置麦克风，也不得继续向 `MiRemoteV 2ch` 送无效音频。唤醒后应能重新连接。

失败判定：收音卡住不结束；语音键保持按下；或回退到电脑麦克风。

### 用例 7：8 kHz 样机必须被拒绝

若有 RemoteG10（只有 8 kHz 语音）样机：

1. 让它进入广播范围。

预期：在**扫描阶段**就被判为不支持并拒绝连接，面板显示「该样机不受支持」及原因；日志为 `state=unavailable`。不得静默升采样，也不得把它当成受支持型号。

失败判定：连接成功但没有声音；或出现升采样后的可用音频。

### 用例 8：快速连续点按

在 toggle 模式下快速连按两次以上。

预期：不产生重复触发；换流期间不重复合成用户可见动作；最终状态与物理按键状态一致（不能出现"以为在收音其实已停"）。

失败判定：输入法被反复开关；或最终状态与实际不符。

### 用例 9：与 Siri Remote 并存（仅当包同时包含两者）

本测试包只包含 Chromecase。要验证并存，需同时带 `SAYALL_SIRI_REMOTE_PACKAGE_PATH` 构建（另需 `libopus` 与 Developer ID 签名）。

1. 两个遥控器都连接。
2. 用 Chromecase 开始持续收音，期间按下 Siri 键。
3. 先松开其中一个，再松开另一个。

预期：语音键按引用计数保持按下，只有最后一个 owner 释放时才真正抬起；两路音频各自路由到 `MiRemoteV 2ch`；任何一方结束都不会取消另一方。

失败判定：一方结束导致另一方收音中断；或语音键提前抬起。

### 用例 10：打包可选性回归

**注意：这一步会在同一个 `dist/` 里重建 App，覆盖上面的真机测试包。请在跑完用例 1–9 之后再执行；**
或者先 `cp -R dist/SayAll.app /tmp/SayAll-chromecase.app` 留一份。

```sh
cd /Users/andy/MySrc/remote-mic-app-chromecase
env -u SAYALL_CHROMECASE_PACKAGE_PATH -u SAYALL_ENABLE_SIRI_REMOTE \
  SAYALL_CHROMECASE_PACKAGE_PATH= ./scripts/build-app.sh
plutil -extract SayAllChromecaseIncluded raw -o - "dist/SayAll.app/Contents/Info.plist"
```

预期：未提供私有包时构建仍然成功，输出 `false`，App 正常启动，设置页连接页不出现 Chromecase 面板。

若要同时确认"没有私有仓库权限"的场景，应在一个只有公开仓库访问权限的账号或干净机器上完成
resolve、测试与 Release 构建；本机已持有私有包路径，不能替代该验证。

失败判定：构建报错，或缺少私有包时启动异常、设置页出现空面板。

## 日志关键行

| 阶段 | 关键字 |
| --- | --- |
| 链路 | `CHROMECASE LINK state=`、`CHROMECASE CONNECTION state=` |
| 发现（扫描） | `BLE SCANNING`、`BLE CONNECTING source=scan` |
| 发现（系统已连接） | `BLE SYSTEM CONNECTED ADOPTED model=`、`BLE CONNECTING source=connected_peripheral` |
| 发现（扫描未匹配，诊断用） | `BLE DISCOVERED UNMATCHED name=` |
| 开始收音 | `CHROMECASE VOICE phase=started` |
| 持续收音（不得有用户可见动作） | `CHROMECASE VOICE phase=sustain result=no_visible_change` |
| 音频路由 | `CHROMECASE AUDIO routed source=chromecase_microphone route=virtual_audio device=MiRemoteV_2ch` |
| 结束与排空 | `CHROMECASE VOICE playback_stop phase=waiting_for_drain`、`CHROMECASE AUDIO playback_stop phase=completed result=drained` |
| 结束原因 | `completion=normal`（hold 松键 / 第二次点按）、`completion=forced`（断连、取消、宿主关闭） |
| 包内协议 | `ATVV MIC_OPEN written`、`ATVV MIC_CLOSE written`、`ATVV STREAM START/STOP`、`VOICE INTENT` |

合同要求异常原因必须出现在日志里，因此断连原因以稳定 token 输出（如 `disconnected.adapterStopped`）。

## 记录表

| 用例 | 结果 | 证据（日志时间戳 / 录音 / 备注） |
| --- | --- | --- |
| 1 连接与重连 | 部分通过 | 2026-09-15 01:01 本机真机：配对状态下启动即走到 `state=available`（见上文「已确认」）。步 2「重新连接」、步 3 遥控器关开恢复、步 4 系统蓝牙断开/重配对后重连**未执行**。 |
| 2 toggle 开始/结束 | 未执行 | |
| 3 hold | 未执行 | |
| 4 首字完整性（10 次） | 未执行 | |
| 5 尾字完整性 | 未执行 | |
| 6 断连/蓝牙关闭/休眠 | 未执行 | |
| 7 8 kHz 样机拒绝 | 未执行 | 无样机；准入判定已由包内单元测试覆盖（`.rejectUnsupported`），但**不替代真机**。 |
| 8 快速连续点按 | 未执行 | |
| 9 与 Siri Remote 并存 | 未执行 | 本包不含 Siri Remote（`SayAllSiriRemoteIncluded=false`）。 |
| 10 打包可选性回归 | 部分通过 | 不带私有包：`swift build` 通过、项目自检 44/44 通过。**未执行**的是完整 `build-app.sh` 无包出包与 `plutil` 读取 `SayAllChromecaseIncluded=false`，以及无私有仓库权限账号的验证。 |

**结论必须分开记录**：自动化测试结论、真机结论、安装包验收结论不能互相替代。本手册只覆盖真机部分。
本轮自动化结论：包内 69 项 XCTest 全绿；宿主项目自检 44 项、SwiftPM 567 项全绿（带包与不带包两种配置）。
