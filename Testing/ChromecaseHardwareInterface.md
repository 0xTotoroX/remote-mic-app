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
| 构建时间 | 2026-09-15 01:46（CST） |
| 配置 | Release，Apple Silicon `arm64`，最低 macOS 14.0 |
| 版本 | 1.9.21（174） |
| Bundle ID | `com.hd838a.RemoteMic` |
| 宿主源码基线 | 分支 `codex/chromecase-voice-hardware`（worktree `/Users/andy/MySrc/remote-mic-app-chromecase`，含 `3dd3779`、`1ea5061`、`2f0afe1`、`bcddb8a`、`c30fb78`；基线 `origin/main` `41073ea`） |
| 私有包基线 | `SayAllChromecase` @ `dbfdce9`（`sayall-private-platform/packages/audio-input-kit/chromecase`） |
| 主程序 SHA-256 | `e38b8b145e8d75ee16fbf7b3ce1ab97c2201c8e52f8147c4ba9f16f21f941acf` |
| 包体积 | 约 `15 MB` |
| 签名 | Developer ID Application `L3QHLDRPAY`；`codesign --verify --deep --strict` 已通过 |
| Info.plist 标记 | `SayAllChromecaseIncluded=true`，其余可选组件均为 `false` |

> **同一台机器上还有一份 `/Applications/SayAll.app`（1.9.21 build 181，无 Chromecase）。**
> 它的构建号比本测试包更大，但没有 `SayAllChromecaseIncluded` 标记，从启动台或 Spotlight
> 打开它**不会出现遥控器面板**。测试必须显式打开本表的 `dist/SayAll.app`。
>
> 版本历史（每一步都对应一次真实缺陷）：
> - `bc0dac56…`（00:25）：缺少「取回系统已连接设备」的发现路径，遥控器一旦在系统蓝牙里配对上就连不上。
> - `b9f31c0e…`（01:01）：补上该路径，但设置页两项控件只写偏好、不推运行时；模式选项仍叫「点按开关」。
> - `8a35cbb8…`（01:18）：纳入设置同步修复与「按住说话 / 按一次说话」用语。
> - `4865dbe7…`（01:25）：只加了诊断日志。
> - 本版（01:28）：修掉**连错设备**——准入规则曾把「同一 ATVV 服务」当成型号身份，会连上
>   小米语音遥控器并在界面上显示「已连接」。旧包均已由构建脚本移入废纸篓。
> - 当前版（01:46，`e38b8b14…`）：修掉**语音流零音频**——HTT 交互模型下宿主补发 `MIC_OPEN`
>   被样机当成新请求，正在推送的流被拆掉。详见下文「语音流根因」。
>   01:50 已启动该版并确认连接阶段能产出新增证据行（`ATVV CAPABILITIES DETAIL … raw=…`、
>   `BLE LINK maxWriteNoResp=…`）；`ATVV AUDIO notify` 与 `ATVV MIC_OPEN skipped` 两行**需要按一次语音键**
>   才会出现，属用例 2 的待验项。
>
> ⚠️ 因此 01:18 那一版记录在案的真机证据（`frame=120`）**实际是小米语音遥控器的协商结果**，
> 不能当作 Chromecase 已验证。本型号的协商结果是 `frame=247`。

### 连错设备的教训（2026-09-15）

`AB5E0001-5A21-4F05-BC7D-AF01F617B664` 是**通用 ATVV 服务**，不是本品专有：同一仓库的
小米语音遥控器用的就是它。因此 `retrieveConnectedPeripherals(withServices:)` 会一次取回
**两台**遥控器；若把「服务存在」当成型号身份，就会连上错误的设备——面板显示「已连接」，
而真遥控器按语音键毫无反应。

区分设备只看 `name=` 与 `frame=`：

| 设备 | 名字 | 协商 frame |
| --- | --- | --- |
| Chromecase 语音遥控器（本型号） | `Chromecast Remote` | `247` |
| 小米蓝牙语音遥控器 | `小米蓝牙语音遥控器` | `120` |

正确的准入规则是**名字匹配优先**，名字存在但对不上就忽略（即使服务存在）；只有在完全没有名字
可用时才退回按服务采纳。冻结来源 vRemoter 1.1.1 正是这么做的（它的发现谓词把服务判断显式
丢弃，注释写明「多款语音遥控器会广播同一个 ATVV 服务 UUID」）。

### 语音流根因：HTT 下补发 `MIC_OPEN`（2026-09-15 01:32 真机）

现象：按语音键后豆包输入法的电平图**有反应但没有波动**；整段收音在日志里是
`CHROMECASE VOICE phase=completed … audio_batches=0 audio_samples=0`，录音资产只有 557 字节。

关键日志（`pid=83434`，一次 1.33 秒的按住）：

```
ATVV CONTROL source=control opcode=0x04 bytes=4      ← 远端 AUDIO_START(reason=0x03, codec=2, stream=14)
VOICE INTENT start generation=2
ATVV MIC_OPEN written attempt=1 generation=2         ← 宿主在 11ms 后补发 0x0c00
ATVV STREAM START reason=0x03 stream=14 codec=2 generation=2
ATVV CONTROL source=control opcode=0x04 bytes=4      ← 远端改发 AUDIO_START(reason=0x00, stream=0)
ATVV STREAM START reason=0x00 stream=0 codec=2 generation=2
…（此后 289ms 到松键，AB5E0003 上一个字节都没有）…
ATVV CONTROL source=control opcode=0x00 bytes=2      ← 远端 AUDIO_STOP(reason=0x02)
CHROMECASE VOICE phase=completed … audio_batches=0 audio_samples=0
```

对照 Google *Voice over BLE* 1.0 规范（来源文件 `Google_Voice_over_BLE_spec_v1.0.pdf`；
排查时提取的纯文本副本放在 `/tmp/atvv-spec.txt`，属临时文件，**不入库**——该 PDF 为 Google
发布的公开规范，许可证未随文说明，不放公共仓库），根因是**宿主在 HTT 流进行中补发了 `MIC_OPEN`**：

| 事实 | 规范出处 | 含义 |
| --- | --- | --- |
| `AUDIO_START.reason` 是**交互模型**，不是「谁按了键」 | 4.3.1 | `0x00`=`MIC_OPEN` 触发、`0x01`=PTT、`0x03`=HTT |
| `CAPS_RESP.interaction` = `0x00`/`0x01`/`0x03` | 3 | 本机样机协商值为 **`0x03`（HTT，按住说话）** |
| HTT 下「按下即发 `AUDIO_START` 并开始推流，松键即 `AUDIO_STOP`」 | 4.5.3 | 远端**自己**开麦，宿主只需消费 |
| HTT/PTT 进行中收到 `MIC_OPEN`，远端只应回 `MIC_OPEN_ERROR(0x0F80)`，**不得打断音频** | 4.7.5 | 宿主补发 `MIC_OPEN` 是非法打断 |
| `AUDIO_START` 的 `stream id`：`reason=0x00` 时固定 `0x00`，否则远端自增 `0x01..0x80` | 4.3.1 | 日志里 `14`→`15` 逐次自增，`0` 是宿主请求流的专用值 |
| `MIC_CLOSE`/`MIC_EXTEND` 的 `stream id`：`0x00`/`0x01..0x80`/`0xFF` 三类语义 | 4.4 | 关错了流只会被远端忽略 |

即：远端**已经在推** `stream=14` 的 HTT 流，宿主 11ms 后补发的 `MIC_OPEN` 让它改成了
`stream=0` 的宿主请求流，此后一个音频帧都不再来。规范假设远端会回 `MIC_OPEN_ERROR`
且不打断，本机样机不遵守这一点，因此**只能由宿主不补发**。

修复（私有包 `dbfdce9`）：

1. HTT/PTT（`reason=0x01`/`0x03`）下**不补发 `MIC_OPEN`**；只有 On-request（`startSearch`，`opcode=0x08`）
   与「点按保持持续流」两条路径才发 `MIC_OPEN`。
2. `MIC_CLOSE` 只关闭**宿主打开且尚未关闭**的流，`stream id` 用 `0x00`；远端发起的流由远端
   用 `AUDIO_STOP(0x02)` 自行停止，不再补发（多发的会被远端按 4.7.3 忽略）。
3. 续流改用 `MIC_EXTEND` 并按流来源取 `stream id`（宿主 `0x00`，远端用远端分配值）。
   规范 4.6.1 的「音频传输超时」建议 15 s~1 min，长按必须靠它顶回去。
4. 补上此前完全缺失的证据链（见下节新增日志行）。

> ⚠️ 修复前记录的 `audio_batches=0` 不能用来判断「远端没有推流」——当时 AB5E0003 上的通知
> 既没有计数也没有日志。修复后的日志会直接给出 `ATVV AUDIO notify count=` 与 `total=`。

### 已确认（2026-09-15 01:29:01，本机真机）

遥控器已配对至系统蓝牙的前提下启动本包，链路在 **0.2 秒内**自动打通，**不需要先断开系统蓝牙**：

```
BLE SYSTEM CONNECTED CANDIDATES count=2 names=Chromecast Remote | 小米蓝牙语音遥控器
BLE SYSTEM CONNECTED ADOPTED model=chromecast-voice-remote
CHROMECASE CONNECTION state=connecting model=chromecast-voice-remote sequence=1
BLE CONNECTING source=connected_peripheral model=chromecast-voice-remote
BLE CONNECTED model=chromecast-voice-remote
BLE CHARACTERISTIC uuid=AB5E0002 props=write,writeNoResp
BLE CHARACTERISTIC uuid=AB5E0003 props=read,notify
BLE CHARACTERISTIC uuid=AB5E0004 props=read,notify
ATVV CAPABILITIES requested attempt=1
ATVV CONTROL source=control opcode=0x0b bytes=9
ATVV CAPABILITIES version=0x0100 codec=2 frame=247
ATVV CAPABILITIES DETAIL interaction=0x03 remote_mic=true raw=0b0100020300f70100
ATVV READY version=0x0100 codec=2 interaction=0x03 remote_mic=true frame=247 fallback=false
BLE LINK maxWriteNoResp=182 maxWriteResp=512
CHROMECASE CONNECTION state=available model=chromecast-voice-remote sequence=3
CHROMECASE LINK state=connected(displayName: "Chromecase 语音遥控器")
CHROMECASE STATUS Chromecase 语音遥控器 已连接
```

两条关键事实：
1. **ATVV 服务是通用的**：本机同时命中两台遥控器（`count=2`），身份只能由名字决定。
2. 该服务真实暴露**三个特征**，没有额外的按键通道——`…0002` write、`…0003` notify、
   `…0004` notify。语音键事件只可能从 `…0004` 来。

其中 `interaction=0x03` 与 `remote_mic=true` 是本型号语音链路的关键参数：它声明
**HTT（按住说话）** 交互模型，即远端按下语音键后**自己**开麦并推流（规范 4.5.3）。
`ATVV CAPABILITIES DETAIL` 的 `raw=` 是 9 字节原始 payload
（`opcode(1)+version(2)+codecs(1)+interaction(1)+frame(2)+extraConfig(1)+reserved(1)`），
按日志原样（无空格）摘录。2026-09-15 01:50 实测值为 `0b0100020300f70100`，即
`version=0x0100`、`codecs=0x02`、`interaction=0x03`、`frame=0x00f7=247`、`extraConfig=0x01`、`reserved=0x00`。
**这一行必须整段原样留证**，不要拿「协商值」去还原原始字节。

`BLE LINK maxWriteNoResp` 是本链路单包真实容量（≈ATT_MTU−3），要与 `frame=` 对照着看：
`frame=247` 大于该值时，远端「期望的包大小」在这条链路上无法整包发送。
但注意它**不是常数**：同一台样机 01:29 会话是 `182`、01:50 会话是 `244`（`frame` 始终 `247`），
说明每次连接的 ATT MTU 协商结果会变，每轮都必须重读，不能沿用上一轮的数字。

这证明：发现路径、BLE 连接、服务发现与 ATVV 能力协商（v1.0 / 16 kHz IMA ADPCM / 247 字节帧、
HTT 交互模型）在真实硬件上全部可用。**它不等于语音链路已验收**——用例 2 起的收音、首字、
尾字与异常路径仍待执行。

> 日志前缀分工：包内只写 `BLE …` 与 `ATVV …`；`CHROMECASE …` 全部由宿主写出。
> 因此排查协议问题看 `BLE`/`ATVV`，排查宿主接线与语音会话看 `CHROMECASE`。

**当前生效的语音键模式可以在日志里直接读到**，每次开始收音都会带上：

```
CHROMECASE VOICE phase=started result=triggered audio_source=chromecase_microphone route=MiRemoteV_2ch mode=toggle
```

末段 `mode=` 就是运行时实际采用的模式（`toggle` / `hold`），与界面选择应当一致；不一致即为接线缺陷。

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
   - 特别注意别打开 `/Applications/SayAll.app`（构建号更大但**不含 Chromecase**）。用
     `open /Users/andy/MySrc/remote-mic-app-chromecase/dist/SayAll.app` 显式打开本表那份。
2. 确认已安装 `MiRemoteV 2ch` 音频设备（侧边栏「连接」→「连接与语音」页的「音频输入与兼容」面板应显示已就绪）。本次不安装任何 helper。
3. 在侧边栏「设置」页的「权限与隐私」区授予蓝牙、输入监控和辅助功能权限，然后完全退出并重新打开 App。
4. 打开 `~/Library/Logs/RemoteMic/runtime.log`，保留现有文件，不清空、不覆盖。
   - 建议直接双击 `Testing/启动Chromecase真机测试.command`，它会实时过滤出本手册用到的日志行，并在桌面留一份会话记录。
5. 进入侧边栏**「连接」**（链接图标，页面标题「连接与语音」），在右列第三块找到「Chromecase 遥控器」面板——总开关在**这一页**，不在「设置」页（「设置」页只有权限、通用、诊断与日志）。
   - 面板长相见 `Testing/artifacts/chromecase-layout/`（由 App 自带离屏渲染导出，非截图拼贴）：
     `connection-zh-Hans-light-1400x2000.png` 是「连接与语音」页，`settings-zh-Hans-light-1400x2000.png`
     是「设置」页——后者没有该面板，正是本条要说明的对照。
6. 确认遥控器可被 App 发现。**这里有两种情况，都必须能连上**：

   | 情况 | 遥控器状态 | App 应走的发现路径 |
   | --- | --- | --- |
   | A | 未与 Mac 建立连接，正在广播 | `BLE SCANNING` → `BLE CONNECTING source=scan` |
   | B | **已在「系统设置 → 蓝牙」里配对/连接**（或已被系统当作 HID 设备占用） | `BLE SYSTEM CONNECTED CANDIDATES` → `BLE SYSTEM CONNECTED ADOPTED` → `BLE CONNECTING source=connected_peripheral` |

   情况 B 是被动出现的：BLE 设备一旦与主机建立连接就**停止广播**，只靠扫描的链路会永远停在
   「正在搜索遥控器」。App 必须能取回系统已连接的设备并主动连上它。

   ⚠️ 情况 B 有一个必须核对的点：**ATVV 服务是通用的**，本机若同时接着小米语音遥控器，
   `BLE SYSTEM CONNECTED CANDIDATES count=` 会是 `2`。此时必须确认紧接着那句
   `ATVV CAPABILITIES … frame=` 是 **`247`**；如果是 `120`，说明连上的是小米遥控器，
   本遥控器的语音键不会产生任何事件（见上文「连错设备的教训」）。
7. 状态应从「正在搜索遥控器」变为「已连接」。**没有 `state=available`、或 `frame=` 不是 `247`，
   就不要往下测。**
8. 若长时间停在「正在搜索遥控器」，先看日志：
   - 完全没有 `BLE DISCOVERED UNMATCHED`、也没有 `BLE SYSTEM CONNECTED CANDIDATES`：遥控器既没广播、也没被系统连接，多半是没唤醒或不在配对模式。
   - 有 `BLE DISCOVERED UNMATCHED name=...`：设备在广播但名字对不上，记下该名字（匹配规则冻结自 vRemoter，不得擅自放宽）。
   - 有 `BLE SYSTEM CONNECTED CANDIDATES count=1 names=小米蓝牙语音遥控器`：只有小米那台被系统连接，本遥控器需要先唤醒或重新配对。

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

**同时必须核对连上的是本型号**：`ATVV CAPABILITIES … frame=` 应为 `247`。若为 `120`，说明采纳了同协议的小米语音遥控器，本用例不通过。

失败判定：状态长期停在「正在搜索」；或断连后仍显示已连接；或第 4 步只能靠先断开系统蓝牙才能连上；或 `frame=` 是 `120`。

### 用例 2：toggle 模式——按一下开始、再按一下结束（默认模式）

确认面板（侧边栏「连接」→「连接与语音」页 →「Chromecase 遥控器」）语音键模式为「按一次说话」。

1. 按一下遥控器语音键，说一句话后停顿几秒（**先不要**再按）。
2. 观察录音/识别是否持续进行（这正是与 Siri Remote 的核心差异）。
3. 再按一下语音键。

预期：
- 第 1 次按下即开始收音，且**不结束**；用户可见"正在收音"状态保持。
- 第 2 次按下才结束。
- 日志出现 `ATVV CONTROL source=control opcode=0x04 bytes=4`（本型号是 HTT：远端按下即自行起流），
  随后才是 `CHROMECASE VOICE phase=started`。
- **按下期间不得出现 `ATVV MIC_OPEN written`**：本型号远端自己开麦，宿主补发会被样机当成新请求、
  拆掉正在推送的流（规范 4.7.5 明令禁止，详见上文「语音流根因」）。
- **必须有 `ATVV AUDIO notify count=` 持续增长**，这是「远端真的在推音频」的唯一直接证据。
  只有它非零，才谈得上电平图波动。
- 一次性点按（松键）后应看到 `ATVV MIC_OPEN written … bytes=0c00`（这一步才是宿主主动请求持续流），
  以及后续的 `ATVV MIC_EXTEND stream=0`（每 4 秒一次，把远端的「音频传输超时」顶回去）。
- 完整序列：`CHROMECASE VOICE phase=started` → `CHROMECASE VOICE phase=sustain result=no_visible_change`（可能有多次）→ `CHROMECASE VOICE playback_stop phase=waiting_for_drain` → `CHROMECASE AUDIO playback_stop phase=completed result=drained`。

⚠️ **点按必须短于 0.55 秒**：超过 0.55 秒按合同即为「按住（HOLD）」，无论当前是哪种模式都会在松键时结束收音
（`completion=normal reason=hold_release`），那不是缺陷。要验证「按一次说话」的持续收音，请**快速点按**。

**若按了键却连一条 `ATVV CONTROL` 都没有**，说明远端压根没发出控制帧——此时不要继续测语音，
把该次日志（含 `BLE CHARACTERISTIC` 与 `BLE SYSTEM CONNECTED CANDIDATES` 两行）整段留证。
反过来，有 `ATVV CONTROL` 但没有 `CHROMECASE VOICE`，是宿主接线问题；有 `CHROMECASE VOICE` 但
`ATVV AUDIO notify` 从不出现，是远端没有推流（协议层问题）。三者必须分清。

失败判定：第 1 次点按后立刻结束收音；或持续收音期间输入法识别被反复关闭（说明换流被当成了新的用户动作）。

### 用例 2b：`frame=` 与链路容量的对照（本版新增的判断题）

修复后，连接阶段会多出两行：`ATVV CAPABILITIES DETAIL … raw=…` 与 `BLE LINK maxWriteNoResp=…`。

1. 记录 `frame=`（远端期望的音频包大小）与 `maxWriteNoResp=`（本链路单包真实容量 ≈ ATT_MTU−3）。

预期：`frame` 大于 `maxWriteNoResp` 时属于**正常但需要留意**的情况——规范 4.2.2 说明 `frame` 只是
「用于音频帧计数的期望值，可以是任意值」，本实现按 v1.0 连续字节流解码，不依赖整包到达。
只要 `ATVV AUDIO notify` 非零且电平有波动，即视为通过。

失败判定：`ATVV AUDIO notify` 一直为零（远端据此拒绝推流）——这时要把两行数值一并留证，
它是把「远端不发」与「链路装不下」分开的唯一依据。

### 用例 3：hold 模式

把模式切到「按住说话」。切换后**立即生效**，无需重启（面板改动会即时同步到运行时）。

1. 按住语音键说话，中途松开。

预期：按住期间收音，松开即结束；`completion=normal reason=hold_release`。

切换后先核对运行时是否真的换了模式：开始收音那行日志的末段应为 `mode=hold`。若界面已切而日志仍是 `mode=toggle`，即为接线缺陷，本用例结论无效。

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
| 链路单包容量（MTU 代理） | `BLE LINK maxWriteNoResp=` |
| 能力协商原文 | `ATVV CAPABILITIES DETAIL interaction=`、`ATVV READY … interaction=… remote_mic=…` |
| 远端是否在推音频（最关键） | `ATVV AUDIO notify count=… bytes=… total=… head=…`；被丢弃时为 `ATVV AUDIO dropped_phase=` |
| 开始收音 | `CHROMECASE VOICE phase=started` |
| 持续收音（不得有用户可见动作） | `CHROMECASE VOICE phase=sustain result=no_visible_change` |
| 音频路由 | `CHROMECASE AUDIO routed source=chromecase_microphone route=virtual_audio device=MiRemoteV_2ch` |
| 结束与排空 | `CHROMECASE VOICE playback_stop phase=waiting_for_drain`、`CHROMECASE AUDIO playback_stop phase=completed result=drained` |
| 结束原因 | `completion=normal`（hold 松键 / 第二次点按）、`completion=forced`（断连、取消、宿主关闭） |
| 包内协议 | `ATVV MIC_OPEN written`（含 `bytes=`）、`ATVV MIC_OPEN skipped reason=remote_initiated_stream`、`ATVV MIC_CLOSE written` / `skipped`、`ATVV MIC_EXTEND stream=`、`ATVV STREAM START/STOP`（含 `origin=`）、`VOICE INTENT` |

判读要点：`ATVV MIC_OPEN written` 与 `ATVV AUDIO notify` 是两条互相独立的证据。
前者只说明宿主发了命令，后者才是远端真的在推流。**只有出现 `ATVV MIC_OPEN skipped reason=remote_initiated_stream`
且随后 `ATVV AUDIO notify count` 持续增长，才说明 HTT 路径修对了。**

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
